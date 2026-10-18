import AppKit

@MainActor
protocol FolderPicking {
    func chooseFolder(title: String, initialDirectory: URL?) -> URL?
    func chooseMoveDestination(for source: URL, initialDirectory: URL?) -> URL?
}

extension FolderPicking {
    func chooseMoveDestination(for source: URL, initialDirectory: URL?) -> URL? {
        chooseFolder(title: "选择移动目的地（选择后即移动）", initialDirectory: initialDirectory)
    }
}

@MainActor
final class FolderPicker: FolderPicking {
    func chooseFolder(title: String, initialDirectory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "选择"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = initialDirectory

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    func chooseMoveDestination(for source: URL, initialDirectory: URL?) -> URL? {
        let panel = NSOpenPanel()
        let selection = MoveDestinationPanel(source: source)
        selection.configure(panel, initialDirectory: initialDirectory)
        panel.delegate = selection
        guard withExtendedLifetime(selection, { panel.runModal() }) == .OK else { return nil }
        return panel.url
    }
}

@MainActor
final class MoveDestinationPanel: NSObject, NSOpenSavePanelDelegate {
    private let source: URL
    private let targetLabel = NSTextField(wrappingLabelWithString: "")

    init(source: URL) {
        self.source = source
    }

    func configure(_ panel: NSOpenPanel, initialDirectory: URL?) {
        panel.title = "将“\(source.lastPathComponent)”移动到…"
        panel.prompt = "移动到此文件夹"
        panel.message = "源文件：\(source.path)\n请选择目的地文件夹，例如侧栏的“文稿”。确认后即移动。"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.directoryURL = initialDirectory
        targetLabel.preferredMaxLayoutWidth = 460
        targetLabel.frame = NSRect(x: 0, y: 0, width: 460, height: 36)
        targetLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        targetLabel.setAccessibilityLabel("实际移动目的地")
        panel.accessoryView = targetLabel
        updateTarget(panel)
    }

    func panelSelectionDidChange(_ sender: Any?) {
        guard let panel = sender as? NSOpenPanel else { return }
        updateTarget(panel)
    }

    func panel(_ sender: Any, didChangeToDirectoryURL url: URL?) {
        guard let panel = sender as? NSOpenPanel else { return }
        updateTarget(panel)
    }

    func panel(_ sender: Any, validate url: URL) throws {
        try MoveDestinationValidation.validate(url, for: source)
    }

    private func updateTarget(_ panel: NSOpenPanel) {
        let target = panel.url ?? panel.directoryURL
        targetLabel.stringValue = target.map { "将移到：\($0.path)" } ?? "请选择移动目的地"
    }
}
