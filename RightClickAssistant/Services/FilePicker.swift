import AppKit

@MainActor
protocol FilePicking {
    func chooseFile(title: String, initialDirectory: URL?) -> URL?
}

@MainActor
final class FilePicker: FilePicking {
    func chooseFile(title: String, initialDirectory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = false
        panel.directoryURL = initialDirectory

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
