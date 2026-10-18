import Foundation
import XCTest
@testable import RightClickAssistant

final class FinderRequestTests: XCTestCase {
    func testAllActionsRoundTripChineseAndReservedPathCharacters() throws {
        for action in FinderAction.allCases {
            let path = "/test/中文 空格/#报告&预算+100%.txt"
            let location = action == .open ? nil : URL(fileURLWithPath: path, isDirectory: action != .move)
            let request = FinderRequest(action: action, location: location)
            let url = try XCTUnwrap(request.url)
            let decoded = try XCTUnwrap(FinderRequest.decode(url))
            XCTAssertEqual(decoded.action, action)
            XCTAssertEqual(decoded.location?.path, location?.path)
        }
    }

    func testDecoderRejectsAmbiguousMalformedOrUnsupportedRequests() throws {
        let invalid = [
            "other://finder?action=open", "rightclickassistant://other?action=open",
            "rightclickassistant://finder/path?action=open", "rightclickassistant://finder?action=open#fragment",
            "rightclickassistant://user@finder?action=open", "rightclickassistant://finder:12?action=open",
            "rightclickassistant://finder?action=unknown", "rightclickassistant://finder?action=word",
            "rightclickassistant://finder?action=word&path=relative", "rightclickassistant://finder?action=move&path=",
            "rightclickassistant://finder?action=move&path=/test%00file",
            "rightclickassistant://finder?action=open&path=/test", "rightclickassistant://finder?action=open&extra=1",
            "rightclickassistant://finder?action=open&action=move", "rightclickassistant://finder?action=open&action=open",
            "rightclickassistant://finder?action=move&path=/a&path=/b", "rightclickassistant://finder?action",
            "rightclickassistant://finder", "rightclickassistant://finder?action=move&path",
        ]
        for string in invalid {
            let url = try XCTUnwrap(URL(string: string))
            XCTAssertNil(FinderRequest.decode(url), string)
        }
    }

    func testEncoderRejectsMissingOrUnexpectedLocationAndRemoteURLs() {
        XCTAssertNil(FinderRequest(action: .move, location: nil).url)
        XCTAssertNil(FinderRequest(action: .open, location: URL(fileURLWithPath: "/test")).url)
        XCTAssertNil(FinderRequest(action: .word, location: URL(string: "https://example.com/path")).url)
    }

    func testOversizedInputIsRejected() throws {
        let longPath = "/" + String(repeating: "a", count: 4096)
        let request = FinderRequest(action: .move, location: URL(fileURLWithPath: longPath))
        XCTAssertNil(request.url)
        let url = try XCTUnwrap(URL(string: "rightclickassistant://finder?action=move&path=/" + String(repeating: "a", count: 33_000)))
        XCTAssertNil(FinderRequest.decode(url))
    }

    func testScopeAlwaysIncludesStartupRootAndEveryMountedVolume() {
        let external = URL(fileURLWithPath: "/Volumes/外接 磁盘", isDirectory: true)
        let network = URL(fileURLWithPath: "/Volumes/Shared", isDirectory: true)
        let roots = FinderMenuScope.directories(mountedVolumes: [external, network, external])
        XCTAssertEqual(Set(roots.map(\.path)), ["/", "/Volumes/外接 磁盘", "/Volumes/Shared"])
        XCTAssertEqual(roots.count, 3)
    }

    func testScopeSurvivesVolumeRemovalAndFiltersNonFileURLs() throws {
        let remote = try XCTUnwrap(URL(string: "https://example.com/disk"))
        let invalid = try XCTUnwrap(URL(string: "file:///Volumes/Bad%00disk"))
        let roots = FinderMenuScope.directories(mountedVolumes: [remote, invalid])
        XCTAssertEqual(roots.map(\.path), ["/"])
        let mounted = FinderMenuScope.directories(mountedVolumes: [URL(fileURLWithPath: "/Volumes/USB")])
        XCTAssertTrue(mounted.contains(URL(fileURLWithPath: "/Volumes/USB")))
        XCTAssertEqual(FinderMenuScope.directories(mountedVolumes: []).map(\.path), ["/"])
    }
}
