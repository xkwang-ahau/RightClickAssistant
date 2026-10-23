import Foundation
import XCTest
@testable import RightClickAssistant

final class FinderMenuScopeTests: XCTestCase {
    func testCachedPathsRoundTripRestoresSameCoverage() {
        let volumes = [
            URL(fileURLWithPath: "/Volumes/外接 磁盘", isDirectory: true),
            URL(fileURLWithPath: "/Volumes/Shared", isDirectory: true),
        ]
        let scope = FinderMenuScope.directories(mountedVolumes: volumes)
        let restored = FinderMenuScope.directories(fromCachedPaths: FinderMenuScope.cachedPaths(of: scope))
        XCTAssertEqual(restored, scope)
        XCTAssertEqual(restored.map(\.path).sorted(), ["/", "/Volumes/Shared", "/Volumes/外接 磁盘"].sorted())
    }

    func testCachedPathsAreSortedForStableComparison() {
        let scope = FinderMenuScope.directories(mountedVolumes: [
            URL(fileURLWithPath: "/Volumes/B", isDirectory: true),
            URL(fileURLWithPath: "/Volumes/A", isDirectory: true),
        ])
        XCTAssertEqual(FinderMenuScope.cachedPaths(of: scope), ["/", "/Volumes/A", "/Volumes/B"])
    }

    func testCachedPathsDropInvalidEntriesAndAlwaysKeepStartupRoot() {
        let restored = FinderMenuScope.directories(fromCachedPaths: [
            "relative/path", "https://example.com/disk", "file:///Volumes/Bad%00disk", "/Volumes/Good",
        ])
        XCTAssertEqual(restored.map(\.path).sorted(), ["/", "/Volumes/Good"])
        XCTAssertEqual(FinderMenuScope.directories(fromCachedPaths: []).map(\.path), ["/"])
    }

    func testSystemAndTemporaryMountsAreNotRegisteredAsScopeRoots() {
        // 这些挂载点都在启动磁盘树内，已由 "/" 覆盖；登记它们只会随临时挂载频繁抖动。
        let noise = [
            URL(fileURLWithPath: "/System/Volumes/Preboot", isDirectory: true),
            URL(fileURLWithPath: "/System/Volumes/VM", isDirectory: true),
            URL(fileURLWithPath: "/System/Volumes/Data/home", isDirectory: true),
            URL(fileURLWithPath: "/var/folders/2m/wsdtb63j6hl/T/HqeJqm", isDirectory: true),
            URL(fileURLWithPath: "/tmp/astris_mnt", isDirectory: true),
            URL(fileURLWithPath: "/Volumes/.timemachine/Snapshot", isDirectory: true),
        ]
        let scope = FinderMenuScope.directories(mountedVolumes: noise)
        XCTAssertEqual(scope.map(\.path), ["/"])
        let restored = FinderMenuScope.directories(fromCachedPaths: noise.map(\.path) + ["/"])
        XCTAssertEqual(restored.map(\.path), ["/"])
    }

    func testUserVisibleVolumesSurviveAlongsideStartupRoot() {
        let scope = FinderMenuScope.directories(mountedVolumes: [
            URL(fileURLWithPath: "/Volumes/USB", isDirectory: true),
            URL(fileURLWithPath: "/Volumes/Recovery", isDirectory: true),
            URL(fileURLWithPath: "/Network/Share", isDirectory: true),
            URL(fileURLWithPath: "/System/Volumes/VM", isDirectory: true),
        ])
        XCTAssertEqual(scope.map(\.path).sorted(), ["/", "/Network/Share", "/Volumes/Recovery", "/Volumes/USB"])
    }

    func testCachePersistsAcrossInstances() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "FinderMenuScopeTests"))
        suite.removePersistentDomain(forName: "FinderMenuScopeTests")
        FinderScopeCache(defaults: suite).save(["/", "/Volumes/USB"])
        XCTAssertEqual(FinderScopeCache(defaults: suite).load(), ["/", "/Volumes/USB"])
        suite.removePersistentDomain(forName: "FinderMenuScopeTests")
    }
}
