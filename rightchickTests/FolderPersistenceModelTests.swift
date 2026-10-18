import Foundation
import XCTest
@testable import rightchick

@MainActor
final class FolderPersistenceModelTests: XCTestCase {
    private let creation = URL(fileURLWithPath: "/test/creation")
    private let destination = URL(fileURLWithPath: "/test/destination")

    func testStartupRestoresOnlyDirectoriesAndLeavesOperationsIdle() {
        let store = StubFolderPreferenceStore()
        store.results = [.creationDirectory: .restored(creation), .moveDestination: .restored(destination)]
        let model = makeModel(store: store)
        XCTAssertEqual(model.creationDirectory, creation)
        XCTAssertEqual(model.moveDestination, destination)
        XCTAssertNil(model.sourceFile)
        XCTAssertEqual(model.creationStatus, .idle)
        XCTAssertEqual(model.moveStatus, .idle)
        XCTAssertTrue(model.canCreateDocument)
        XCTAssertFalse(model.canMoveFile)
        XCTAssertEqual(store.restoreCalls, FolderPreference.allCases)
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testUnrecoverablePreferenceDoesNotBlockOtherDirectoryAndCanBeCleared() {
        let store = StubFolderPreferenceStore()
        store.results = [.creationDirectory: .requiresReselection, .moveDestination: .restored(destination)]
        let model = makeModel(store: store)
        XCTAssertNil(model.creationDirectory)
        XCTAssertFalse(model.canCreateDocument)
        XCTAssertEqual(model.creationDirectoryMessage, FolderBookmarkError.unavailable.localizedDescription)
        XCTAssertEqual(model.moveDestination, destination)
        XCTAssertNil(model.moveDestinationMessage)
        model.clearCreationDirectory()
        XCTAssertNil(model.creationDirectoryMessage)
        XCTAssertEqual(store.cleared, [.creationDirectory])
        XCTAssertEqual(model.moveDestination, destination)
    }

    func testChoosingSavesIndependentPreferencesAndCancelPreservesMessages() {
        let store = StubFolderPreferenceStore()
        store.results = [.creationDirectory: .requiresReselection]
        let model = makeModel(store: store, selections: [nil, creation, destination, nil])
        model.chooseCreationDirectory()
        XCTAssertNotNil(model.creationDirectoryMessage)
        XCTAssertTrue(store.saved.isEmpty)
        model.chooseCreationDirectory()
        model.chooseMoveDestination()
        model.chooseMoveDestination()
        XCTAssertEqual(store.saved[.creationDirectory], creation)
        XCTAssertEqual(store.saved[.moveDestination], destination)
        XCTAssertEqual(model.moveDestination, destination)
        XCTAssertNil(model.creationDirectoryMessage)
    }

    func testSaveFailureKeepsCurrentSessionDirectoryUntilSuccessfulReselection() {
        let store = StubFolderPreferenceStore()
        store.failSave = true
        let model = makeModel(store: store, selections: [creation, nil, creation])
        model.chooseCreationDirectory()
        XCTAssertEqual(model.creationDirectory, creation)
        XCTAssertTrue(model.canCreateDocument)
        XCTAssertEqual(model.creationDirectoryMessage, FolderBookmarkError.saveFailed.localizedDescription)
        model.chooseCreationDirectory()
        XCTAssertNotNil(model.creationDirectoryMessage)
        store.failSave = false
        model.chooseCreationDirectory()
        XCTAssertNil(model.creationDirectoryMessage)
        XCTAssertEqual(store.saved[.creationDirectory], creation)
    }

    func testClearingMoveDestinationPreservesCreationAndSourceSelection() {
        let store = StubFolderPreferenceStore()
        store.results = [.creationDirectory: .restored(creation), .moveDestination: .restored(destination)]
        let model = makeModel(store: store)
        model.chooseSourceFile()
        let source = model.sourceFile
        XCTAssertTrue(model.canMoveFile)
        model.clearMoveDestination()
        XCTAssertEqual(store.cleared, [.moveDestination])
        XCTAssertNil(model.moveDestination)
        XCTAssertEqual(model.creationDirectory, creation)
        XCTAssertEqual(model.sourceFile, source)
        XCTAssertFalse(model.canMoveFile)
    }

    private func makeModel(store: StubFolderPreferenceStore, selections: [URL?] = []) -> WorkspaceModel {
        let service = FileOperationService()
        return WorkspaceModel(
            folderPicker: PersistenceFolderPicker(selections), documentCreator: service,
            filePicker: PersistenceFilePicker(), fileMover: service, bookmarkStore: store
        )
    }
}

@MainActor
private final class StubFolderPreferenceStore: FolderBookmarkPersisting {
    var results: [FolderPreference: FolderBookmarkRestoration] = [:]
    var saved: [FolderPreference: URL] = [:]
    var cleared: [FolderPreference] = []
    var restoreCalls: [FolderPreference] = []
    var failSave = false

    func restore(_ preference: FolderPreference) -> FolderBookmarkRestoration {
        restoreCalls.append(preference)
        return results[preference] ?? .notSaved
    }

    func save(_ directory: URL, for preference: FolderPreference) throws {
        if failSave { throw FolderBookmarkError.saveFailed }
        saved[preference] = directory
    }

    func clear(_ preference: FolderPreference) { cleared.append(preference) }
}

@MainActor
private final class PersistenceFolderPicker: FolderPicking {
    private var selections: [URL?]
    init(_ selections: [URL?]) { self.selections = selections }
    func chooseFolder(title: String, initialDirectory: URL?) -> URL? {
        selections.isEmpty ? nil : selections.removeFirst()
    }
}

@MainActor
private struct PersistenceFilePicker: FilePicking {
    func chooseFile(title: String, initialDirectory: URL?) -> URL? {
        URL(fileURLWithPath: "/test/source.txt")
    }
}
