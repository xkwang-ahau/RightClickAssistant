import Foundation
import Observation
import XCTest
@testable import rightchick

@MainActor
final class FinderRequestModelTests: XCTestCase {
    func testCreationRequestCreatesDirectlyWithoutAnyPicker() async throws {
        let directory = URL(fileURLWithPath: "/Users/test/Desktop")
        let folders = FinderTestFolderPicker([])
        let files = FinderTestFilePicker([])
        let service = FinderTestService()
        let model = makeModel(folders: folders, files: files, service: service)
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .excel, location: directory).url))
        XCTAssertTrue(folders.initialDirectories.isEmpty)
        XCTAssertTrue(files.initialDirectories.isEmpty)
        XCTAssertEqual(model.creationDirectory, directory)
        XCTAssertEqual(model.selectedDocumentType, .excel)
        XCTAssertEqual(model.creationStatus, .creating)
        await waitUntilCreationFinishes(model)
        let request = await service.lastRequest
        XCTAssertEqual(request?.type, .excel)
        XCTAssertEqual(request?.name, "新建 Excel 文档")
        XCTAssertEqual(request?.directory, directory)
        XCTAssertEqual(model.creationStatus, .created(directory.appendingPathComponent("新建 Excel 文档.xlsx")))
        XCTAssertEqual(model.finderResultURL, directory.appendingPathComponent("新建 Excel 文档.xlsx"))
    }

    func testConsecutiveCreationsInDifferentFoldersUseTheirOwnFolderWithoutPicker() async throws {
        let first = URL(fileURLWithPath: "/Volumes/USB/工作")
        let second = URL(fileURLWithPath: "/Users/test/Documents/项目")
        let folders = FinderTestFolderPicker([])
        let files = FinderTestFilePicker([])
        let service = FinderTestService()
        let model = makeModel(folders: folders, files: files, service: service)
        for directory in [first, second] {
            model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .word, location: directory).url))
            await waitUntilCreationFinishes(model)
            XCTAssertEqual(model.creationDirectory, directory)
            let request = await service.lastRequest
            XCTAssertEqual(request?.directory, directory)
        }
        XCTAssertTrue(folders.initialDirectories.isEmpty)
        XCTAssertTrue(files.initialDirectories.isEmpty)
        let calls = await service.calls
        XCTAssertEqual(calls, 2)
    }

    func testDuplicateCreationRequestCannotChangeQueuedCreation() async throws {
        let directory = URL(fileURLWithPath: "/Users/test/Desktop")
        let folders = FinderTestFolderPicker([])
        let service = FinderTestService()
        let model = makeModel(folders: folders, files: FinderTestFilePicker([]), service: service)
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .word, location: directory).url))
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .excel, location: directory).url))
        XCTAssertEqual(model.selectedDocumentType, .word)
        await waitUntilCreationFinishes(model)
        let calls = await service.calls
        XCTAssertEqual(calls, 1)
    }

    func testCreationFailureIsVisibleAndCancellationDoesNotReportSuccess() async throws {
        for failure: Error in [DocumentCreationError.accessDenied, CancellationError()] {
            let directory = URL(fileURLWithPath: "/Users/test/Desktop")
            let service = FinderTestService(failure: failure)
            let model = makeModel(folders: FinderTestFolderPicker([]), service: service)
            model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .word, location: directory).url))
            await waitUntilCreationFinishes(model)
            if failure is CancellationError {
                XCTAssertEqual(model.creationStatus, .idle)
                XCTAssertEqual(model.finderRequestMessage, "已取消新建文档。")
                XCTAssertNil(model.finderResultURL)
            } else {
                XCTAssertEqual(model.creationStatus, .failed(failure.localizedDescription))
                XCTAssertEqual(model.finderRequestMessage, failure.localizedDescription)
                XCTAssertNil(model.finderResultURL)
            }
        }
    }

    func testClosingImmediatelyCancelsQueuedAutomaticCreation() async throws {
        let directory = URL(fileURLWithPath: "/Users/test/Desktop")
        let service = FinderTestService()
        let model = makeModel(folders: FinderTestFolderPicker([]), service: service)
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .word, location: directory).url))
        model.cancelPendingOperations()
        await waitUntilCreationFinishes(model)
        XCTAssertEqual(model.creationStatus, .idle)
        let calls = await service.calls
        XCTAssertEqual(calls, 0)
    }

    func testMoveMenuUsesFinderFileDirectlyAndChosenDestination() async throws {
        let source = URL(fileURLWithPath: "/Users/test/Desktop/新建 Word 文档.docx")
        let destination = URL(fileURLWithPath: "/Users/test/Documents")
        let files = FinderTestFilePicker([])
        let folders = FinderTestFolderPicker([destination])
        let service = FinderTestService()
        let model = makeModel(folders: folders, files: files, service: service)
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .move, location: source).url))
        XCTAssertTrue(files.initialDirectories.isEmpty, "非沙盒应用无需源文件授权面板")
        XCTAssertEqual(model.sourceFile, source)
        XCTAssertEqual(model.moveStatus, .moving)
        XCTAssertNil(model.finderResultURL)
        await waitUntilMoveFinishes(model)
        let output = destination.appendingPathComponent(source.lastPathComponent)
        XCTAssertEqual(model.moveStatus, .moved(output))
        XCTAssertEqual(model.finderResultURL, output)
        XCTAssertNil(model.sourceFile)
        let request = await service.lastMoveRequest
        XCTAssertEqual(request?.source, source)
        XCTAssertEqual(request?.destination, destination)
    }

    func testCancellingDestinationPreservesInputsAndNeverCallsService() async throws {
        let originalSource = URL(fileURLWithPath: "/test/original.txt")
        let originalDestination = URL(fileURLWithPath: "/test/original-destination")
        let source = URL(fileURLWithPath: "/Users/test/Desktop/报告.txt")
        let files = FinderTestFilePicker([originalSource])
        let folders = FinderTestFolderPicker([originalDestination, nil])
        let service = FinderTestService()
        let model = makeModel(folders: folders, files: files, service: service)
        model.chooseSourceFile()
        model.chooseMoveDestination()
        let sourcePickerCalls = files.initialDirectories.count
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .move, location: source).url))
        XCTAssertEqual(model.finderRequestMessage, "已取消移动，文件位置未改变。")
        XCTAssertEqual(model.sourceFile, originalSource)
        XCTAssertEqual(model.moveDestination, originalDestination)
        XCTAssertEqual(model.moveStatus, .idle)
        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(files.initialDirectories.count, sourcePickerCalls)
        let calls = await service.calls
        XCTAssertEqual(calls, 0)
    }

    func testMoveMenuRejectsDuplicateRequestsAndReportsFailure() async throws {
        let source = URL(fileURLWithPath: "/Users/test/Desktop/报告.txt")
        let destination = URL(fileURLWithPath: "/Users/test/Documents")
        let failure = FileMoveError.accessDenied
        let service = FinderTestService(failure: failure)
        let folders = FinderTestFolderPicker([destination])
        let model = makeModel(folders: folders, service: service)
        let url = try XCTUnwrap(FinderRequest(action: .move, location: source).url)
        model.handleFinderURL(url)
        model.handleFinderURL(url)
        XCTAssertEqual(folders.initialDirectories.count, 1)
        await waitUntilMoveFinishes(model)
        XCTAssertEqual(model.moveStatus, .failed(failure.localizedDescription))
        XCTAssertEqual(model.finderRequestMessage, failure.localizedDescription)
        XCTAssertNil(model.finderResultURL)
        let calls = await service.calls
        XCTAssertEqual(calls, 1)
    }

    func testMoveDestinationPanelRejectsNestedRequests() async throws {
        let source = URL(fileURLWithPath: "/Users/test/Desktop/报告.txt")
        let destination = URL(fileURLWithPath: "/Users/test/Documents")
        let folders = FinderTestFolderPicker([destination])
        let model = makeModel(folders: folders, service: FinderTestService())
        let url = try XCTUnwrap(FinderRequest(action: .move, location: source).url)
        folders.onChoose = { model.handleFinderURL(url) }
        model.handleFinderURL(url)
        await waitUntilMoveFinishes(model)
        XCTAssertEqual(folders.initialDirectories.count, 1)
        XCTAssertEqual(model.moveStatus, .moved(destination.appendingPathComponent(source.lastPathComponent)))
    }

    func testCancellingQueuedMenuMoveDoesNotReportSuccessOrCallMover() async throws {
        let source = URL(fileURLWithPath: "/Users/test/Desktop/报告.txt")
        let service = FinderTestService()
        let model = makeModel(
            folders: FinderTestFolderPicker([URL(fileURLWithPath: "/Users/test/Documents")]),
            service: service
        )
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .move, location: source).url))
        model.cancelPendingOperations()
        await waitUntilMoveFinishes(model)
        XCTAssertEqual(model.moveStatus, .idle)
        XCTAssertNil(model.finderResultURL)
        XCTAssertEqual(model.sourceFile, source)
        XCTAssertEqual(model.finderRequestMessage, "已取消移动。")
        let calls = await service.calls
        XCTAssertEqual(calls, 0)
    }

    func testMoveConflictKeepBothRenamesAndKeepsExisting() async throws {
        let source = URL(fileURLWithPath: "/Users/test/Desktop/报告.txt")
        let destination = URL(fileURLWithPath: "/Users/test/Documents")
        let service = ConflictingFinderMoveService(existingName: source.lastPathComponent)
        let resolver = StubMoveConflictResolver(.keepBoth)
        let model = WorkspaceModel(
            folderPicker: FinderTestFolderPicker([destination]), documentCreator: service,
            filePicker: FinderTestFilePicker([]), fileMover: service, moveConflictResolver: resolver
        )
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .move, location: source).url))
        await waitUntilMoveFinishes(model)
        let expected = destination.appendingPathComponent("报告 (2).txt")
        XCTAssertEqual(model.moveStatus, .moved(expected))
        XCTAssertEqual(model.finderResultURL, expected)
        XCTAssertEqual(resolver.calls, 1)
        let attempts = await service.attempts
        XCTAssertEqual(attempts, [
            .init(name: "报告.txt", replaceExisting: false),
            .init(name: "报告 (2).txt", replaceExisting: false),
        ])
    }

    func testMoveConflictReplaceReplacesExisting() async throws {
        let source = URL(fileURLWithPath: "/Users/test/Desktop/报告.txt")
        let destination = URL(fileURLWithPath: "/Users/test/Documents")
        let service = ConflictingFinderMoveService(existingName: source.lastPathComponent)
        let resolver = StubMoveConflictResolver(.replace)
        let model = WorkspaceModel(
            folderPicker: FinderTestFolderPicker([destination]), documentCreator: service,
            filePicker: FinderTestFilePicker([]), fileMover: service, moveConflictResolver: resolver
        )
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .move, location: source).url))
        await waitUntilMoveFinishes(model)
        XCTAssertEqual(model.moveStatus, .moved(destination.appendingPathComponent("报告.txt")))
        XCTAssertEqual(resolver.calls, 1)
        let attempts = await service.attempts
        XCTAssertEqual(attempts, [
            .init(name: "报告.txt", replaceExisting: false),
            .init(name: "报告.txt", replaceExisting: true),
        ])
    }

    func testMoveConflictCancelLeavesEverythingUnchanged() async throws {
        let source = URL(fileURLWithPath: "/Users/test/Desktop/报告.txt")
        let destination = URL(fileURLWithPath: "/Users/test/Documents")
        let service = ConflictingFinderMoveService(existingName: source.lastPathComponent)
        let resolver = StubMoveConflictResolver(.cancel)
        let model = WorkspaceModel(
            folderPicker: FinderTestFolderPicker([destination]), documentCreator: service,
            filePicker: FinderTestFilePicker([]), fileMover: service, moveConflictResolver: resolver
        )
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .move, location: source).url))
        await waitUntilMoveFinishes(model)
        XCTAssertEqual(model.moveStatus, .idle)
        XCTAssertNil(model.finderResultURL)
        XCTAssertEqual(model.finderRequestMessage, "已取消移动；目的地同名文件保持不变。")
        XCTAssertEqual(resolver.calls, 1)
        let attempts = await service.attempts
        XCTAssertEqual(attempts.count, 1)
    }

    func testMenuMoveWithRealServiceMovesFileWithoutAnyWindowButton() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { XCTFail("Could not clean up: \(error)") }
        }
        let source = desktop.appendingPathComponent("测试.txt")
        let contents = Data("菜单移动内容".utf8)
        try contents.write(to: source)
        let service = FileOperationService()
        let model = WorkspaceModel(
            folderPicker: FinderTestFolderPicker([documents]), documentCreator: service,
            filePicker: FinderTestFilePicker([]), fileMover: service
        )
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .move, location: source).url))
        await waitUntilMoveFinishes(model)
        let output = try XCTUnwrap(model.finderResultURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(output, documents.appendingPathComponent(source.lastPathComponent))
        XCTAssertEqual(try Data(contentsOf: output), contents)
    }

    func testMenuCreateThenMoveFromDesktopToDocumentsEndToEnd() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { XCTFail("Could not clean up: \(error)") }
        }
        let service = FileOperationService()
        let model = WorkspaceModel(
            folderPicker: FinderTestFolderPicker([documents]), documentCreator: service,
            filePicker: FinderTestFilePicker([]), fileMover: service
        )
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .word, location: desktop).url))
        await waitUntilCreationFinishes(model)
        let created = try XCTUnwrap(model.finderResultURL)
        let contents = try Data(contentsOf: created)
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .move, location: created).url))
        await waitUntilMoveFinishes(model)
        let output = try XCTUnwrap(model.finderResultURL)
        XCTAssertEqual(output, documents.appendingPathComponent(created.lastPathComponent))
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
        XCTAssertEqual(try Data(contentsOf: output), contents)
    }

    func testNextMenuRequestClearsPreviousResultAndSettingsOpenDoesNotEraseIt() async throws {
        let directory = URL(fileURLWithPath: "/Users/test/Desktop")
        let model = makeModel(folders: FinderTestFolderPicker([]))
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .word, location: directory).url))
        await waitUntilCreationFinishes(model)
        let result = try XCTUnwrap(model.finderResultURL)
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .open, location: nil).url))
        XCTAssertEqual(model.finderResultURL, result)
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .move, location: result).url))
        XCTAssertNil(model.finderResultURL)
        XCTAssertEqual(model.finderRequestMessage, "已取消移动，文件位置未改变。")
    }

    func testOpenAndInvalidRequestsNeverAskForFilesystemAccess() throws {
        let folders = FinderTestFolderPicker([])
        let files = FinderTestFilePicker([])
        let model = makeModel(folders: folders, files: files)
        model.handleFinderURL(try XCTUnwrap(URL(string: "rightchick://finder?action=unsupported")))
        XCTAssertNotNil(model.finderRequestMessage)
        let message = model.finderRequestMessage
        model.handleFinderURL(try XCTUnwrap(FinderRequest(action: .open, location: nil).url))
        XCTAssertEqual(model.finderRequestMessage, message)
        XCTAssertTrue(folders.initialDirectories.isEmpty)
        XCTAssertTrue(files.initialDirectories.isEmpty)
        XCTAssertNil(model.creationDirectory)
        XCTAssertNil(model.sourceFile)
    }

    private func makeModel(
        folders: FinderTestFolderPicker? = nil,
        files: FinderTestFilePicker? = nil,
        service: FinderTestService? = nil,
        conflictResolver: (any MoveConflictResolving)? = nil
    ) -> WorkspaceModel {
        let service = service ?? FinderTestService()
        return WorkspaceModel(
            folderPicker: folders ?? FinderTestFolderPicker([]), documentCreator: service,
            filePicker: files ?? FinderTestFilePicker([]), fileMover: service,
            moveConflictResolver: conflictResolver ?? StubMoveConflictResolver(.cancel)
        )
    }

    private func waitUntilCreationFinishes(_ model: WorkspaceModel) async {
        guard model.isCreating else { return }
        let finished = expectation(description: "Automatic creation finishes")
        withObservationTracking {
            _ = model.creationStatus
        } onChange: {
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertFalse(model.isCreating)
    }

    private func waitUntilMoveFinishes(_ model: WorkspaceModel) async {
        guard model.isMoving else { return }
        let finished = expectation(description: "Menu move finishes")
        withObservationTracking {
            _ = model.moveStatus
        } onChange: {
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertFalse(model.isMoving)
    }
}

@MainActor
private final class FinderTestFolderPicker: FolderPicking {
    var selections: [URL?]
    var initialDirectories: [URL?] = []
    var onChoose: (() throws -> Void)?
    init(_ selections: [URL?]) { self.selections = selections }
    func chooseFolder(title: String, initialDirectory: URL?) -> URL? {
        initialDirectories.append(initialDirectory)
        do {
            try onChoose?()
        } catch {
            XCTFail("Nested request setup failed: \(error)")
        }
        return selections.isEmpty ? nil : selections.removeFirst()
    }
}

@MainActor
private final class FinderTestFilePicker: FilePicking {
    var selections: [URL?]
    var initialDirectories: [URL?] = []
    init(_ selections: [URL?]) { self.selections = selections }
    func chooseFile(title: String, initialDirectory: URL?) -> URL? {
        initialDirectories.append(initialDirectory)
        return selections.isEmpty ? nil : selections.removeFirst()
    }
}

@MainActor
private final class StubMoveConflictResolver: MoveConflictResolving {
    private let decision: MoveConflictDecision
    private(set) var calls = 0
    init(_ decision: MoveConflictDecision) { self.decision = decision }
    func resolve(sourceName: String, destinationPath: String) -> MoveConflictDecision {
        calls += 1
        return decision
    }
}

private actor ConflictingFinderMoveService: FileMoving, DocumentCreating {
    struct Attempt: Equatable, Sendable {
        let name: String
        let replaceExisting: Bool
    }
    private let existingName: String
    private(set) var attempts: [Attempt] = []
    init(existingName: String) { self.existingName = existingName }
    func moveFile(at source: URL, to directory: URL, name: String, replaceExisting: Bool) throws -> URL {
        attempts.append(Attempt(name: name, replaceExisting: replaceExisting))
        if !replaceExisting, name == existingName {
            throw FileMoveError.alreadyExists(name)
        }
        return directory.appendingPathComponent(name)
    }
    func createDocument(type: DocumentType, name: String, in directory: URL) throws -> URL {
        throw DocumentCreationError.invalidDirectory
    }
}

private actor FinderTestService: DocumentCreating, FileMoving {
    struct Request: Sendable {
        let type: DocumentType
        let name: String
        let directory: URL
    }
    private let failure: Error?
    private(set) var calls = 0
    private(set) var lastRequest: Request?
    private(set) var lastMoveRequest: (source: URL, destination: URL)?
    private(set) var lastMoveName: String?
    private(set) var lastMoveReplaced = false
    init(failure: Error? = nil) { self.failure = failure }
    func createDocument(type: DocumentType, name: String, in directory: URL) throws -> URL {
        calls += 1
        lastRequest = Request(type: type, name: name, directory: directory)
        if let failure { throw failure }
        return directory.appendingPathComponent(try DocumentFileName.make(name: name, type: type))
    }
    func moveFile(at source: URL, to directory: URL, name: String, replaceExisting: Bool) throws -> URL {
        try Task.checkCancellation()
        calls += 1
        lastMoveRequest = (source, directory)
        lastMoveName = name
        lastMoveReplaced = replaceExisting
        if let failure { throw failure }
        return directory.appendingPathComponent(name)
    }
}
