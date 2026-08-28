import Foundation

public struct BookmarkResolution: Sendable, Equatable {
    public let url: URL
    public let isStale: Bool

    public init(url: URL, isStale: Bool) {
        self.url = url.standardizedFileURL
        self.isStale = isStale
    }
}

public struct SecurityScopedBookmarkOperations: @unchecked Sendable {
    public let create: @Sendable (URL) throws -> Data
    public let resolve: @Sendable (Data) throws -> BookmarkResolution
    public let start: @Sendable (URL) -> Bool
    public let stop: @Sendable (URL) -> Void

    public init(
        create: @escaping @Sendable (URL) throws -> Data,
        resolve: @escaping @Sendable (Data) throws -> BookmarkResolution,
        start: @escaping @Sendable (URL) -> Bool,
        stop: @escaping @Sendable (URL) -> Void
    ) {
        self.create = create
        self.resolve = resolve
        self.start = start
        self.stop = stop
    }

    public static let system = SecurityScopedBookmarkOperations(
        create: { url in
            try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        },
        resolve: { data in
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            return BookmarkResolution(url: url, isStale: stale)
        },
        start: { $0.startAccessingSecurityScopedResource() },
        stop: { $0.stopAccessingSecurityScopedResource() }
    )
}

public final class SecurityScopedBookmarkStore: @unchecked Sendable {
    public typealias Load = @Sendable () -> [String: Data]
    public typealias Save = @Sendable ([String: Data]) -> Void

    private let lock = NSLock()
    private let load: Load
    private let save: Save
    private let operations: SecurityScopedBookmarkOperations

    public init(
        defaults: UserDefaults = .standard,
        key: String = "securityScopedFolderBookmarks",
        operations: SecurityScopedBookmarkOperations = .system
    ) {
        let defaultsBox = UserDefaultsBox(defaults)
        self.load = {
            guard let data = defaultsBox.value.data(forKey: key) else { return [:] }
            return (try? PropertyListDecoder().decode([String: Data].self, from: data)) ?? [:]
        }
        self.save = { bookmarks in
            if bookmarks.isEmpty {
                defaultsBox.value.removeObject(forKey: key)
            } else if let data = try? PropertyListEncoder().encode(bookmarks) {
                defaultsBox.value.set(data, forKey: key)
            }
        }
        self.operations = operations
    }

    public init(
        load: @escaping Load,
        save: @escaping Save,
        operations: SecurityScopedBookmarkOperations = .system
    ) {
        self.load = load
        self.save = save
        self.operations = operations
    }

    public func persistAccess(to folderURL: URL) throws {
        let normalized = folderURL.standardizedFileURL
        let data = try operations.create(normalized)
        lock.withLock {
            var bookmarks = load()
            bookmarks[normalized.path] = data
            save(bookmarks)
        }
    }

    public func access(to requestedURL: URL) -> AccessLease? {
        let requested = requestedURL.standardizedFileURL
        let resolved: URL? = lock.withLock {
            var bookmarks = load()
            var removals: [String] = []
            var replacements: [(oldKey: String, newURL: URL, data: Data)] = []
            var candidates: [URL] = []

            for (storedPath, data) in bookmarks {
                do {
                    let resolution = try operations.resolve(data)
                    let folder = resolution.url.standardizedFileURL
                    if resolution.isStale {
                        replacements.append((storedPath, folder, try operations.create(folder)))
                    }
                    if Self.contains(folder, requested) { candidates.append(folder) }
                } catch {
                    removals.append(storedPath)
                }
            }
            removals.forEach { bookmarks.removeValue(forKey: $0) }
            for replacement in replacements {
                bookmarks.removeValue(forKey: replacement.oldKey)
                bookmarks[replacement.newURL.path] = replacement.data
            }
            if !removals.isEmpty || !replacements.isEmpty { save(bookmarks) }
            return candidates.max { $0.pathComponents.count < $1.pathComponents.count }
        }
        guard let resolved, operations.start(resolved) else { return nil }
        return AccessLease(url: resolved) { [operations] in operations.stop(resolved) }
    }

    public func accessDirectly(to url: URL) -> AccessLease {
        let normalized = url.standardizedFileURL
        let didStart = operations.start(normalized)
        return AccessLease(url: normalized) { [operations] in
            if didStart { operations.stop(normalized) }
        }
    }

    private static func contains(_ folder: URL, _ requested: URL) -> Bool {
        let folderComponents = folder.standardizedFileURL.pathComponents
        let requestedComponents = requested.standardizedFileURL.pathComponents
        guard folderComponents.count <= requestedComponents.count else { return false }
        return Array(requestedComponents.prefix(folderComponents.count)) == folderComponents
    }
}

private final class UserDefaultsBox: @unchecked Sendable {
    let value: UserDefaults

    init(_ value: UserDefaults) {
        self.value = value
    }
}
