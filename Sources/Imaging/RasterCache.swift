import CoreGraphics
import Foundation

public struct RasterCacheKey: Hashable, Sendable {
    public let sourceURL: URL
    public let targetPixelWidth: Int
    public let targetPixelHeight: Int
    public let requiresFullResolution: Bool

    public init(sourceURL: URL, targetPixelSize: CGSize, requiresFullResolution: Bool) {
        self.sourceURL = sourceURL.standardizedFileURL
        targetPixelWidth = Int(targetPixelSize.width.rounded(.up))
        targetPixelHeight = Int(targetPixelSize.height.rounded(.up))
        self.requiresFullResolution = requiresFullResolution
    }
}

public final class RasterCache: @unchecked Sendable {
    private struct Entry {
        let asset: RasterAsset
        var lastAccess: UInt64
        var pinned: Bool
    }

    public let byteLimit: Int

    private let lock = NSLock()
    private var entries: [RasterCacheKey: Entry] = [:]
    private var byteCost = 0
    private var accessCounter: UInt64 = 0

    public init(byteLimit: Int) {
        self.byteLimit = max(0, byteLimit)
    }

    public var totalByteCost: Int {
        lock.withLock { byteCost }
    }

    public func value(for key: RasterCacheKey) -> RasterAsset? {
        lock.withLock {
            guard var entry = entries[key] else { return nil }
            accessCounter &+= 1
            entry.lastAccess = accessCounter
            entries[key] = entry
            return entry.asset
        }
    }

    public func insert(_ asset: RasterAsset, for key: RasterCacheKey, pinned: Bool = false) {
        lock.withLock {
            if let replaced = entries.removeValue(forKey: key) {
                byteCost -= replaced.asset.decodedByteCost
            }
            accessCounter &+= 1
            entries[key] = Entry(asset: asset, lastAccess: accessCounter, pinned: pinned)
            byteCost += asset.decodedByteCost
            trimToLimit()
        }
    }

    public func setPinned(_ pinned: Bool, for key: RasterCacheKey) {
        lock.withLock {
            guard var entry = entries[key] else { return }
            entry.pinned = pinned
            entries[key] = entry
            if !pinned { trimToLimit() }
        }
    }

    public func removeAllNonessential() {
        lock.withLock {
            entries = entries.filter { $0.value.pinned }
            byteCost = entries.values.reduce(0) { $0 + $1.asset.decodedByteCost }
        }
    }

    public func removeAll() {
        lock.withLock {
            entries.removeAll(keepingCapacity: false)
            byteCost = 0
        }
    }

    private func trimToLimit() {
        while byteCost > byteLimit {
            guard let victim = entries
                .filter({ !$0.value.pinned })
                .min(by: { $0.value.lastAccess < $1.value.lastAccess }) else {
                return
            }
            entries.removeValue(forKey: victim.key)
            byteCost -= victim.value.asset.decodedByteCost
        }
    }
}
