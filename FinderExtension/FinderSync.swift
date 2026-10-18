import AppKit
import FinderSync
import OSLog

final class FinderSync: FIFinderSync {
    private let logger = Logger(subsystem: "devplaceholder.JW2H7X4Z.RightClickAssistant.FinderExtension", category: "FinderMenu")
    private var requests = FinderMenuRequests()

    override init() {
        super.init()
        refreshDirectories()
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(volumesChanged(_:)), name: name, object: nil)
        }
        logger.info("Finder menu extension initialized")
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func volumesChanged(_ notification: Notification) {
        refreshDirectories()
    }

    private func refreshDirectories() {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [])
        if volumes == nil { logger.error("Unable to enumerate mounted volumes; retaining root coverage") }
        let directories = FinderMenuScope.directories(mountedVolumes: volumes ?? [])
        FIFinderSyncController.default().directoryURLs = directories
        logger.notice("Finder menu scope updated, volume roots: \(directories.count)")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else { return nil }
        let controller = FIFinderSyncController.default()
        let menu = NSMenu(title: "RightClickAssistant")
        let root = NSMenuItem(title: "RightClickAssistant", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "RightClickAssistant")
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
        add("打开 RightClickAssistant", request: FinderRequest(action: .open, location: nil), to: submenu)
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
