import Darwin
import Foundation

nonisolated enum ExclusiveFileMove {
    static func perform(source: URL, destination: URL) throws {
        let outcome = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else {
                    return (result: Int32(-1), error: Int32(EINVAL))
                }
                // RENAME_EXCL 在一次操作内拒绝已有目标；跨卷不回退到复制后删除。
                let result = renamex_np(sourcePath, destinationPath, UInt32(RENAME_EXCL))
                return (result: result, error: errno)
            }
        }
        guard outcome.result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(outcome.error))
        }
    }

    /// 仅在用户确认后调用：rename 在同一卷内原子替换已有目标；跨卷返回 EXDEV，不回退复制删除。
    static func replace(source: URL, destination: URL) throws {
        let outcome = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else {
                    return (result: Int32(-1), error: Int32(EINVAL))
                }
                let result = rename(sourcePath, destinationPath)
                return (result: result, error: errno)
            }
        }
        guard outcome.result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(outcome.error))
        }
    }
}
