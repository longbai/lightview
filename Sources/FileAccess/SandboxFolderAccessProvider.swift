import Foundation

public struct SandboxFolderAccessProvider: FolderAccessProvider, @unchecked Sendable {
    private let bookmarkStore: SecurityScopedBookmarkStore
    private let fileManager: FileManager

    public init(
        bookmarkStore: SecurityScopedBookmarkStore = SecurityScopedBookmarkStore(),
        fileManager: FileManager = .default
    ) {
        self.bookmarkStore = bookmarkStore
        self.fileManager = fileManager
    }

    public func accessImage(at url: URL) throws -> AccessLease {
        let lease = bookmarkStore.accessDirectly(to: url)
        do {
            try validateFile(at: lease.url)
            return lease
        } catch {
            lease.end()
            throw error
        }
    }

    public func accessContainingFolder(of url: URL) throws -> AccessLease {
        let folder = url.standardizedFileURL.deletingLastPathComponent()
        guard let lease = bookmarkStore.access(to: folder) else {
            throw FolderAccessError.authorizationRequired(folder)
        }
        return lease
    }

    public func restorePersistedAccess(to url: URL) throws -> AccessLease? {
        bookmarkStore.access(to: url)
    }

    public func authorizeFolder(at url: URL) throws -> AccessLease {
        let normalized = url.standardizedFileURL
        try validateDirectory(at: normalized)
        try bookmarkStore.persistAccess(to: normalized)
        guard let lease = bookmarkStore.access(to: normalized) else {
            throw ImageLoadError.accessDenied(normalized)
        }
        return lease
    }

    private func validateFile(at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ImageLoadError.missing(url)
        }
        guard !isDirectory.boolValue, fileManager.isReadableFile(atPath: url.path) else {
            throw ImageLoadError.accessDenied(url)
        }
    }

    private func validateDirectory(at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ImageLoadError.missing(url)
        }
        guard isDirectory.boolValue, fileManager.isReadableFile(atPath: url.path) else {
            throw ImageLoadError.accessDenied(url)
        }
    }
}
