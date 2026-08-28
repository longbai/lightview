import Foundation

public enum CatalogSort: String, Sendable, CaseIterable {
    case nameAscending
    case nameDescending
    case modificationDateNewest
    case modificationDateOldest
    case sizeLargest
    case sizeSmallest
}

public enum CatalogDirection: Sendable, Equatable {
    case previous
    case next
}

public struct CatalogEntry: Sendable, Equatable {
    public let url: URL
    public let name: String
    public let modificationDate: Date?
    public let byteCount: Int64?

    public init(url: URL, name: String, modificationDate: Date?, byteCount: Int64?) {
        self.url = url
        self.name = name
        self.modificationDate = modificationDate
        self.byteCount = byteCount
    }
}

public struct FolderCatalog: Sendable {
    public let directoryURL: URL
    public let entries: [CatalogEntry]

    public init(
        directoryURL: URL,
        sort: CatalogSort = .nameAscending,
        includeHidden: Bool = false,
        fileManager: FileManager = .default
    ) throws {
        self.directoryURL = directoryURL.standardizedFileURL
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isHiddenKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]
        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }

        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: options
        )
        let candidates = try urls.compactMap { url -> CatalogEntry? in
            guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { return nil }
            if !includeHidden, values.isHidden == true { return nil }
            return CatalogEntry(
                url: url.standardizedFileURL,
                name: url.lastPathComponent,
                modificationDate: values.contentModificationDate,
                byteCount: values.fileSize.map(Int64.init)
            )
        }
        entries = candidates.sorted { Self.isOrdered($0, before: $1, by: sort) }
    }

    public func index(of url: URL) -> Int? {
        let normalizedURL = url.standardizedFileURL
        return entries.firstIndex(where: { $0.url == normalizedURL })
    }

    public func neighbor(
        from url: URL,
        direction: CatalogDirection,
        wraps: Bool
    ) -> CatalogEntry? {
        guard let currentIndex = index(of: url), !entries.isEmpty else { return nil }
        switch direction {
        case .previous:
            if currentIndex > entries.startIndex { return entries[currentIndex - 1] }
            return wraps ? entries.last : nil
        case .next:
            let nextIndex = currentIndex + 1
            if nextIndex < entries.endIndex { return entries[nextIndex] }
            return wraps ? entries.first : nil
        }
    }

    private static let supportedExtensions: Set<String> = [
        "apng", "arw", "avif", "bmp", "cr2", "cr3", "cur", "dng", "erf", "gif", "heic", "heif",
        "hif", "ico", "j2k", "jpe", "jpeg", "jp2", "jpf", "jpg", "jpx", "mos", "mrw",
        "nef", "nrw", "orf", "pef", "png", "raf", "raw", "rw2", "srw", "svg", "tif",
        "tiff", "webp", "x3f",
    ]

    private static func isOrdered(
        _ left: CatalogEntry,
        before right: CatalogEntry,
        by sort: CatalogSort
    ) -> Bool {
        let primary: ComparisonResult
        switch sort {
        case .nameAscending:
            primary = compareNames(left.name, right.name)
        case .nameDescending:
            primary = compareNames(right.name, left.name)
        case .modificationDateNewest:
            primary = compare(right.modificationDate ?? .distantPast, left.modificationDate ?? .distantPast)
        case .modificationDateOldest:
            primary = compare(left.modificationDate ?? .distantPast, right.modificationDate ?? .distantPast)
        case .sizeLargest:
            primary = compare(right.byteCount ?? 0, left.byteCount ?? 0)
        case .sizeSmallest:
            primary = compare(left.byteCount ?? 0, right.byteCount ?? 0)
        }

        if primary != .orderedSame { return primary == .orderedAscending }
        return left.url.path.compare(right.url.path, options: [.literal, .caseInsensitive]) == .orderedAscending
    }

    private static func compareNames(_ left: String, _ right: String) -> ComparisonResult {
        left.compare(right, options: [.numeric, .caseInsensitive], locale: .current)
    }

    private static func compare<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
    }
}
