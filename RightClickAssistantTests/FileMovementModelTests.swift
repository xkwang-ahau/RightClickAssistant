import Foundation
import Observation
import XCTest
@testable import RightClickAssistant

@MainActor
final class FileMovementModelTests: XCTestCase {
    private let source = URL(fileURLWithPath: "/test/source/报告.txt")
    private let destination = URL(fileURLWithPath: "/test/target")

    func testMissingInputsPreventServiceCalls() async {
        let mover = StubFileMover()
        let model = WorkspaceModel(
            folderPicker: MoveFolderPicker([]), documentCreator: MoveDocumentCreator(),
            filePicker: MoveFilePicker([source]), fileMover: mover
        )
        await model.moveFile()
        XCTAssertEqual(model.moveStatus, .failed("请先选择要移动的文件。"))
        model.chooseSourceFile()
        await model.moveFile()
        XCTAssertEqual(model.moveStatus, .failed("请先选择移动目的地。"))
        let calls = await mover.callCount
        XCTAssertEqual(calls, 0)
    }

    func testCancelledSelectionsPreserveInputsAndResult() async {
        let failure = FileMoveError.alreadyExists(source.lastPathComponent)
        let model = makeModel(mover: StubFileMover(.failure(failure)))
        await model.moveFile()
        model.chooseSourceFile()
        model.chooseMoveDestination()
        XCTAssertEqual(model.sourceFile, source)
        XCTAssertEqual(model.moveDestination, destination)
        XCTAssertEqual(model.moveStatus, .failed(failure.localizedDescription))
    }

    func testSuccessClearsSourceAndPublishesActualOutput() async {
        let output = destination.appendingPathComponent(source.lastPathComponent)
        let model = makeModel(mover: StubFileMover(.success(output)))
        XCTAssertTrue(model.canMoveFile)
        await model.moveFile()
        XCTAssertNil(model.sourceFile)
        XCTAssertEqual(model.moveDestination, destination)
        XCTAssertEqual(model.moveStatus, .moved(output))
        XCTAssertFalse(model.canMoveFile)
    }

    func testFailureKeepsSourceAndAllowsSuccessfulRetry() async {
        let mover = StubFileMover(.failure(FileMoveError.accessDenied))
        let model = makeModel(mover: mover)
        await model.moveFile()
        XCTAssertEqual(model.moveStatus, .failed(FileMoveError.accessDenied.localizedDescription))
        XCTAssertEqual(model.sourceFile, source)
        XCTAssertTrue(model.canMoveFile)
        let output = destination.appendingPathComponent(source.lastPathComponent)
        await mover.setResult(.success(output))
        await model.moveFile()
        XCTAssertEqual(model.moveStatus, .moved(output))
        let calls = await mover.callCount
        XCTAssertEqual(calls, 2)
    }

    func testDuplicateMoveAndCreationAreIgnoredWhileMoving() async {
        let mover = ControlledFileMover()
        let creator = MoveDocumentCreator()
        let model = makeModel(mover: mover, creator: creator)
        let first = Task { await model.moveFile() }
        await mover.waitUntilStarted()
        XCTAssertTrue(model.isBusy)
        XCTAssertFalse(model.canMoveFile)
        XCTAssertFalse(model.canCreateDocument)
        await model.moveFile()
        await model.createDocument()
        model.startMovingFile()
        model.startCreatingDocument()
        let moveCalls = await mover.callCount
        let createCalls = await creator.callCount
        XCTAssertEqual(moveCalls, 1)
        XCTAssertEqual(createCalls, 0)
        await mover.finish(.success(destination.appendingPathComponent(source.lastPathComponent)))
        await first.value
    }

    func testPendingMoveKeepsOriginalInputsAndIgnoresSelection() async throws {
        let mover = ControlledFileMover()
        let files = MoveFilePicker([source, URL(fileURLWithPath: "/test/other")])
        let folders = MoveFolderPicker([destination, URL(fileURLWithPath: "/test/other-folder")])
        let model = WorkspaceModel(
            folderPicker: folders, documentCreator: MoveDocumentCreator(),
            filePicker: files, fileMover: mover
        )
        model.chooseSourceFile()
        model.chooseMoveDestination()
        let first = Task { await model.moveFile() }
        await mover.waitUntilStarted()
        model.chooseSourceFile()
        model.chooseMoveDestination()
        model.chooseCreationDirectory()
        model.clearCreationDirectory()
        model.clearMoveDestination()
        model.handleFinderURL(try XCTUnwrap(URL(string: "rightclickassistant://finder?action=move&path=/test/other")))
        XCTAssertEqual(model.finderRequestMessage, "当前文件操作尚未完成，请完成后重新点击 Finder 菜单。")
        let request = await mover.request
        XCTAssertEqual(request?.source, source)
        XCTAssertEqual(request?.destination, destination)
        XCTAssertEqual(files.callCount, 1)
        XCTAssertEqual(folders.callCount, 1)
        XCTAssertEqual(model.sourceFile, source)
        XCTAssertEqual(model.moveDestination, destination)
        await mover.finish(.failure(FileMoveError.accessDenied))
        await first.value
    }

    func testMovingIsIgnoredWhileCreationIsPending() async throws {
        let creator = MoveControlledCreator()
        let mover = StubFileMover()
        let folders = MoveFolderPicker([destination, URL(fileURLWithPath: "/test/create")])
        let model = WorkspaceModel(
            folderPicker: folders, documentCreator: creator,
            filePicker: MoveFilePicker([source]), fileMover: mover
        )
        model.chooseMoveDestination()
        model.chooseSourceFile()
        model.chooseCreationDirectory()
        let task = Task { await model.createDocument() }
        await creator.waitUntilStarted()
        model.clearCreationDirectory()
        model.clearMoveDestination()
        XCTAssertEqual(model.creationDirectory, URL(fileURLWithPath: "/test/create"))
        XCTAssertEqual(model.moveDestination, destination)
        model.handleFinderURL(try XCTUnwrap(URL(string: "rightclickassistant://finder?action=word&path=/test/other")))
        XCTAssertEqual(model.creationDirectory, URL(fileURLWithPath: "/test/create"))
        XCTAssertEqual(model.finderRequestMessage, "当前文件操作尚未完成，请完成后重新点击 Finder 菜单。")
        await model.moveFile()
        model.startMovingFile()
        XCTAssertEqual(model.moveStatus, .idle)
        XCTAssertEqual(model.sourceFile, source)
        let calls = await mover.callCount
        XCTAssertEqual(calls, 0)
        await creator.finish()
        await task.value
    }

    func testClosingCancelsOwnedMoveTaskAndKeepsSource() async {
        let mover = ControlledFileMover()
        let model = makeModel(mover: mover)
        model.startMovingFile()
        await mover.waitUntilStarted()
        let changed = expectation(description: "Move leaves pending state")
        withObservationTracking {
            _ = model.moveStatus
        } onChange: {
            changed.fulfill()
        }
        model.cancelPendingOperations()
        await mover.finish(.failure(CancellationError()))
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(model.moveStatus, .idle)
        XCTAssertEqual(model.sourceFile, source)
        let cancelled = await mover.wasCancelled
        XCTAssertTrue(cancelled)
        XCTAssertTrue(model.canMoveFile)
    }

    func testReselectionClearsOldFailure() async {
        let model = WorkspaceModel(
            folderPicker: MoveFolderPicker([destination, destination]), documentCreator: MoveDocumentCreator(),
            filePicker: MoveFilePicker([source, source]), fileMover: StubFileMover()
        )
        model.chooseSourceFile()
        model.chooseMoveDestination()
        await model.moveFile()
        model.chooseSourceFile()
        XCTAssertEqual(model.moveStatus, .idle)
        await model.moveFile()
        model.chooseMoveDestination()
        XCTAssertEqual(model.moveStatus, .idle)
    }

    private func makeModel(mover: any FileMoving) -> WorkspaceModel {
        makeModel(mover: mover, creator: MoveDocumentCreator())
    }

    private func makeModel(mover: any FileMoving, creator: any DocumentCreating) -> WorkspaceModel {
        let model = WorkspaceModel(
            folderPicker: MoveFolderPicker([destination, nil]), documentCreator: creator,
            filePicker: MoveFilePicker([source, nil]), fileMover: mover
        )
        model.chooseSourceFile()
        model.chooseMoveDestination()
        return model
    }
}

@MainActor
private final class MoveFolderPicker: FolderPicking {
    private var selections: [URL?]
    private(set) var callCount = 0
    init(_ selections: [URL?]) { self.selections = selections }
    func chooseFolder(title: String, initialDirectory: URL?) -> URL? {
        callCount += 1
        return selections.isEmpty ? nil : selections.removeFirst()
    }
}

@MainActor
private final class MoveFilePicker: FilePicking {
    private var selections: [URL?]
    private(set) var callCount = 0
    init(_ selections: [URL?]) { self.selections = selections }
    func chooseFile(title: String, initialDirectory: URL?) -> URL? {
        callCount += 1
        return selections.isEmpty ? nil : selections.removeFirst()
    }
}

private actor StubFileMover: FileMoving {
    private var result: Result<URL, Error>
    private(set) var callCount = 0
    init(_ result: Result<URL, Error> = .failure(FileMoveError.accessDenied)) { self.result = result }
    func setResult(_ result: Result<URL, Error>) { self.result = result }
    func moveFile(at source: URL, to directory: URL, name: String, replaceExisting: Bool) throws -> URL {
        callCount += 1
        return try result.get()
    }
}

private actor MoveDocumentCreator: DocumentCreating {
    private(set) var callCount = 0
    init() {}

    func createDocument(type: DocumentType, name: String, in directory: URL) throws -> URL {
        callCount += 1
        throw DocumentCreationError.invalidDirectory
    }
}

private actor ControlledFileMover: FileMoving {
    struct Request: Sendable {
        let source: URL
        let destination: URL
    }
    private(set) var request: Request?
    private(set) var callCount = 0
    private(set) var wasCancelled = false
    private var continuation: CheckedContinuation<URL, Error>?
    private var started: CheckedContinuation<Void, Never>?
    func moveFile(at source: URL, to directory: URL, name: String, replaceExisting: Bool) async throws -> URL {
        callCount += 1
        request = Request(source: source, destination: directory)
        defer { wasCancelled = Task.isCancelled }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        guard request == nil else { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ result: Result<URL, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

private actor MoveControlledCreator: DocumentCreating {
    private var continuation: CheckedContinuation<URL, Error>?
    private var started: CheckedContinuation<Void, Never>?
    private var isStarted = false
    func createDocument(type: DocumentType, name: String, in directory: URL) async throws -> URL {
        isStarted = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        guard !isStarted else { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}
