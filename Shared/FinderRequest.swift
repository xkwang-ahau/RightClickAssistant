import Foundation

nonisolated enum FinderAction: String, CaseIterable, Sendable {
    case word
    case powerPoint
    case excel
    case move
    case open
}

nonisolated struct FinderRequest: Equatable, Sendable {
    static let scheme = "rightclickassistant"
    let action: FinderAction
    let location: URL?

    var url: URL? {
        guard location?.isFileURL ?? true else { return nil }
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "finder"
        components.queryItems = [URLQueryItem(name: "action", value: action.rawValue)]
        if let location {
            components.queryItems?.append(URLQueryItem(name: "path", value: location.path))
        }
        guard let url = components.url, let decoded = Self.decode(url),
              decoded.action == action, decoded.location?.path == location?.path else { return nil }
        return url
    }

    static func decode(_ url: URL) -> Self? {
        guard url.absoluteString.utf8.count <= 32_768,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == scheme, components.host == "finder",
              components.path.isEmpty, components.fragment == nil,
              components.user == nil, components.password == nil, components.port == nil,
              let items = components.queryItems,
              items.allSatisfy({ $0.name == "action" || $0.name == "path" }),
              items.filter({ $0.name == "action" }).count == 1,
              items.filter({ $0.name == "path" }).count <= 1,
              let rawAction = items.first(where: { $0.name == "action" })?.value,
              let action = FinderAction(rawValue: rawAction) else { return nil }
        if action == .open {
            return items.count == 1 ? Self(action: .open, location: nil) : nil
        }
        guard let path = items.first(where: { $0.name == "path" })?.value,
              path.hasPrefix("/"), !path.contains("\0"), path.utf8.count <= 4096 else { return nil }
        return Self(action: action, location: URL(fileURLWithPath: path))
    }
}

nonisolated enum FinderMenuScope {
    static func directories(mountedVolumes: [URL]) -> Set<URL> {
        // 明确注册卷根，避免依赖 Finder 是否跨挂载点传播根目录的监控。
        var roots = Set([URL(fileURLWithPath: "/", isDirectory: true)])
        for volume in mountedVolumes where volume.isFileURL && !volume.path(percentEncoded: true).contains("%00") {
            roots.insert(volume.standardizedFileURL)
        }
        return roots
    }
}
