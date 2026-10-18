import AppKit
import XCTest
@testable import RightClickAssistant

@MainActor
final class FinderMenuRequestsTests: XCTestCase {
    func testForwardedMenuItemWithoutRepresentedObjectResolvesByTag() throws {
        let request = FinderRequest(action: .word, location: URL(fileURLWithPath: "/test/first"))
        let url = try XCTUnwrap(request.url)
        var requests = FinderMenuRequests()
        let forwarded = NSMenuItem(title: "新建 Word 文档", action: nil, keyEquivalent: "")
        forwarded.tag = requests.store(url)
        XCTAssertNil(forwarded.representedObject)
        XCTAssertEqual(requests.url(for: forwarded.tag), url)
    }

    func testLaterMenuDoesNotReplacePreviousRequestSnapshot() throws {
        var requests = FinderMenuRequests()
        let first = try XCTUnwrap(FinderRequest(action: .word, location: URL(fileURLWithPath: "/test/first")).url)
        let second = try XCTUnwrap(FinderRequest(action: .excel, location: URL(fileURLWithPath: "/test/second")).url)
        let firstTag = requests.store(first)
        let secondTag = requests.store(second)
        XCTAssertNotEqual(firstTag, secondTag)
        XCTAssertEqual(requests.url(for: firstTag), first)
        XCTAssertEqual(requests.url(for: secondTag), second)
    }

    func testEvictedOrUnknownTagsDoNotResolveToNewerRequests() throws {
        var requests = FinderMenuRequests(capacity: 2)
        let url = try XCTUnwrap(FinderRequest(action: .open, location: nil).url)
        let old = requests.store(url)
        let retained = requests.store(url)
        let latest = requests.store(url)
        XCTAssertNil(requests.url(for: old))
        XCTAssertNil(requests.url(for: 0))
        XCTAssertNil(requests.url(for: latest + 1))
        XCTAssertEqual(requests.url(for: retained), url)
        XCTAssertEqual(requests.url(for: latest), url)
    }
}
