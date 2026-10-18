import Foundation

nonisolated enum FolderPreference: String, CaseIterable {
    case creationDirectory
    case moveDestination

    var storageKey: String { "folderBookmarks.v1.\(rawValue)" }
}

nonisolated enum FolderBookmarkRestoration: Equatable {
    case notSaved
    case restored(URL)
    case requiresReselection
}

nonisolated enum FolderBookmarkError: LocalizedError {
    case unavailable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: "已保存的文件夹无法访问，请重新选择。"
        case .saveFailed: "无法保存文件夹授权；当前选择仅本次可用，请重新选择以重试。"
        }
    }
}
