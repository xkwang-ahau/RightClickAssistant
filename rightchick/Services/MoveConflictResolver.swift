import AppKit
import Foundation

nonisolated enum MoveConflictDecision: Equatable, Sendable {
    case keepBoth
    case replace
    case cancel
}

@MainActor
protocol MoveConflictResolving {
    func resolve(sourceName: String, destinationPath: String) -> MoveConflictDecision
}

/// 目的地同名时的用户决策。应用平时在后台运行，这里只在冲突时短暂激活前台的模态对话框。
@MainActor
final class MoveConflictResolver: MoveConflictResolving {
    func resolve(sourceName: String, destinationPath: String) -> MoveConflictDecision {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "目的地已有“\(sourceName)”"
        alert.informativeText = "位置：\(destinationPath)\n请选择处理方式。"
        alert.addButton(withTitle: "保留两者")
        alert.addButton(withTitle: "替换")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .replace
        default: return .cancel
        }
    }
}
