import Foundation
import XCTest
@testable import rightchick

@MainActor
final class FolderBookmarkStoreTests: XCTestCase {
    func testRestoredMoveDestinationIsUsableByCreationAndMovementServices() async throws {
        let suite = "rightchick.nested-bookmark-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = root.appendingPathComponent("子目录/工作")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { removeTemporaryDirectory(root) }
        let store = FolderBookmarkStore(defaults: defaults)
        try store.save(destination, for: .moveDestination)
        guard case .restored(let restoredDestination) = store.restore(.moveDestination) else {
            XCTFail("Move destination must restore")
            return
        }
        let service = FileOperationService()
        for type in DocumentType.allCases {
            let automatic = try await service.createNewDocument(type: type, in: restoredDestination, accessing: restoredDestination)
            let manual = try await service.createDocument(type: type, name: "手动创建", in: restoredDestination, accessing: restoredDestination)
            let template = try XCTUnwrap(Bundle.main.url(forResource: type.templateResourceName, withExtension: type.fileExtension))
            XCTAssertEqual(try Data(contentsOf: automatic), try Data(contentsOf: template))
            XCTAssertEqual(try Data(contentsOf: manual), try Data(contentsOf: template))
            XCTAssertEqual(automatic.deletingLastPathComponent().standardizedFileURL.path, destination.standardizedFileURL.path)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).count, 6)
    }

    func testRestoredURLsCanBeUsedByExistingCreationAndMovementServices() async throws {
        let suite = "rightchick.bookmark-io-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let creation = root.appendingPathComponent("creation")
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: creation, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { removeTemporaryDirectory(root) }
        let first = FolderBookmarkStore(defaults: defaults)
        try first.save(creation, for: .creationDirectory)
        try first.save(destination, for: .moveDestination)
        let reloadedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let second = FolderBookmarkStore(defaults: reloadedDefaults)
        guard case .restored(let creationURL) = second.restore(.creationDirectory),
              case .restored(let destinationURL) = second.restore(.moveDestination) else {
            XCTFail("Saved directories must restore before IO")
            return
        }
        let service = FileOperationService()
        for type in DocumentType.allCases {
            let output = try await service.createDocument(type: type, name: "授权恢复", in: creationURL)
            let contents = try Data(contentsOf: output)
            let moved = try await service.moveFile(at: output, to: destinationURL)
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertEqual(try Data(contentsOf: moved), contents)
        }
    }

    func testRealSecurityScopedBookmarksRestoreIndependentDirectoriesAcrossStoreInstances() throws {
        try withDefaults { defaults in
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let creation = root.appendingPathComponent("创建")
            let destination = root.appendingPathComponent("目的地")
            try FileManager.default.createDirectory(at: creation, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { removeTemporaryDirectory(root) }
            let first = FolderBookmarkStore(defaults: defaults)
            try first.save(creation, for: .creationDirectory)
            try first.save(destination, for: .moveDestination)
            let second = FolderBookmarkStore(defaults: defaults)
            assertRestored(second.restore(.creationDirectory), matches: creation)
            assertRestored(second.restore(.moveDestination), matches: destination)
            second.clear(.creationDirectory)
            XCTAssertEqual(first.restore(.creationDirectory), .notSaved)
            assertRestored(first.restore(.moveDestination), matches: destination)
        }
    }

    func testRealDeletedDirectoryAndRegularFileCannotRestoreAsDirectory() throws {
        try withDefaults { defaults in
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { removeTemporaryDirectory(root) }
            let store = FolderBookmarkStore(defaults: defaults)
            let directory = root.appendingPathComponent("已删除")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try store.save(directory, for: .creationDirectory)
            try FileManager.default.removeItem(at: directory)
            XCTAssertEqual(store.restore(.creationDirectory), .requiresReselection)
            let file = root.appendingPathComponent("普通文件")
            try Data("content".utf8).write(to: file)
            XCTAssertThrowsError(try store.save(file, for: .moveDestination))
            XCTAssertEqual(store.restore(.moveDestination), .notSaved)
        }
    }

    func testAbsentWrongTypeAndCorruptBookmarksDoNotReturnPathFallback() throws {
        try withDefaults { defaults in
            let store = FolderBookmarkStore(defaults: defaults)
            XCTAssertEqual(store.restore(.creationDirectory), .notSaved)
            defaults.set("/tmp", forKey: FolderPreference.creationDirectory.storageKey)
            defaults.set(Data([0, 1, 2]), forKey: FolderPreference.moveDestination.storageKey)
            XCTAssertEqual(store.restore(.creationDirectory), .requiresReselection)
            XCTAssertEqual(store.restore(.moveDestination), .requiresReselection)
            XCTAssertNotNil(defaults.object(forKey: FolderPreference.creationDirectory.storageKey))
            store.clear(.creationDirectory)
            XCTAssertNil(defaults.object(forKey: FolderPreference.creationDirectory.storageKey))
            XCTAssertNotNil(defaults.object(forKey: FolderPreference.moveDestination.storageKey))
        }
    }

    func testStaleBookmarkRefreshesOnlyItsOwnKeyWithinBalancedAccess() throws {
        try withDefaults { defaults in
            let access = StubBookmarkAccess()
            access.isStale = true
            seed(defaults)
            let store = FolderBookmarkStore(defaults: defaults, access: access)
            XCTAssertEqual(store.restore(.creationDirectory), .restored(access.directory))
            XCTAssertEqual(defaults.data(forKey: FolderPreference.creationDirectory.storageKey), access.newData)
            XCTAssertEqual(defaults.data(forKey: FolderPreference.moveDestination.storageKey), Data([9]))
            XCTAssertEqual(access.events, ["resolve", "start", "validate", "make", "stop"])
        }
    }

    func testUnusableDirectoryAndFailedStaleRefreshKeepOldBookmarkAndBalanceAccess() throws {
        try withDefaults { defaults in
            seed(defaults)
            let access = StubBookmarkAccess()
            access.failValidation = true
            let store = FolderBookmarkStore(defaults: defaults, access: access)
            XCTAssertEqual(store.restore(.creationDirectory), .requiresReselection)
            XCTAssertEqual(access.events, ["resolve", "start", "validate", "stop"])
            access.events = []
            access.failValidation = false
            access.isStale = true
            access.failMake = true
            XCTAssertEqual(store.restore(.creationDirectory), .requiresReselection)
            XCTAssertEqual(access.events, ["resolve", "start", "validate", "make", "stop"])
            XCTAssertEqual(defaults.data(forKey: FolderPreference.creationDirectory.storageKey), Data([1]))
        }
    }

    func testResolutionFailureDoesNotStartAccess() throws {
        try withDefaults { defaults in
            seed(defaults)
            let access = StubBookmarkAccess()
            access.failResolve = true
            let store = FolderBookmarkStore(defaults: defaults, access: access)
            XCTAssertEqual(store.restore(.creationDirectory), .requiresReselection)
            XCTAssertEqual(access.events, ["resolve"])
        }
    }

    func testFailedReplacementRemovesOldSelectionWithoutChangingOtherPreference() throws {
        try withDefaults { defaults in
            seed(defaults)
            let access = StubBookmarkAccess()
            access.failMake = true
            let store = FolderBookmarkStore(defaults: defaults, access: access)
            XCTAssertThrowsError(try store.save(access.directory, for: .creationDirectory)) { error in
                XCTAssertEqual(error.localizedDescription, FolderBookmarkError.saveFailed.localizedDescription)
            }
            XCTAssertNil(defaults.object(forKey: FolderPreference.creationDirectory.storageKey))
            XCTAssertEqual(defaults.data(forKey: FolderPreference.moveDestination.storageKey), Data([9]))
            XCTAssertEqual(access.events, ["start", "validate", "make", "stop"])
        }
    }

    func testFalseStartUsesActualValidationAndNeverStopsUnstartedAccess() throws {
        try withDefaults { defaults in
            seed(defaults)
            let access = StubBookmarkAccess()
            access.didStart = false
            let store = FolderBookmarkStore(defaults: defaults, access: access)
            XCTAssertEqual(store.restore(.creationDirectory), .restored(access.directory))
            try store.save(access.directory, for: .moveDestination)
            XCTAssertFalse(access.events.contains("stop"))
            access.failValidation = true
            XCTAssertEqual(store.restore(.creationDirectory), .requiresReselection)
            XCTAssertThrowsError(try store.save(access.directory, for: .moveDestination))
            XCTAssertFalse(access.events.contains("stop"))
        }
    }

    func testSaveValidationFailureClearsOnlyTargetAndBalancesAccess() throws {
        try withDefaults { defaults in
            seed(defaults)
            let access = StubBookmarkAccess()
            access.failValidation = true
            let store = FolderBookmarkStore(defaults: defaults, access: access)
            XCTAssertThrowsError(try store.save(access.directory, for: .creationDirectory))
            XCTAssertEqual(access.events, ["start", "validate", "stop"])
            XCTAssertEqual(store.restore(.creationDirectory), .notSaved)
            XCTAssertEqual(defaults.data(forKey: FolderPreference.moveDestination.storageKey), Data([9]))
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "rightchick.bookmark-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func seed(_ defaults: UserDefaults) {
        defaults.set(Data([1]), forKey: FolderPreference.creationDirectory.storageKey)
        defaults.set(Data([9]), forKey: FolderPreference.moveDestination.storageKey)
    }

    private func assertRestored(_ result: FolderBookmarkRestoration, matches directory: URL) {
        guard case .restored(let url) = result else {
            XCTFail("Expected usable directory, got \(result)")
            return
        }
        XCTAssertEqual(url.standardizedFileURL.resolvingSymlinksInPath().path,
                       directory.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            XCTFail("Temporary cleanup failed: \(error)")
        }
    }
}

@MainActor
private final class StubBookmarkAccess: FolderBookmarkAccessing {
    let directory = URL(fileURLWithPath: "/test/bookmarked")
    let newData = Data([2])
    var isStale = false
    var didStart = true
    var failResolve = false
    var failValidation = false
    var failMake = false
    var events: [String] = []

    func makeBookmark(for directory: URL) throws -> Data {
        events.append("make")
        if failMake { throw FolderBookmarkError.saveFailed }
        return newData
    }

    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        events.append("resolve")
        if failResolve { throw FolderBookmarkError.unavailable }
        return (directory, isStale)
    }

    func startAccessing(_ directory: URL) -> Bool {
        events.append("start")
        return didStart
    }

    func stopAccessing(_ directory: URL) { events.append("stop") }

    func validateDirectory(_ directory: URL) throws {
        events.append("validate")
        if failValidation { throw FolderBookmarkError.unavailable }
    }
}
