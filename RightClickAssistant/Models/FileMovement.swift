import Foundation

nonisolated enum FileMoveError: LocalizedError, Equatable, Sendable {
    case sourceUnavailable
    case unsupportedSource
    case invalidDestination
    case sameLocation
    case alreadyExists(String)
    case accessDenied
    case differentVolume
    case locationChanged
    case unsupportedFileSystem
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable: "源文件不存在或已不可用，请重新选择。"
        case .unsupportedSource: "目前仅支持单个普通文件，暂不支持文件夹或符号链接。"
        case .invalidDestination: "移动目的地不是可用的文件夹，请重新选择。"
        case .sameLocation: "所选目的地就是源文件所在文件夹，请选择其他文件夹（例如“文稿”）。文件尚未移动。"
        case .alreadyExists(let name): "目的地已有“\(name)”，请更换文件夹或先处理同名文件。"
        case .accessDenied: "没有移动权限，请检查源文件所在文件夹和目的地的读写权限。"
        case .differentVolume: "目前仅支持同一磁盘内移动，请选择源文件所在磁盘的文件夹。"
        case .locationChanged: "操作期间源文件或目的地发生变化，请重新选择后重试。"
        case .unsupportedFileSystem: "这个文件系统不支持安全的无覆盖移动，请更换目的地。"
        case .operationFailed(let message): "移动失败：\(message)"
        }
    }
}

nonisolated enum FileMoveStatus: Equatable, Sendable {
    case idle
    case moving
    case moved(URL)
    case failed(String)
}
