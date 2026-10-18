import Foundation
import OSLog

/// 非沙盒应用通过 TCC 的“文件与文件夹”提示获得访问权。
/// 首次启动时主动读取常见受保护目录，一次性触发系统授权提示；之后读取不再弹窗。
@MainActor
enum FolderAccessPreauthorizer {
    private static let logger = Logger(subsystem: "devplaceholder.JW2H7X4Z.RightClickAssistant", category: "FolderAccess")
    private static let folders: [(component: String, displayName: String)] = [
        ("Desktop", "桌面"),
        ("Documents", "文稿"),
        ("Downloads", "下载"),
    ]

    /// 读取目录会触发系统授权提示（仅在尚未决定时）；返回已可访问目录的中文名。
    @discardableResult
    static func requestCommonFolders() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var granted: [String] = []
        for folder in folders {
            let url = home.appendingPathComponent(folder.component, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
                granted.append(folder.displayName)
            } catch {
                logger.notice("No access yet for \(folder.component, privacy: .public)")
            }
        }
        logger.notice("Folder access check finished, granted: \(granted.count)")
        return granted
    }
}
