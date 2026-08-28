import AVFoundation
import CoreGraphics
import Foundation

public final class ExportImageRepository: @unchecked Sendable {
    private let urls: [URL]
    private let targetSize: CGSize
    private let decoder: any ImageDecoding
    private let animationDecoder: any AnimationAssetDecoding
    private let lock = NSLock()
    private var cache: [Int: DisplayAsset] = [:]
    private var recency: [Int] = []
    private let cacheCountLimit: Int

    public init(
        urls: [URL],
        targetSize: CGSize,
        cacheCountLimit: Int = 3,
        decoder: any ImageDecoding = ImageDecoderRouter(),
        animationDecoder: any AnimationAssetDecoding = AnimationDecoderRouter()
    ) {
        self.urls = urls.map(\.standardizedFileURL)
        self.targetSize = targetSize
        self.cacheCountLimit = max(1, cacheCountLimit)
        self.decoder = decoder
        self.animationDecoder = animationDecoder
    }

    public func prepareSources() throws -> [ExportSource] {
        try urls.enumerated().map { index, url in
            if let animation = try animationDecoder.decodeIfPresent(url: url) {
                return .animation(
                    identifier: url.path,
                    frameDurations: animation.frameDurations.map {
                        CMTime(seconds: $0, preferredTimescale: 600)
                    },
                    sourceLoopCount: animation.loopCount
                )
            }
            return .still(identifier: url.path)
        }
    }

    public func image(sourceIndex: Int, localTime: CMTime) throws -> CGImage {
        guard urls.indices.contains(sourceIndex) else {
            throw MovieExportError.invalidPlan("Export source index is out of bounds")
        }
        let asset = try cachedAsset(at: sourceIndex)
        switch asset {
        case .raster(let raster):
            return raster.image
        case .animation(let animation):
            let seconds = CMTimeGetSeconds(localTime)
            let cycle = animation.descriptor.cycleDuration
            let timeInCycle = cycle > 0 && seconds.isFinite ? seconds.truncatingRemainder(dividingBy: cycle) : 0
            let frameIndex = animation.descriptor.cumulativeFrameEndTimes.firstIndex {
                timeInCycle < $0
            } ?? max(0, animation.frameCount - 1)
            return try animation.provider.frame(at: frameIndex).image
        case .vector:
            throw MovieExportError.writerFailed("Vector export did not produce a raster")
        }
    }

    public func decodeBackgroundImage(at url: URL) throws -> CGImage {
        try decoder.decode(
            DecodeRequest(
                url: url,
                targetPixelSize: targetSize,
                requiresFullResolution: false,
                generation: 0
            ),
            cancellation: DecodeCancellation()
        ).image
    }

    private func cachedAsset(at index: Int) throws -> DisplayAsset {
        if let cached = lock.withLock({ cache[index] }) {
            touch(index)
            return cached
        }
        let url = urls[index]
        let decoded: DisplayAsset
        if let animation = try animationDecoder.decodeIfPresent(url: url) {
            decoded = .animation(animation)
        } else {
            decoded = .raster(try decoder.decode(
                DecodeRequest(
                    url: url,
                    targetPixelSize: targetSize,
                    requiresFullResolution: false,
                    generation: 0
                ),
                cancellation: DecodeCancellation()
            ))
        }
        lock.withLock {
            cache[index] = decoded
            recency.removeAll { $0 == index }
            recency.append(index)
            while recency.count > cacheCountLimit {
                cache.removeValue(forKey: recency.removeFirst())
            }
        }
        return decoded
    }

    private func touch(_ index: Int) {
        lock.withLock {
            recency.removeAll { $0 == index }
            recency.append(index)
        }
    }
}
