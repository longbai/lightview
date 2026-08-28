import Foundation

public final class AccessLease: @unchecked Sendable {
    public let url: URL

    private let lock = NSLock()
    private var releaseAction: (@Sendable () -> Void)?

    public init(url: URL, release: @escaping @Sendable () -> Void = {}) {
        self.url = url.standardizedFileURL
        releaseAction = release
    }

    deinit {
        end()
    }

    public func end() {
        let action = lock.withLock { () -> (@Sendable () -> Void)? in
            defer { releaseAction = nil }
            return releaseAction
        }
        action?()
    }
}

public protocol FolderAccessProvider: Sendable {
    func accessImage(at url: URL) throws -> AccessLease
    func accessContainingFolder(of url: URL) throws -> AccessLease
    func restorePersistedAccess(to url: URL) throws -> AccessLease?
    func authorizeFolder(at url: URL) throws -> AccessLease
}

public enum FolderAccessError: Error, Sendable, Equatable {
    case authorizationRequired(URL)
}
