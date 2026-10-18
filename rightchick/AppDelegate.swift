import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "devplaceholder.JW2H7X4Z.RightClickAssistant", category: "Lifecycle")
    private static let onboardingKey = "didCompleteFolderAccessOnboarding"

    let model: WorkspaceModel

    override init() {
        let service = FileOperationService()
        model = WorkspaceModel(
            folderPicker: FolderPicker(),
            documentCreator: service,
            filePicker: FilePicker(),
            fileMover: service,
            bookmarkStore: FolderBookmarkStore()
        )
        super.init()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        logger.notice("Received \(urls.count) Finder URL(s)")
        for url in urls {
            model.handleFinderURL(url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !UserDefaults.standard.bool(forKey: Self.onboardingKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        presentOnboarding()
    }

    private func presentOnboarding() {
        let alert = NSAlert()
        alert.messageText = "欢迎使用右键助手"
        alert.informativeText = """
        首次使用只需两步：
        • 在系统设置中启用“右键助手 Finder 菜单”扩展。
        • 当你在桌面、文稿、下载等受保护位置首次新建或移动时，系统可能询问一次“允许访问”，点“允许”即可，之后不再打扰。

        其它普通文件夹可直接使用，无需授权。
        """
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "管理 Finder 扩展")
        if alert.runModal() == .alertSecondButtonReturn {
            FinderIntegration().showManagement()
        }
    }
}
