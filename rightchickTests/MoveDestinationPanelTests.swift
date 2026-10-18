import AppKit
import XCTest
@testable import rightchick

@MainActor
final class MoveDestinationPanelTests: XCTestCase {
    func testDestinationPanelClearlyIdentifiesSourceAndUsesMovePrompt() throws {
        let source = URL(fileURLWithPath: "/Users/test/Desktop/新建 Word 文档.docx")
        let panel = NSOpenPanel()
        let delegate = MoveDestinationPanel(source: source)
        delegate.configure(panel, initialDirectory: nil)
        XCTAssertEqual(panel.prompt, "移动到此文件夹")
        XCTAssertTrue(panel.message.contains(source.path))
        XCTAssertTrue(panel.message.contains("文稿"))
        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertNotNil(panel.accessoryView)
    }

    func testPanelRejectsSourceFolderButAcceptsDocumentsAndShowsActualSelection() throws {
        let source = URL(fileURLWithPath: "/Users/test/Desktop/新建 Word 文档.docx")
        let desktop = source.deletingLastPathComponent()
        let documents = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        let panel = NSOpenPanel()
        let delegate = MoveDestinationPanel(source: source)
        delegate.configure(panel, initialDirectory: nil)
        XCTAssertThrowsError(try delegate.panel(panel, validate: desktop)) { error in
            XCTAssertEqual(error as? FileMoveError, .sameLocation)
        }
        XCTAssertNoThrow(try delegate.panel(panel, validate: documents))
        panel.directoryURL = documents
        delegate.panel(panel, didChangeToDirectoryURL: documents)
        let label = try XCTUnwrap(panel.accessoryView as? NSTextField)
        XCTAssertTrue(label.stringValue.contains(documents.path))
    }
}
