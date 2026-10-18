import Darwin
import Foundation

nonisolated protocol DocumentCreating: Sendable {
    func createDocument(type: DocumentType, name: String, in directory: URL) async throws -> URL
}

nonisolated extension DocumentCreating {
    func createDocument(type: DocumentType, name: String, in directory: URL, accessing root: URL) async throws -> URL {
        let didStart = root.startAccessingSecurityScopedResource()
        defer {
            if didStart { root.stopAccessingSecurityScopedResource() }
        }
        return try await createDocument(type: type, name: name, in: directory)
    }

    func createNewDocument(type: DocumentType, in directory: URL, accessing root: URL) async throws -> URL {
        let didStart = root.startAccessingSecurityScopedResource()
        defer {
            if didStart { root.stopAccessingSecurityScopedResource() }
        }
        return try await createNewDocument(type: type, in: directory)
    }

    // 每次实际复制拒绝已有目标后才换名，不能靠事前存在检查防止竞争覆盖。
    func createNewDocument(type: DocumentType, in directory: URL) async throws -> URL {
        for number in 1...1000 {
            try Task.checkCancellation()
            let name = number == 1 ? type.newDocumentName : "\(type.newDocumentName) (\(number))"
            do {
                return try await createDocument(type: type, name: name, in: directory)
            } catch let error as DocumentCreationError {
                guard case .alreadyExists = error, number < 1000 else { throw error }
            }
        }
        throw DocumentCreationError.operationFailed("可用名称已用尽，请在主窗口指定名称。")
    }
}

nonisolated protocol FileMoving: Sendable {
    /// 以指定名称移动到目录；replaceExisting 为 true 时按系统原子替换已有同名普通文件。
    func moveFile(at source: URL, to directory: URL, name: String, replaceExisting: Bool) async throws -> URL
}

nonisolated extension FileMoving {
    /// 保留源文件名，绝不覆盖已有目标。
    func moveFile(at source: URL, to directory: URL) async throws -> URL {
        try await moveFile(at: source, to: directory, name: source.lastPathComponent, replaceExisting: false)
    }

    /// 同名冲突时自动改用“名称 (2)”等可用编号，保留两者。
    func moveFileKeepingBoth(at source: URL, to directory: URL) async throws -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let fileExtension = source.pathExtension
        for number in 2...1000 {
            try Task.checkCancellation()
            let name = fileExtension.isEmpty ? "\(base) (\(number))" : "\(base) (\(number)).\(fileExtension)"
            do {
                return try await moveFile(at: source, to: directory, name: name, replaceExisting: false)
            } catch let error as FileMoveError {
                guard case .alreadyExists = error, number < 1000 else { throw error }
            }
        }
        throw FileMoveError.operationFailed("可用名称已用尽，请先整理目的地。")
    }
}

actor FileOperationService: DocumentCreating, FileMoving {
    private let templateURLs: [DocumentType: URL]
    private let fileManager = FileManager()
    private let moveOperation: @Sendable (URL, URL) throws -> Void
    private let replaceOperation: @Sendable (URL, URL) throws -> Void

    init(
        bundle: Bundle = .main,
        moveOperation: @escaping @Sendable (URL, URL) throws -> Void = ExclusiveFileMove.perform,
        replaceOperation: @escaping @Sendable (URL, URL) throws -> Void = ExclusiveFileMove.replace
    ) {
        self.moveOperation = moveOperation
        self.replaceOperation = replaceOperation
        templateURLs = Dictionary(uniqueKeysWithValues: DocumentType.allCases.compactMap { type in
            guard let url = bundle.url(
                forResource: type.templateResourceName,
                withExtension: type.fileExtension
            ) else {
                return nil
            }
            return (type, url)
        })
    }

    init(
        templateURLs: [DocumentType: URL],
        moveOperation: @escaping @Sendable (URL, URL) throws -> Void = ExclusiveFileMove.perform,
        replaceOperation: @escaping @Sendable (URL, URL) throws -> Void = ExclusiveFileMove.replace
    ) {
        self.templateURLs = templateURLs
        self.moveOperation = moveOperation
        self.replaceOperation = replaceOperation
    }

    func createDocument(type: DocumentType, name: String, in directory: URL) throws -> URL {
        try Task.checkCancellation()
        let fileName = try DocumentFileName.make(name: name, type: type)
        guard directory.isFileURL else {
            throw DocumentCreationError.invalidDirectory
        }

        let didStartAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                throw DocumentCreationError.invalidDirectory
            }
        } catch let error as DocumentCreationError {
            throw error
        } catch {
            let code = (error as NSError).code
            if code == CocoaError.fileReadNoPermission.rawValue {
                throw DocumentCreationError.accessDenied
            }
            throw DocumentCreationError.invalidDirectory
        }

        guard let templateURL = templateURLs[type],
              fileManager.isReadableFile(atPath: templateURL.path) else {
            throw DocumentCreationError.templateUnavailable(type)
        }

        let destination = directory.appendingPathComponent(fileName, isDirectory: false)
        try Task.checkCancellation()

        do {
            // copyItem 自身拒绝同名目标，不依赖可能被并发操作绕过的事前存在检查。
            try fileManager.copyItem(at: templateURL, to: destination)
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain {
                switch CocoaError.Code(rawValue: failure.code) {
                case .fileWriteFileExists:
                    throw DocumentCreationError.alreadyExists(fileName)
                case .fileReadNoPermission, .fileWriteNoPermission, .fileWriteVolumeReadOnly:
                    throw DocumentCreationError.accessDenied
                default:
                    break
                }
            }
            throw DocumentCreationError.operationFailed(error.localizedDescription)
        }

        // 文件已经生成后按成功返回，不能因迟来的取消把成功误报为未执行。
        return destination
    }

    func moveFile(at source: URL, to directory: URL, name: String, replaceExisting: Bool) throws -> URL {
        try Task.checkCancellation()
        // URL.path 可能隐藏编码后的空字符，原始编码路径也要检查。
        guard source.isFileURL, !source.path.contains("\0"),
              !source.path(percentEncoded: true).contains("%00") else {
            throw FileMoveError.sourceUnavailable
        }
        guard directory.isFileURL, !directory.path.contains("\0"),
              !directory.path(percentEncoded: true).contains("%00") else {
            throw FileMoveError.invalidDestination
        }
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\0"), name.utf8.count <= 255 else {
            throw FileMoveError.invalidDestination
        }

        let sourceAccess = source.startAccessingSecurityScopedResource()
        let destinationAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if sourceAccess { source.stopAccessingSecurityScopedResource() }
            if destinationAccess { directory.stopAccessingSecurityScopedResource() }
        }

        do {
            // attributesOfItem 检查链接本身，避免把符号链接当成普通文件。
            let attributes = try fileManager.attributesOfItem(atPath: source.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw FileMoveError.unsupportedSource
            }
        } catch let error as FileMoveError {
            throw error
        } catch {
            if (error as NSError).code == CocoaError.fileReadNoPermission.rawValue {
                throw FileMoveError.accessDenied
            }
            throw FileMoveError.sourceUnavailable
        }

        let targetDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        do {
            let values = try targetDirectory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { throw FileMoveError.invalidDestination }
        } catch let error as FileMoveError {
            throw error
        } catch {
            if (error as NSError).code == CocoaError.fileReadNoPermission.rawValue {
                throw FileMoveError.accessDenied
            }
            throw FileMoveError.invalidDestination
        }

        try MoveDestinationValidation.validate(directory, for: source)
        let destination = directory.appendingPathComponent(name, isDirectory: false)

        if replaceExisting,
           let attributes = try? fileManager.attributesOfItem(atPath: destination.path),
           let type = attributes[.type] as? FileAttributeType, type != .typeRegular {
            // 只替换普通文件；目录、符号链接等仍按冲突处理，避免误删。
            throw FileMoveError.alreadyExists(name)
        }
        try Task.checkCancellation()

        do {
            if replaceExisting {
                try replaceOperation(source, destination)
            } else {
                try moveOperation(source, destination)
            }
        } catch {
            let failure = error as NSError
            if failure.domain == NSPOSIXErrorDomain {
                switch failure.code {
                case Int(EEXIST): throw FileMoveError.alreadyExists(name)
                case Int(EISDIR), Int(ENOTDIR): throw FileMoveError.alreadyExists(name)
                case Int(EXDEV): throw FileMoveError.differentVolume
                case Int(EACCES), Int(EPERM), Int(EROFS): throw FileMoveError.accessDenied
                case Int(ENOENT): throw FileMoveError.locationChanged
                case Int(ENOTSUP), Int(EINVAL): throw FileMoveError.unsupportedFileSystem
                default: break
                }
            }
            throw FileMoveError.operationFailed(error.localizedDescription)
        }

        // 重命名已经完成时返回真实成功结果，不把迟来的取消当作未移动。
        return destination
    }
}
