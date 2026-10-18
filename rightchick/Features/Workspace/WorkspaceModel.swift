import AppKit
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class WorkspaceModel {
    var selectedDocumentType: DocumentType = .word
    var documentName = "未命名"
    private(set) var creationDirectory: URL?
    private(set) var moveDestination: URL?
    private(set) var sourceFile: URL?
    private(set) var creationStatus: DocumentCreationStatus = .idle
    private(set) var moveStatus: FileMoveStatus = .idle
    private(set) var creationDirectoryMessage: String?
    private(set) var moveDestinationMessage: String?
    private(set) var finderRequestMessage: String?
    private(set) var finderResultURL: URL?
    private var isAuthorizingFinder = false
    private(set) var creationAccessRoot: URL?

    private let folderPicker: any FolderPicking
    private let documentCreator: any DocumentCreating
    private let filePicker: any FilePicking
    private let fileMover: any FileMoving
    private let bookmarkStore: (any FolderBookmarkPersisting)?
    private let moveConflictResolver: any MoveConflictResolving
    @ObservationIgnored private var creationTask: Task<Void, Never>?
    @ObservationIgnored private var moveTask: Task<Void, Never>?

    init(
        folderPicker: any FolderPicking,
        documentCreator: any DocumentCreating,
        filePicker: any FilePicking,
        fileMover: any FileMoving,
        bookmarkStore: (any FolderBookmarkPersisting)? = nil,
        moveConflictResolver: (any MoveConflictResolving)? = nil
    ) {
        self.folderPicker = folderPicker
        self.documentCreator = documentCreator
        self.filePicker = filePicker
        self.fileMover = fileMover
        self.bookmarkStore = bookmarkStore
        self.moveConflictResolver = moveConflictResolver ?? MoveConflictResolver()
        restoreDirectories()
    }

    private var validatedFileName: Result<String, Error> {
        Result { try DocumentFileName.make(name: documentName, type: selectedDocumentType) }
    }

    var documentNamePreview: String {
        switch validatedFileName {
        case .success(let name): name
        case .failure: "请输入有效的文件名称"
        }
    }

    var nameValidationMessage: String? {
        switch validatedFileName {
        case .success: nil
        case .failure(let error): error.localizedDescription
        }
    }

    var isCreating: Bool {
        creationStatus == .creating
    }

    var canCreateDocument: Bool {
        creationDirectory != nil && nameValidationMessage == nil && !isBusy
    }

    var isMoving: Bool {
        moveStatus == .moving
    }

    var isBusy: Bool {
        isCreating || isMoving || isAuthorizingFinder
    }

    var canMoveFile: Bool {
        sourceFile != nil && moveDestination != nil && !isBusy
    }

    func chooseCreationDirectory() {
        guard !isBusy else { return }
        if let directory = folderPicker.chooseFolder(
            title: "授权文件夹及其子目录",
            initialDirectory: creationAccessRoot
        ) {
            creationDirectory = directory
            creationAccessRoot = directory
            creationStatus = .idle
            creationDirectoryMessage = saveDirectory(directory, for: .creationDirectory)
        }
    }

    func chooseMoveDestination() {
        guard !isBusy else { return }
        if let directory = folderPicker.chooseFolder(
            title: "选择文件移动目的地",
            initialDirectory: moveDestination
        ) {
            moveDestination = directory
            moveStatus = .idle
            moveDestinationMessage = saveDirectory(directory, for: .moveDestination)
        }
    }

    private func restoreDirectories() {
        guard let bookmarkStore else { return }
        for preference in FolderPreference.allCases {
            let restoration = bookmarkStore.restore(preference)
            let directory: URL?
            let message: String?
            switch restoration {
            case .notSaved:
                directory = nil
                message = nil
            case .restored(let url):
                directory = url
                message = nil
            case .requiresReselection:
                directory = nil
                message = FolderBookmarkError.unavailable.localizedDescription
            }
            switch preference {
            case .creationDirectory:
                creationDirectory = directory
                creationAccessRoot = directory
                creationDirectoryMessage = message
            case .moveDestination:
                moveDestination = directory
                moveDestinationMessage = message
            }
        }
    }

    private func saveDirectory(_ directory: URL, for preference: FolderPreference) -> String? {
        guard let bookmarkStore else { return nil }
        do {
            try bookmarkStore.save(directory, for: preference)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func clearCreationDirectory() {
        guard !isBusy else { return }
        bookmarkStore?.clear(.creationDirectory)
        creationDirectory = nil
        creationAccessRoot = nil
        creationDirectoryMessage = nil
        creationStatus = .idle
    }

    func clearMoveDestination() {
        guard !isBusy else { return }
        bookmarkStore?.clear(.moveDestination)
        moveDestination = nil
        moveDestinationMessage = nil
        moveStatus = .idle
    }

    func handleFinderURL(_ url: URL) {
        let logger = Logger(subsystem: "devplaceholder.JW2H7X4Z.RightClickAssistant", category: "FinderRequest")
        logger.notice("Processing Finder request")
        guard let request = FinderRequest.decode(url) else {
            finderResultURL = nil
            finderRequestMessage = "无法识别 Finder 请求，请重新从右键菜单打开。"
            return
        }
        if request.action == .open {
            return
        }
        guard !isBusy, creationTask == nil, moveTask == nil else {
            finderRequestMessage = "当前文件操作尚未完成，请完成后重新点击 Finder 菜单。"
            return
        }
        guard let location = request.location else { return }
        finderResultURL = nil
        logger.notice("Finder request action: \(request.action.rawValue, privacy: .public)")
        switch request.action {
        case .word, .powerPoint, .excel:
            switch request.action {
            case .word: selectedDocumentType = .word
            case .powerPoint: selectedDocumentType = .powerPoint
            case .excel: selectedDocumentType = .excel
            case .move, .open: break
            }
            // 应用不在沙盒中：直接使用 Finder 提供的目录，受保护位置由系统完全磁盘访问/TCC 处理。
            let directory = location
            let type = selectedDocumentType
            creationDirectory = directory
            creationAccessRoot = directory
            documentName = type.newDocumentName
            creationStatus = .creating
            finderRequestMessage = "正在新建\(type.displayName)文档…"
            creationTask = Task {
                defer { creationTask = nil }
                do {
                    let output = try await documentCreator.createNewDocument(type: type, in: directory, accessing: directory)
                    documentName = output.deletingPathExtension().lastPathComponent
                    creationStatus = .created(output)
                    finderResultURL = output
                    finderRequestMessage = "已创建“\(output.lastPathComponent)”：\(output.deletingLastPathComponent().path)"
                } catch is CancellationError {
                    creationStatus = .idle
                    finderRequestMessage = "已取消新建文档。"
                } catch {
                    creationStatus = .failed(error.localizedDescription)
                    finderRequestMessage = error.localizedDescription
                }
            }
        case .move:
            isAuthorizingFinder = true
            let destination = folderPicker.chooseMoveDestination(for: location, initialDirectory: moveDestination)
            isAuthorizingFinder = false
            guard let destination else {
                finderRequestMessage = "已取消移动，文件位置未改变。"
                return
            }
            logger.notice("Moving source: \(location.path, privacy: .private), destination: \(destination.path, privacy: .private)")
            sourceFile = location
            moveDestination = destination
            moveDestinationMessage = saveDirectory(destination, for: .moveDestination)
            moveStatus = .moving
            finderRequestMessage = "正在移动“\(location.lastPathComponent)”…"
            moveTask = Task {
                defer { moveTask = nil }
                await performMenuMove(source: location, destination: destination)
            }
        case .open:
            break
        }
    }

    private func performMenuMove(source: URL, destination: URL) async {
        let logger = Logger(subsystem: "devplaceholder.JW2H7X4Z.RightClickAssistant", category: "FinderRequest")
        do {
            let output = try await fileMover.moveFile(at: source, to: destination)
            logger.notice("Menu file move succeeded")
            finishMenuMove(output)
        } catch let error as FileMoveError {
            guard case .alreadyExists = error else {
                logger.error("Menu file move failed: \(error.localizedDescription, privacy: .private)")
                failMenuMove(error)
                return
            }
            // 目的地同名：交由用户决定，避免静默失败或意外覆盖。
            logger.notice("Menu file move conflict; asking user")
            switch moveConflictResolver.resolve(sourceName: source.lastPathComponent, destinationPath: destination.path) {
            case .cancel:
                moveStatus = .idle
                finderRequestMessage = "已取消移动；目的地同名文件保持不变。"
            case .replace:
                do {
                    let output = try await fileMover.moveFile(
                        at: source, to: destination, name: source.lastPathComponent, replaceExisting: true
                    )
                    logger.notice("Menu file move replaced destination")
                    finishMenuMove(output)
                } catch is CancellationError {
                    moveStatus = .idle
                    finderRequestMessage = "已取消移动。"
                } catch {
                    logger.error("Menu file replace failed: \(error.localizedDescription, privacy: .private)")
                    failMenuMove(error)
                }
            case .keepBoth:
                do {
                    let output = try await fileMover.moveFileKeepingBoth(at: source, to: destination)
                    logger.notice("Menu file move kept both")
                    finishMenuMove(output)
                } catch is CancellationError {
                    moveStatus = .idle
                    finderRequestMessage = "已取消移动。"
                } catch {
                    logger.error("Menu file keep-both failed: \(error.localizedDescription, privacy: .private)")
                    failMenuMove(error)
                }
            }
        } catch is CancellationError {
            moveStatus = .idle
            finderRequestMessage = "已取消移动。"
        } catch {
            logger.error("Menu file move failed: \(error.localizedDescription, privacy: .private)")
            failMenuMove(error)
        }
    }

    private func finishMenuMove(_ output: URL) {
        sourceFile = nil
        moveStatus = .moved(output)
        finderResultURL = output
        finderRequestMessage = "已移动“\(output.lastPathComponent)”：\(output.deletingLastPathComponent().path)"
    }

    private func failMenuMove(_ error: Error) {
        moveStatus = .failed(error.localizedDescription)
        finderRequestMessage = error.localizedDescription
    }

    func revealFinderResult() {
        guard let url = finderResultURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func chooseSourceFile() {
        guard !isBusy else { return }
        if let file = filePicker.chooseFile(
            title: "选择要移动的文件",
            initialDirectory: sourceFile?.deletingLastPathComponent()
        ) {
            sourceFile = file
            moveStatus = .idle
        }
    }

    func startCreatingDocument() {
        guard creationTask == nil, moveTask == nil, !isBusy else { return }
        creationTask = Task {
            await createDocument()
            creationTask = nil
        }
    }

    func cancelPendingOperations() {
        creationTask?.cancel()
        moveTask?.cancel()
    }

    func createDocument() async {
        guard !isBusy else { return }
        guard let directory = creationDirectory else {
            creationStatus = .failed("请先选择文档创建位置。")
            return
        }
        if case .failure(let error) = validatedFileName {
            creationStatus = .failed(error.localizedDescription)
            return
        }

        // 固定本次请求的输入，异步操作期间不会读取到后来修改的名称或目录。
        let type = selectedDocumentType
        let name = documentName
        let root = creationAccessRoot ?? directory
        creationStatus = .creating

        do {
            let url = try await documentCreator.createDocument(type: type, name: name, in: directory, accessing: root)
            creationStatus = .created(url)
        } catch is CancellationError {
            creationStatus = .idle
        } catch {
            creationStatus = .failed(error.localizedDescription)
        }
    }

    func revealCreatedDocument() {
        guard case .created(let url) = creationStatus else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func startMovingFile() {
        guard moveTask == nil, creationTask == nil, !isBusy else { return }
        moveTask = Task {
            await moveFile()
            moveTask = nil
        }
    }

    func moveFile() async {
        guard !isBusy else { return }
        guard let source = sourceFile else {
            moveStatus = .failed("请先选择要移动的文件。")
            return
        }
        guard let directory = moveDestination else {
            moveStatus = .failed("请先选择移动目的地。")
            return
        }
        moveStatus = .moving

        do {
            let output = try await fileMover.moveFile(at: source, to: directory)
            sourceFile = nil
            moveStatus = .moved(output)
        } catch is CancellationError {
            moveStatus = .idle
        } catch {
            moveStatus = .failed(error.localizedDescription)
        }
    }

    func revealMovedFile() {
        guard case .moved(let url) = moveStatus else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
