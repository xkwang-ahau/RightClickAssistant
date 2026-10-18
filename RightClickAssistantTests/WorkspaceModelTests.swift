import Foundation
import XCTest
@testable import RightClickAssistant

@MainActor
final class WorkspaceModelTests: XCTestCase {
    func testCancelFolderSelectionPreservesBothIndependentDirectories() {
        let creation = URL(fileURLWithPath: "/test/creation")
        let destination = URL(fileURLWithPath: "/test/destination")
        let picker = StubFolderPicker(selections: [creation, destination, nil, nil])
        let model = WorkspaceModel(
            folderPicker: picker,
            documentCreator: StubDocumentCreator(),
            filePicker: FilePicker(),
            fileMover: FileOperationService()
        )
        model.chooseCreationDirectory()
        model.chooseMoveDestination()
        model.chooseCreationDirectory()
        model.chooseMoveDestination()
        XCTAssertEqual(model.creationDirectory, creation)
        XCTAssertEqual(model.moveDestination, destination)
    }

    func testValidationMatchesPreviewAndButtonAvailability() {
        let model = makeModel(creator: StubDocumentCreator())
        model.documentName = "  报告.DOCX.docx  "
        XCTAssertEqual(model.documentNamePreview, "报告.docx")
        XCTAssertTrue(model.canCreateDocument)
        model.selectedDocumentType = .excel
        XCTAssertEqual(model.documentNamePreview, "报告.xlsx")
        model.documentName = "../报告"
        XCTAssertNotNil(model.nameValidationMessage)
        XCTAssertFalse(model.canCreateDocument)
    }

    func testMissingDirectoryPreventsServiceCall() async {
        let creator = StubDocumentCreator()
        let model = WorkspaceModel(
            folderPicker: StubFolderPicker(selections: []),
            documentCreator: creator,
            filePicker: FilePicker(),
            fileMover: FileOperationService()
        )
        await model.createDocument()
        XCTAssertEqual(model.creationStatus, .failed("请先选择文档创建位置。"))
        let calls = await creator.callCount
        XCTAssertEqual(calls, 0)
    }

    func testInvalidNamePreventsServiceCall() async {
        let creator = StubDocumentCreator()
        let model = makeModel(creator: creator)
        model.documentName = "../无效名称"
        await model.createDocument()
        XCTAssertEqual(model.creationStatus, .failed(DocumentCreationError.invalidName.localizedDescription))
        let calls = await creator.callCount
        XCTAssertEqual(calls, 0)
    }

    func testSuccessPublishesActualCreatedURL() async {
        let output = URL(fileURLWithPath: "/test/creation/未命名.docx")
        let creator = StubDocumentCreator(result: .success(output))
        let model = makeModel(creator: creator)
        await model.createDocument()
        XCTAssertEqual(model.creationStatus, .created(output))
        XCTAssertFalse(model.isCreating)
        XCTAssertTrue(model.canCreateDocument)
    }

    func testFailureShowsUsefulErrorAndAllowsRetry() async {
        let failure = DocumentCreationError.alreadyExists("未命名.docx")
        let model = makeModel(creator: StubDocumentCreator(result: .failure(failure)))
        await model.createDocument()
        XCTAssertEqual(model.creationStatus, .failed(failure.localizedDescription))
        XCTAssertTrue(model.canCreateDocument)
    }

    func testDuplicateRequestsAreIgnoredWhileCreationIsPending() async {
        let creator = ControlledDocumentCreator()
        let model = makeModel(creator: creator)
        let first = Task { await model.createDocument() }
        await creator.waitUntilStarted()
        XCTAssertTrue(model.isCreating)
        XCTAssertFalse(model.canCreateDocument)

        await model.createDocument()
        let calls = await creator.callCount
        XCTAssertEqual(calls, 1)
        let output = URL(fileURLWithPath: "/test/creation/未命名.docx")
        await creator.finish(with: .success(output))
        await first.value
        XCTAssertEqual(model.creationStatus, .created(output))
    }

    func testInFlightRequestKeepsItsOriginalInput() async {
        let creator = ControlledDocumentCreator()
        let model = makeModel(creator: creator)
        model.documentName = "原始名称"
        let task = Task { await model.createDocument() }
        await creator.waitUntilStarted()
        model.documentName = "后来的名称"
        model.selectedDocumentType = .excel

        let request = await creator.request
        XCTAssertEqual(request?.name, "原始名称")
        XCTAssertEqual(request?.type, .word)
        let output = URL(fileURLWithPath: "/test/creation/原始名称.docx")
        await creator.finish(with: .success(output))
        await task.value
        XCTAssertEqual(model.creationStatus, .created(output))
    }

    func testCancellationReturnsToIdleWithoutFalseSuccess() async {
        let model = makeModel(creator: StubDocumentCreator(result: .failure(CancellationError())))
        await model.createDocument()
        XCTAssertEqual(model.creationStatus, .idle)
        XCTAssertTrue(model.canCreateDocument)
    }

    private func makeModel(creator: any DocumentCreating) -> WorkspaceModel {
        let directory = URL(fileURLWithPath: "/test/creation")
        let model = WorkspaceModel(
            folderPicker: StubFolderPicker(selections: [directory]),
            documentCreator: creator,
            filePicker: FilePicker(),
            fileMover: FileOperationService()
        )
        model.chooseCreationDirectory()
        return model
    }
}

@MainActor
private final class StubFolderPicker: FolderPicking {
    private var selections: [URL?]

    init(selections: [URL?]) {
        self.selections = selections
    }

    func chooseFolder(title: String, initialDirectory: URL?) -> URL? {
        guard !selections.isEmpty else { return nil }
        return selections.removeFirst()
    }
}

private actor StubDocumentCreator: DocumentCreating {
    private let result: Result<URL, Error>
    private(set) var callCount = 0

    init(result: Result<URL, Error> = .failure(DocumentCreationError.invalidDirectory)) {
        self.result = result
    }

    func createDocument(type: DocumentType, name: String, in directory: URL) throws -> URL {
        callCount += 1
        return try result.get()
    }
}

private actor ControlledDocumentCreator: DocumentCreating {
    struct Request: Sendable {
        let type: DocumentType
        let name: String
    }

    private(set) var callCount = 0
    private(set) var request: Request?
    private var resultContinuation: CheckedContinuation<URL, Error>?
    private var startContinuation: CheckedContinuation<Void, Never>?

    func createDocument(type: DocumentType, name: String, in directory: URL) async throws -> URL {
        callCount += 1
        request = Request(type: type, name: name)
        return try await withCheckedThrowingContinuation { continuation in
            resultContinuation = continuation
            startContinuation?.resume()
            startContinuation = nil
        }
    }

    func waitUntilStarted() async {
        guard request == nil else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func finish(with result: Result<URL, Error>) {
        resultContinuation?.resume(with: result)
        resultContinuation = nil
    }
}
