import AppKit
import FinderSync
import OSLog

final class FinderSync: FIFinderSync {
    private let logger = Logger(subsystem: "devplaceholder.JW2H7X4Z.RightClickAssistant.FinderExtension", category: "FinderMenu")
    private var requests = FinderMenuRequests()
    private let scopeCache = FinderScopeCache()
    /// 已交给 Finder 的范围。重复赋值会让 Finder 重新加载扩展，因此只在真的变化时写回。
    private var appliedScope: Set<URL> = []
    private var pendingScopeRefresh: Task<Void, Never>?

    override init() {
        super.init()
        // 启动路径上不做磁盘枚举：先用上次范围（或仅启动磁盘根）建立监控，
        // 真正的卷枚举放到后台任务里完成，菜单可用性不受影响。
        apply(FinderMenuScope.directories(fromCachedPaths: scopeCache.load()), reason: "bootstrap")
        scheduleScopeRefresh(after: .zero, reason: "startup")
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(volumesChanged(_:)), name: name, object: nil)
        }
        logger.info("Finder menu extension initialized")
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func volumesChanged(_ notification: Notification) {
        // 插拔一次磁盘常连发多条挂载/卸载通知，去抖后只刷新一次。
        scheduleScopeRefresh(after: .milliseconds(500), reason: "volumeChange")
    }

    private func scheduleScopeRefresh(after delay: Duration, reason: String) {
        pendingScopeRefresh?.cancel()
        pendingScopeRefresh = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            let scope = await Self.enumeratedScope()
            guard !Task.isCancelled else { return }
            self?.apply(scope, reason: reason)
        }
    }

    /// 在后台线程枚举挂载卷；回到调用方（主 actor）后才会写回 Finder。
    /// 只取可浏览卷，系统卷（Recovery、Preboot 等）与应用临时挂载点直接不参与比较。
    private nonisolated static func enumeratedScope() async -> Set<URL> {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes])
        if volumes == nil {
            Logger(subsystem: "devplaceholder.JW2H7X4Z.RightClickAssistant.FinderExtension", category: "FinderMenu")
                .error("Unable to enumerate mounted volumes; retaining current coverage")
        }
        return FinderMenuScope.directories(mountedVolumes: volumes ?? [])
    }

    private func apply(_ scope: Set<URL>, reason: String) {
        guard scope != appliedScope else {
            logger.debug("Finder menu scope unchanged, \(scope.count, privacy: .public) roots kept (\(reason, privacy: .public))")
            return
        }
        appliedScope = scope
        FIFinderSyncController.default().directoryURLs = scope
        scopeCache.save(FinderMenuScope.cachedPaths(of: scope))
        logger.notice("Finder menu scope updated, \(scope.count, privacy: .public) roots (\(reason, privacy: .public))")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else { return nil }
        let controller = FIFinderSyncController.default()
        let menu = NSMenu(title: "右键助手")
        let root = NSMenuItem(title: "右键助手", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "右键助手")
        root.submenu = submenu
        menu.addItem(root)

        if menuKind == .contextualMenuForContainer, let directory = controller.targetedURL() {
            addCreationItems(to: submenu, directory: directory)
        } else if let items = controller.selectedItemURLs(), items.count == 1, let selected = items.first {
            // 无权读取元数据时只提供“打开”，不猜测文件/目录身份。
            do {
                let values = try selected.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                if values.isDirectory == true {
                    addCreationItems(to: submenu, directory: selected)
                } else if values.isRegularFile == true, values.isSymbolicLink != true {
                    add("移动此文件…", request: FinderRequest(action: .move, location: selected), to: submenu)
                }
            } catch {
                logger.error("Unable to inspect Finder selection: \(error.localizedDescription, privacy: .public)")
            }
        }
        if !submenu.items.isEmpty { submenu.addItem(.separator()) }
        add("打开右键助手", request: FinderRequest(action: .open, location: nil), to: submenu)
        return menu
    }

    private func addCreationItems(to menu: NSMenu, directory: URL) {
        add("新建 Word 文档…", request: FinderRequest(action: .word, location: directory), to: menu)
        add("新建 PowerPoint 文档…", request: FinderRequest(action: .powerPoint, location: directory), to: menu)
        add("新建 Excel 文档…", request: FinderRequest(action: .excel, location: directory), to: menu)
    }

    private func add(_ title: String, request: FinderRequest, to menu: NSMenu) {
        guard let url = request.url else { return }
        let item = NSMenuItem(title: title, action: #selector(openAssistant(_:)), keyEquivalent: "")
        item.target = self
        // Finder 跨进程回传 tag，不依赖 representedObject 或 NSMenuItem 对象身份。
        item.tag = requests.store(url)
        menu.addItem(item)
    }

    @objc private func openAssistant(_ sender: NSMenuItem) {
        logger.notice("Finder menu action received, tag: \(sender.tag)")
        guard let url = requests.url(for: sender.tag) else {
            logger.error("Missing or expired menu request, tag: \(sender.tag)")
            return
        }
        // 指定本扩展所在 App，避免系统选择其他同 scheme 的开发副本；后台执行不抢占焦点。
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { [logger] _, error in
            if let error {
                logger.error("Unable to open containing app: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.notice("Containing app open request completed")
            }
        }
    }
}
