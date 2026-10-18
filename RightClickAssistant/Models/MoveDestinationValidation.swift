import Foundation

nonisolated enum MoveDestinationValidation {
    static func isSourceDirectory(_ directory: URL, for source: URL) -> Bool {
        source.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
            == directory.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func validate(_ directory: URL, for source: URL) throws {
        guard directory.isFileURL else { throw FileMoveError.invalidDestination }
        guard !isSourceDirectory(directory, for: source) else { throw FileMoveError.sameLocation }
    }
}
