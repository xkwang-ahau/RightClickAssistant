import Darwin
import Foundation
import XCTest
@testable import RightClickAssistant

@MainActor
final class FileMovementServiceTests: XCTestCase {
    func testMovePreservesExactNameBytesAndPermissions() async throws {
        try await withFixture { source, target in
            let bytes = Data([0, 1, 255, 42])
            try bytes.write(to: source)
            try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: source.path)
            let output = try await FileOperationService().moveFile(at: source, to: target)
            XCTAssertEqual(output.lastPathComponent, source.lastPathComponent)
            XCTAssertEqual(try Data(contentsOf: output), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o400)
        }
    }

    func testSameFolderAndItsSymbolicAliasKeepSourceUnchanged() async throws {
        try await withFixture { source, target in
            let parent = source.deletingLastPathComponent()
            let alias = target.appendingPathComponent("alias")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: parent)
            for directory in [parent, alias] {
                await expectError(.sameLocation) {
                    try await FileOperationService().moveFile(at: source, to: directory)
                }
                XCTAssertEqual(try Data(contentsOf: source), Data("源内容".utf8))
            }
        }
    }

    func testExistingFileIsNeverOverwritten() async throws {
        try await withFixture { source, target in
            let existing = target.appendingPathComponent(source.lastPathComponent)
            let sentinel = Data("已有内容".utf8)
            try sentinel.write(to: existing)
            await expectError(.alreadyExists(source.lastPathComponent)) {
                try await FileOperationService().moveFile(at: source, to: target)
            }
            XCTAssertEqual(try Data(contentsOf: existing), sentinel)
            XCTAssertEqual(try Data(contentsOf: source), Data("源内容".utf8))
        }
    }

    func testExistingHardLinkToSourceIsStillAConflict() async throws {
        try await withFixture { source, target in
            let existing = target.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.linkItem(at: source, to: existing)
            await expectError(.alreadyExists(source.lastPathComponent)) {
                try await FileOperationService().moveFile(at: source, to: target)
            }
            XCTAssertEqual(try Data(contentsOf: source), Data("源内容".utf8))
            XCTAssertEqual(try Data(contentsOf: existing), Data("源内容".utf8))
        }
    }

    func testExistingDirectoryIsNeverReplaced() async throws {
        try await withFixture { source, target in
            let existing = target.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
            let marker = existing.appendingPathComponent("保留")
            try Data("标记".utf8).write(to: marker)
            await expectError(.alreadyExists(source.lastPathComponent)) {
                try await FileOperationService().moveFile(at: source, to: target)
            }
            XCTAssertEqual(try Data(contentsOf: marker), Data("标记".utf8))
            XCTAssertEqual(try Data(contentsOf: source), Data("源内容".utf8))
        }
    }

    func testExistingAndDanglingSymbolicLinksAreNeverReplaced() async throws {
        try await withFixture { source, target in
            let existing = target.appendingPathComponent(source.lastPathComponent)
            let original = target.appendingPathComponent("original")
            try Data("链接指向的内容".utf8).write(to: original)
            for destination in [original, target.appendingPathComponent("missing")] {
                try FileManager.default.createSymbolicLink(at: existing, withDestinationURL: destination)
                await expectError(.alreadyExists(source.lastPathComponent)) {
                    try await FileOperationService().moveFile(at: source, to: target)
                }
                XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: existing.path), destination.path)
                XCTAssertEqual(try Data(contentsOf: source), Data("源内容".utf8))
                try FileManager.default.removeItem(at: existing)
            }
            XCTAssertEqual(try Data(contentsOf: original), Data("链接指向的内容".utf8))
        }
    }

    func testMissingSourceAndInvalidDestinationDoNotMoveAnything() async throws {
        try await withFixture { source, target in
            await expectError(.sourceUnavailable) {
                try await FileOperationService().moveFile(at: target.appendingPathComponent("missing"), to: target)
            }
            for invalid in [target.appendingPathComponent("missing"), source] {
                await expectError(.invalidDestination) {
                    try await FileOperationService().moveFile(at: source, to: invalid)
                }
                XCTAssertEqual(try Data(contentsOf: source), Data("源内容".utf8))
            }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
        }
    }

    func testDirectoriesAndSymbolicLinkSourcesAreRejected() async throws {
        try await withFixture { source, target in
            let parent = source.deletingLastPathComponent()
            let link = parent.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
            for invalid in [parent, link] {
                await expectError(.unsupportedSource) {
                    try await FileOperationService().moveFile(at: invalid, to: target)
                }
            }
            XCTAssertEqual(try Data(contentsOf: source), Data("源内容".utf8))
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), source.path)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
        }
    }

    func testReadOnlySourceAndDestinationFoldersKeepSourceIntact() async throws {
        try await withFixture { source, target in
            for directory in [source.deletingLastPathComponent(), target] {
                try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
                defer {
                    do {
                        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
                    } catch { XCTFail("Could not restore permissions: \(error)") }
                }
                await expectError(.accessDenied) {
                    try await FileOperationService().moveFile(at: source, to: target)
                }
                XCTAssertEqual(try Data(contentsOf: source), Data("源内容".utf8))
                XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
            }
        }
    }

    func testCancellationBeforeExecutionKeepsSourceIntact() async throws {
        try await withFixture { source, target in
            let service = FileOperationService()
            let task = Task { try await service.moveFile(at: source, to: target) }
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("Expected cancellation")
            } catch is CancellationError {
                // 服务开始时即检查取消，还没有执行重命名。
            }
            XCTAssertEqual(try Data(contentsOf: source), Data("源内容".utf8))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
        }
    }

    func testCancellationAfterRenameStillReportsCommittedSuccess() async throws {
        try await withFixture { source, target in
            let service = FileOperationService(moveOperation: { source, destination in
                try ExclusiveFileMove.perform(source: source, destination: destination)
                withUnsafeCurrentTask { $0?.cancel() }
            })
            let task = Task { try await service.moveFile(at: source, to: target) }
            let output = try await task.value
            XCTAssertEqual(try Data(contentsOf: output), Data("源内容".utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        }
    }

    func testCompetingSourcesOnlyAllowOneWinnerAndKeepLoser() async throws {
        try await withFixture { source, target in
            let otherFolder = target.deletingLastPathComponent().appendingPathComponent("other")
            try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: false)
            let other = otherFolder.appendingPathComponent(source.lastPathComponent)
            try Data("另一个源".utf8).write(to: other)
            async let first = moveResult(service: FileOperationService(), source: source, target: target)
            async let second = moveResult(service: FileOperationService(), source: other, target: target)
            let results = await [first, second]
            var successes = 0
            for (index, result) in results.enumerated() {
                let original = index == 0 ? source : other
                switch result {
                case .success(let output):
                    successes += 1
                    XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
                    XCTAssertEqual(try Data(contentsOf: output), Data((index == 0 ? "源内容" : "另一个源").utf8))
                case .failure(let error):
                    XCTAssertEqual(error as? FileMoveError, .alreadyExists(source.lastPathComponent))
                    XCTAssertEqual(try Data(contentsOf: original), Data((index == 0 ? "源内容" : "另一个源").utf8))
                }
            }
            XCTAssertEqual(successes, 1)
        }
    }

    func testCrossVolumeAndUnsupportedFileSystemErrorsKeepSourceIntact() async throws {
        try await withFixture { source, target in
            let cases: [(Int32, FileMoveError)] = [(EXDEV, .differentVolume), (ENOTSUP, .unsupportedFileSystem)]
            for (code, expected) in cases {
                let service = FileOperationService(moveOperation: { _, _ in
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
                })
                await expectError(expected) { try await service.moveFile(at: source, to: target) }
                XCTAssertEqual(try Data(contentsOf: source), Data("源内容".utf8))
                XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
            }
        }
    }

    func testNonFileURLsAndEmbeddedNullsAreRejected() async throws {
        try await withFixture { source, target in
            let remote = try XCTUnwrap(URL(string: "https://example.invalid/file"))
            for invalid in [remote, URL(fileURLWithPath: source.path + "\0suffix")] {
                await expectError(.sourceUnavailable) {
                    try await FileOperationService().moveFile(at: invalid, to: target)
                }
            }
            for invalid in [remote, URL(fileURLWithPath: target.path + "\0suffix")] {
                await expectError(.invalidDestination) {
                    try await FileOperationService().moveFile(at: source, to: invalid)
                }
            }
            XCTAssertEqual(try Data(contentsOf: source), Data("源内容".utf8))
        }
    }

    func testMoveKeepingBothPicksNextAvailableNameAndKeepsExisting() async throws {
        try await withConflictFixture { source, target in
            let existing = target.appendingPathComponent(source.lastPathComponent)
            let existingTwo = target.appendingPathComponent("报告 (2).txt")
            try Data("已有".utf8).write(to: existing)
            try Data("已有2".utf8).write(to: existingTwo)
            let output = try await FileOperationService().moveFileKeepingBoth(at: source, to: target)
            XCTAssertEqual(output.lastPathComponent, "报告 (3).txt")
            XCTAssertEqual(try Data(contentsOf: output), Data("源内容".utf8))
            XCTAssertEqual(try Data(contentsOf: existing), Data("已有".utf8))
            XCTAssertEqual(try Data(contentsOf: existingTwo), Data("已有2".utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        }
    }

    func testMoveReplacingReplacesRegularFileAtomically() async throws {
        try await withConflictFixture { source, target in
            let existing = target.appendingPathComponent(source.lastPathComponent)
            try Data("已有".utf8).write(to: existing)
            let output = try await FileOperationService().moveFile(
                at: source, to: target, name: source.lastPathComponent, replaceExisting: true
            )
            XCTAssertEqual(output, existing)
            XCTAssertEqual(try Data(contentsOf: output), Data("源内容".utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        }
    }

    func testMoveReplacingRefusesDirectoryAndSymbolicLink() async throws {
        try await withConflictFixture { source, target in
            let directory = target.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let marker = directory.appendingPathComponent("保留")
            try Data("标记".utf8).write(to: marker)
            await expectError(.alreadyExists(source.lastPathComponent)) {
                try await FileOperationService().moveFile(
                    at: source, to: target, name: source.lastPathComponent, replaceExisting: true
                )
            }
            XCTAssertEqual(try Data(contentsOf: marker), Data("标记".utf8))
            XCTAssertEqual(try Data(contentsOf: source), Data("源内容".utf8))
            try FileManager.default.removeItem(at: directory)

            let link = target.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            await expectError(.alreadyExists(source.lastPathComponent)) {
                try await FileOperationService().moveFile(
                    at: source, to: target, name: source.lastPathComponent, replaceExisting: true
                )
            }
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
            XCTAssertEqual(try Data(contentsOf: source), Data("源内容".utf8))
        }
    }

    func testExplicitNameWithoutReplaceStillRefusesExisting() async throws {
        try await withConflictFixture { source, target in
            try Data("已有".utf8).write(to: target.appendingPathComponent("报告.txt"))
            await expectError(.alreadyExists("报告.txt")) {
                try await FileOperationService().moveFile(at: source, to: target, name: "报告.txt", replaceExisting: false)
            }
            XCTAssertEqual(try Data(contentsOf: source), Data("源内容".utf8))
        }
    }

    private func withConflictFixture(_ body: (URL, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RightClickAssistant-conflict-\(UUID().uuidString)")
        let origin = root.appendingPathComponent("origin")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { XCTFail("Could not clean up conflict fixture: \(error)") }
        }
        let source = origin.appendingPathComponent("报告.txt")
        try Data("源内容".utf8).write(to: source)
        try await body(source, target)
    }

    private func withFixture(_ body: (URL, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RightClickAssistant-move-\(UUID().uuidString)")
        let origin = root.appendingPathComponent("origin")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { XCTFail("Could not clean up move fixture: \(error)") }
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let source = origin.appendingPathComponent(" 中文名称 : 原样.TXT ")
        try Data("源内容".utf8).write(to: source)
        try await body(source, target)
    }

    private func expectError(_ expected: FileMoveError, operation: () async throws -> URL) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch { XCTAssertEqual(error as? FileMoveError, expected) }
    }

    nonisolated private func moveResult(service: FileOperationService, source: URL, target: URL) async -> Result<URL, Error> {
        do { return .success(try await service.moveFile(at: source, to: target)) }
        catch { return .failure(error) }
    }
}
