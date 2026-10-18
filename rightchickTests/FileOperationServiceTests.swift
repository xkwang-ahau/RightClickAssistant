import Foundation
import XCTest
@testable import rightchick

@MainActor
final class FileOperationServiceTests: XCTestCase {
    func testAutomaticNewDocumentsUseNumberedNamesAndPreserveExistingContentsForAllTypes() async throws {
        try await withTemporaryDirectory { directory in
            let service = FileOperationService()
            for type in DocumentType.allCases {
                let existing = directory.appendingPathComponent("\(type.newDocumentName).\(type.fileExtension)")
                let sentinel = Data("已有内容".utf8)
                try sentinel.write(to: existing)
                let second = try await service.createNewDocument(type: type, in: directory)
                let third = try await service.createNewDocument(type: type, in: directory)
                XCTAssertEqual(second.lastPathComponent, "\(type.newDocumentName) (2).\(type.fileExtension)")
                XCTAssertEqual(third.lastPathComponent, "\(type.newDocumentName) (3).\(type.fileExtension)")
                XCTAssertEqual(try Data(contentsOf: existing), sentinel)
                let template = try XCTUnwrap(Bundle.main.url(forResource: type.templateResourceName, withExtension: type.fileExtension))
                XCTAssertEqual(try Data(contentsOf: second), try Data(contentsOf: template))
                XCTAssertEqual(try Data(contentsOf: third), try Data(contentsOf: template))
            }
        }
    }

    func testCompetingAutomaticRequestsBothCreateDistinctIntactDocuments() async throws {
        try await withTemporaryDirectory { directory in
            let firstService = FileOperationService()
            let secondService = FileOperationService()
            async let first = firstService.createNewDocument(type: .word, in: directory)
            async let second = secondService.createNewDocument(type: .word, in: directory)
            let outputs = try await [first, second]
            XCTAssertEqual(Set(outputs.map(\.lastPathComponent)), ["新建 Word 文档.docx", "新建 Word 文档 (2).docx"])
            let template = try XCTUnwrap(Bundle.main.url(forResource: "BlankWord", withExtension: "docx"))
            for output in outputs {
                XCTAssertEqual(try Data(contentsOf: output), try Data(contentsOf: template))
            }
        }
    }

    func testAutomaticCreationSkipsExistingDirectoryAndDanglingLinkWithoutChangingThem() async throws {
        try await withTemporaryDirectory { directory in
            let folder = directory.appendingPathComponent("新建 Word 文档.docx")
            let link = directory.appendingPathComponent("新建 Word 文档 (2).docx")
            let missing = directory.appendingPathComponent("missing")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: missing)
            let output = try await FileOperationService().createNewDocument(type: .word, in: directory)
            XCTAssertEqual(output.lastPathComponent, "新建 Word 文档 (3).docx")
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), missing.path)
        }
    }

    func testAutomaticCreationPropagatesNonConflictFailures() async throws {
        try await withTemporaryDirectory { directory in
            await expectError(.templateUnavailable(.word)) {
                try await FileOperationService(templateURLs: [:]).createNewDocument(type: .word, in: directory)
            }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    func testCreatesAllOfficeTypesFromBundledTemplates() async throws {
        try await withTemporaryDirectory { directory in
            let service = FileOperationService()
            for type in DocumentType.allCases {
                let output = try await service.createDocument(type: type, name: "会议记录", in: directory)
                let template = try XCTUnwrap(Bundle.main.url(
                    forResource: type.templateResourceName,
                    withExtension: type.fileExtension
                ))
                XCTAssertEqual(output.lastPathComponent, "会议记录.\(type.fileExtension)")
                let actual = try Data(contentsOf: output)
                XCTAssertEqual(actual, try Data(contentsOf: template))
                XCTAssertEqual(Array(actual.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
                XCTAssertGreaterThan(actual.count, 1_000)
            }
        }
    }

    func testNormalizesWhitespaceAndRepeatedOfficeExtensions() async throws {
        try await withTemporaryDirectory { directory in
            let service = FileOperationService()
            let word = try await service.createDocument(type: .word, name: "  会议记录.DOCX.docx  ", in: directory)
            let excel = try await service.createDocument(type: .excel, name: "预算.docx", in: directory)
            XCTAssertEqual(word.lastPathComponent, "会议记录.docx")
            XCTAssertEqual(excel.lastPathComponent, "预算.xlsx")
        }
    }

    func testInvalidNamesNeverCreateFiles() async throws {
        try await withTemporaryDirectory { directory in
            let service = FileOperationService()
            let invalidNames = [
                "", "  ", ".", "..", "../escape", "folder/name", "a\\b", "bad:name",
                "bad?name", "a\nb", ".docx", String(repeating: "汉", count: 100)
            ]
            for name in invalidNames {
                do {
                    _ = try await service.createDocument(type: .word, name: name, in: directory)
                    XCTFail("Accepted invalid name: \(name.debugDescription)")
                } catch {
                    XCTAssertNotNil(error as? DocumentCreationError)
                }
            }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    func testExistingFileIsNeverOverwritten() async throws {
        try await withTemporaryDirectory { directory in
            let destination = directory.appendingPathComponent("已有文档.docx")
            let sentinel = Data("已有的用户内容".utf8)
            try sentinel.write(to: destination)

            await expectError(.alreadyExists("已有文档.docx")) {
                try await FileOperationService().createDocument(type: .word, name: "已有文档", in: directory)
            }
            XCTAssertEqual(try Data(contentsOf: destination), sentinel)
        }
    }

    func testExistingDirectoryIsNeverReplaced() async throws {
        try await withTemporaryDirectory { directory in
            let existing = directory.appendingPathComponent("目录.docx", isDirectory: true)
            try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
            let marker = existing.appendingPathComponent("保留.txt")
            try Data("保留".utf8).write(to: marker)

            await expectError(.alreadyExists("目录.docx")) {
                try await FileOperationService().createDocument(type: .word, name: "目录", in: directory)
            }
            XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "保留")
        }
    }

    func testSymbolicLinkTargetIsNeverOverwritten() async throws {
        try await withTemporaryDirectory { directory in
            let original = directory.appendingPathComponent("original.txt")
            let link = directory.appendingPathComponent("链接.docx")
            let sentinel = Data("原始内容".utf8)
            try sentinel.write(to: original)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)

            await expectError(.alreadyExists("链接.docx")) {
                try await FileOperationService().createDocument(type: .word, name: "链接", in: directory)
            }
            XCTAssertEqual(try Data(contentsOf: original), sentinel)
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), original.path)
        }
    }

    func testDanglingSymbolicLinkIsNeverReplaced() async throws {
        try await withTemporaryDirectory { directory in
            let missing = directory.appendingPathComponent("missing.txt")
            let link = directory.appendingPathComponent("链接.docx")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: missing)

            await expectError(.alreadyExists("链接.docx")) {
                try await FileOperationService().createDocument(type: .word, name: "链接", in: directory)
            }
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), missing.path)
            XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        }
    }

    func testCompetingServicesCreateExactlyOneFile() async throws {
        try await withTemporaryDirectory { directory in
            let firstService = FileOperationService()
            let secondService = FileOperationService()
            async let first = creationResult(service: firstService, directory: directory)
            async let second = creationResult(service: secondService, directory: directory)
            let results = await [first, second]
            var successes = 0
            var conflicts = 0
            for result in results {
                switch result {
                case .success:
                    successes += 1
                case .failure(let error):
                    XCTAssertEqual(error as? DocumentCreationError, .alreadyExists("同名.docx"))
                    conflicts += 1
                }
            }
            XCTAssertEqual(successes, 1)
            XCTAssertEqual(conflicts, 1)
            let template = try XCTUnwrap(Bundle.main.url(forResource: "BlankWord", withExtension: "docx"))
            XCTAssertEqual(
                try Data(contentsOf: directory.appendingPathComponent("同名.docx")),
                try Data(contentsOf: template)
            )
        }
    }

    func testMissingTemplateDoesNotCreateFile() async throws {
        try await withTemporaryDirectory { directory in
            await expectError(.templateUnavailable(.word)) {
                try await FileOperationService(templateURLs: [:]).createDocument(
                    type: .word, name: "文档", in: directory
                )
            }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    func testMissingDirectoryReportsUnavailable() async throws {
        try await withTemporaryDirectory { directory in
            let missing = directory.appendingPathComponent("不存在", isDirectory: true)
            await expectError(.invalidDirectory) {
                try await FileOperationService().createDocument(type: .word, name: "文档", in: missing)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        }
    }

    func testPlainFileCannotBeUsedAsDirectory() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("file.txt")
            let sentinel = Data("保留".utf8)
            try sentinel.write(to: file)
            await expectError(.invalidDirectory) {
                try await FileOperationService().createDocument(type: .word, name: "文档", in: file)
            }
            XCTAssertEqual(try Data(contentsOf: file), sentinel)
        }
    }

    func testReadOnlyDirectoryReportsAccessDenied() async throws {
        try await withTemporaryDirectory { directory in
            let readOnly = directory.appendingPathComponent("readonly", isDirectory: true)
            try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: false)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: readOnly.path)
            defer {
                do {
                    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: readOnly.path)
                } catch {
                    XCTFail("Could not restore test-directory permissions: \(error)")
                }
            }
            await expectError(.accessDenied) {
                try await FileOperationService().createDocument(type: .word, name: "文档", in: readOnly)
            }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: readOnly.path).isEmpty)
        }
    }

    func testCancellationBeforeExecutionDoesNotCreateFile() async throws {
        try await withTemporaryDirectory { directory in
            let service = FileOperationService()
            let task = Task {
                try await service.createDocument(type: .word, name: "取消", in: directory)
            }
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("A cancelled request should not create a file")
            } catch is CancellationError {
                // Expected: the actual file service checks cancellation before copying.
            }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rightchick-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                XCTFail("Could not clean up test directory: \(error)")
            }
        }
        try await body(directory)
    }

    private func expectError(
        _ expected: DocumentCreationError,
        operation: () async throws -> URL
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? DocumentCreationError, expected)
        }
    }

    nonisolated private func creationResult(
        service: FileOperationService,
        directory: URL
    ) async -> Result<URL, Error> {
        do {
            return .success(try await service.createDocument(type: .word, name: "同名", in: directory))
        } catch {
            return .failure(error)
        }
    }
}
