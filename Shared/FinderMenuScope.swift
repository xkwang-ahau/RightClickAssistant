import Foundation

nonisolated enum FinderMenuScope {
    /// 启动磁盘根始终在范围内，保证扩展在冷启动的瞬间就有可用监控范围。
    static let startupRoot = URL(fileURLWithPath: "/", isDirectory: true)

    /// 明确注册用户可见的卷根，避免依赖 Finder 是否跨挂载点传播根目录的监控。
    static func directories(mountedVolumes: [URL]) -> Set<URL> {
        var roots = Set([startupRoot])
        for volume in mountedVolumes where isUsable(volume) && isUserBrowsableVolume(volume) {
            roots.insert(volume.standardizedFileURL)
        }
        return roots
    }

    /// 用上次运行缓存的路径恢复范围，省掉启动后立刻二次赋值触发的 Finder 重新加载。
    /// 缓存不可用（相对路径、非文件 URL、含 NUL 的路径、非用户卷）时逐项丢弃，并始终保留启动磁盘根。
    static func directories(fromCachedPaths paths: [String]) -> Set<URL> {
        var roots = Set<URL>()
        for path in paths where path.hasPrefix("/") {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            guard isUsable(url) else { continue }
            if url.path == "/" || isUserBrowsableVolume(url) { roots.insert(url.standardizedFileURL) }
        }
        roots.insert(startupRoot)
        return roots
    }

    /// 稳定顺序的缓存表示，便于比较与排查日志。
    static func cachedPaths(of scope: Set<URL>) -> [String] {
        scope.map(\.path).sorted()
    }

    static func isUsable(_ url: URL) -> Bool {
        url.isFileURL && !url.path(percentEncoded: true).contains("%00")
    }

    /// 只登记用户在 Finder 里能点到的卷：`/Volumes/<名称>` 与 `/Network/<名称>`。
    ///
    /// 系统卷（`/System/Volumes/Preboot`、`VM`、`xarts` 等）和应用临时挂载点
    /// （`/var/folders/.../T/*`、`/tmp/*`）本来就位于启动磁盘的目录树内，已被 `/` 覆盖；
    /// 把它们登记进来只会让监控范围随临时挂载反复变化，进而让 Finder 反复重载扩展。
    /// 快照挂载（`/Volumes/.timemachine/...`）以及卷内更深层的挂载同理不登记。
    static func isUserBrowsableVolume(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        guard components.count == 3, components[0] == "/" else { return false }
        guard components[1] == "Volumes" || components[1] == "Network" else { return false }
        return !components[2].hasPrefix(".")
    }
}

/// 记录上次实际交给 Finder 的监控范围，供扩展下次启动直接复用。
nonisolated struct FinderScopeCache {
    static let storageKey = "FinderMenuScope.roots"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [String] {
        defaults.stringArray(forKey: Self.storageKey) ?? []
    }

    func save(_ paths: [String]) {
        defaults.set(paths, forKey: Self.storageKey)
    }
}
