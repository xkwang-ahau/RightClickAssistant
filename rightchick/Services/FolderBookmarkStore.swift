import Foundation

@MainActor
protocol FolderBookmarkPersisting {
    func restore(_ preference: FolderPreference) -> FolderBookmarkRestoration
    func save(_ directory: URL, for preference: FolderPreference) throws
    func clear(_ preference: FolderPreference)
}

@MainActor
protocol FolderBookmarkAccessing {
    func makeBookmark(for directory: URL) throws -> Data
    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool)
    func startAccessing(_ directory: URL) -> Bool
    func stopAccessing(_ directory: URL)
    func validateDirectory(_ directory: URL) throws
}

@MainActor
struct SecurityScopedBookmarkAccess: FolderBookmarkAccessing {
    func makeBookmark(for directory: URL) throws -> Data {
        try directory.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    func startAccessing(_ directory: URL) -> Bool {
        directory.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ directory: URL) {
        directory.stopAccessingSecurityScopedResource()
    }

    func validateDirectory(_ directory: URL) throws {
        guard directory.isFileURL,
              !directory.path(percentEncoded: true).contains("%00"),
              try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw FolderBookmarkError.unavailable
        }
    }
}

@MainActor
final class FolderBookmarkStore: FolderBookmarkPersisting {
    private let defaults: UserDefaults
    private let access: any FolderBookmarkAccessing

    init(defaults: UserDefaults = .standard, access: (any FolderBookmarkAccessing)? = nil) {
        self.defaults = defaults
        self.access = access ?? SecurityScopedBookmarkAccess()
    }

    func restore(_ preference: FolderPreference) -> FolderBookmarkRestoration {
        guard let stored = defaults.object(forKey: preference.storageKey) else { return .notSaved }
        guard let data = stored as? Data else { return .requiresReselection }
        do {
            let resolved = try access.resolve(data)
            let didStart = access.startAccessing(resolved.url)
            defer {
                if didStart { access.stopAccessing(resolved.url) }
            }
            // false 也可能意味着无需额外 scope；实际目录读取决定是否可用。
            try access.validateDirectory(resolved.url)
            if resolved.isStale {
                let refreshed = try access.makeBookmark(for: resolved.url)
                defaults.set(refreshed, forKey: preference.storageKey)
            }
            return .restored(resolved.url)
        } catch {
            // 保留不可恢复的书签，供用户明确替换或清除；绝不退回路径字符串。
            return .requiresReselection
        }
    }

    func save(_ directory: URL, for preference: FolderPreference) throws {
        let didStart = access.startAccessing(directory)
        defer {
            if didStart { access.stopAccessing(directory) }
        }
        do {
            try access.validateDirectory(directory)
            let data = try access.makeBookmark(for: directory)
            defaults.set(data, forKey: preference.storageKey)
        } catch {
            // 新选择未保存时不允许下次启动悄悄恢复该位置的旧选择。
            clear(preference)
            throw FolderBookmarkError.saveFailed
        }
    }

    func clear(_ preference: FolderPreference) {
        defaults.removeObject(forKey: preference.storageKey)
    }
}
