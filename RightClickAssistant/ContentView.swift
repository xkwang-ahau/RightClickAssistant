import AppKit
import SwiftUI

struct ContentView: View {
    let model: WorkspaceModel
    @State private var finderIntegration = FinderIntegration()
    @State private var grantedFolders: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("右键助手")
                        .font(.headline)
                    Text("在 Finder 中右键新建文档或移动文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Label(
                    "Finder 扩展：\(finderIntegration.isEnabled ? "已启用" : "未启用")",
                    systemImage: finderIntegration.isEnabled ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .font(.callout)
                .foregroundStyle(finderIntegration.isEnabled ? Color.green : Color.orange)
                Spacer()
                Button("管理…", action: finderIntegration.showManagement)
                    .controlSize(.small)
            }

            HStack {
                Label(folderAccessText, systemImage: folderAccessIcon)
                    .font(.callout)
                    .foregroundStyle(folderAccessColor)
                Spacer()
                Button("立即申请…") {
                    grantedFolders = FolderAccessPreauthorizer.requestCommonFolders()
                }
                .controlSize(.small)
            }

            Text("普通文件夹可直接使用。仅在首次访问桌面、文稿、下载等受保护位置时，系统会询问一次“允许访问”。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let message = model.finderRequestMessage {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.callout)
                        .textSelection(.enabled)
                    if model.finderResultURL != nil {
                        Button("在 Finder 中显示", action: model.revealFinderResult)
                    }
                }
            }

            Divider()
            Button("退出右键助手") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 320)
        .task {
            // 系统设置里改动扩展状态时应用不会被通知；面板显示期间短轮询，保证状态及时更新。
            finderIntegration.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                finderIntegration.refresh()
            }
        }
    }

    private var folderAccessText: String {
        guard let grantedFolders else { return "文件夹访问：用到时系统会提示" }
        return grantedFolders.isEmpty
            ? "文件夹访问：未授权"
            : "文件夹访问：已授权（\(grantedFolders.joined(separator: "、"))）"
    }

    private var folderAccessIcon: String {
        guard let grantedFolders else { return "folder" }
        return grantedFolders.isEmpty ? "exclamationmark.circle" : "checkmark.circle.fill"
    }

    private var folderAccessColor: Color {
        guard let grantedFolders else { return .secondary }
        return grantedFolders.isEmpty ? .orange : .green
    }
}

#Preview {
    let service = FileOperationService()
    ContentView(model: WorkspaceModel(
        folderPicker: FolderPicker(),
        documentCreator: service,
        filePicker: FilePicker(),
        fileMover: service
    ))
}
