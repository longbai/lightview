import Foundation

public struct DirectFolderAccessProvider: FolderAccessProvider, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func accessImage(at url: URL) throws -> AccessLease {
        let normalizedURL = url.standardizedFileURL
        guard fileManager.fileExists(atPath: normalizedURL.path) else {
            throw ImageLoadError.missing(normalizedURL)
        }
        let values = try normalizedURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true, fileManager.isReadableFile(atPath: normalizedURL.path) else {
            throw ImageLoadError.accessDenied(normalizedURL)
        }
        return AccessLease(url: normalizedURL)
    }

    public func accessContainingFolder(of url: URL) throws -> AccessLease {
        try accessDirectory(at: url.deletingLastPathComponent())
    }

    public func restorePersistedAccess(to url: URL) throws -> AccessLease? {
        try accessDirectory(at: url)
    }

    private func accessDirectory(at url: URL) throws -> AccessLease {
        let normalizedURL = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: normalizedURL.path, isDirectory: &isDirectory) else {
            throw ImageLoadError.missing(normalizedURL)
        }
        guard isDirectory.boolValue, fileManager.isReadableFile(atPath: normalizedURL.path) else {
            throw ImageLoadError.accessDenied(normalizedURL)
        }
        return AccessLease(url: normalizedURL)
    }
}
