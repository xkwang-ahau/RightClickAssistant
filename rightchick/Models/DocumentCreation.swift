import Foundation

nonisolated enum DocumentCreationError: LocalizedError, Equatable, Sendable {
    case emptyName
    case invalidName
    case nameTooLong
    case invalidDirectory
    case templateUnavailable(DocumentType)
    case alreadyExists(String)
    case accessDenied
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "请输入文件名称。"
        case .invalidName:
            "文件名称不能是 . 或 ..，也不能包含 /、\\、:、*、?、\"、<、>、| 或控制字符。"
        case .nameTooLong:
            "文件名称过长，请缩短名称。"
        case .invalidDirectory:
            "创建位置不可用，请重新选择一个文件夹。"
        case .templateUnavailable(let type):
            "无法读取 \(type.displayName) 空白模板，请重新安装应用。"
        case .alreadyExists(let name):
            "已存在“\(name)”，请更换名称。已有文件未被覆盖。"
        case .accessDenied:
            "无法写入所选文件夹，请检查权限或重新选择创建位置。"
        case .operationFailed(let detail):
            "创建失败：\(detail)"
        }
    }
}

nonisolated enum DocumentFileName {
    static func make(name: String, type: DocumentType) throws -> String {
        var baseName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseName.isEmpty else {
            throw DocumentCreationError.emptyName
        }

        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.controlCharacters)
        guard baseName.rangeOfCharacter(from: forbidden) == nil else {
            throw DocumentCreationError.invalidName
        }

        // 输入带有 Office 扩展名时统一规范化，切换文档类型也不会叠加后缀。
        while let suffix = DocumentType.allCases.first(where: {
            baseName.lowercased().hasSuffix(".\($0.fileExtension)")
        }) {
            baseName.removeLast(suffix.fileExtension.count + 1)
            baseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !baseName.isEmpty else {
            throw DocumentCreationError.emptyName
        }
        guard baseName != ".", baseName != ".." else {
            throw DocumentCreationError.invalidName
        }

        let result = "\(baseName).\(type.fileExtension)"
        guard result.utf8.count <= 255 else {
            throw DocumentCreationError.nameTooLong
        }
        return result
    }
}

nonisolated enum DocumentCreationStatus: Equatable, Sendable {
    case idle
    case creating
    case created(URL)
    case failed(String)
}
