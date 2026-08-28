import Foundation

public protocol AnimationAssetDecoding: Sendable {
    func decodeIfPresent(url: URL, cancellation: DecodeCancellation) throws -> AnimationAsset?
}

public extension AnimationAssetDecoding {
    func decodeIfPresent(url: URL) throws -> AnimationAsset? {
        try decodeIfPresent(url: url, cancellation: DecodeCancellation())
    }
}

public protocol ImageInspectionProviding: Sendable {
    func inspect(url: URL) throws -> ImageInspection
}

public protocol AnimationDisplayDecoding: Sendable {
    func decode(url: URL, cancellation: DecodeCancellation) throws -> DisplayAsset
}

extension ImageIODecoder: ImageInspectionProviding {}
extension ImageIOAnimationDecoder: AnimationDisplayDecoding {}
extension WebPAnimationDecoder: AnimationDisplayDecoding {}

public struct AnimationDecoderRouter: AnimationAssetDecoding, Sendable {
    private let imageIOInspector: any ImageInspectionProviding
    private let imageIOAnimation: any AnimationDisplayDecoding
    private let webPAnimation: any AnimationDisplayDecoding

    public init(
        imageIOInspector: any ImageInspectionProviding = ImageIODecoder(),
        imageIOAnimation: any AnimationDisplayDecoding = ImageIOAnimationDecoder(),
        webPAnimation: any AnimationDisplayDecoding = WebPAnimationDecoder()
    ) {
        self.imageIOInspector = imageIOInspector
        self.imageIOAnimation = imageIOAnimation
        self.webPAnimation = webPAnimation
    }

    public func decodeIfPresent(url: URL, cancellation: DecodeCancellation) throws -> AnimationAsset? {
        try cancellation.throwIfCancelled()
        switch try format(for: url) {
        case .gif, .png:
            guard try imageIOInspector.inspect(url: url).frameCount > 1 else { return nil }
            return try animation(from: imageIOAnimation.decode(url: url, cancellation: cancellation))
        case .webP:
            do {
                let inspection = try imageIOInspector.inspect(url: url)
                if inspection.frameCount > 1 {
                    do {
                        let native = try animation(from: imageIOAnimation.decode(
                            url: url,
                            cancellation: cancellation
                        ))
                        let provider = NativeThenFallbackAnimationFrameProvider(
                            primary: native.provider,
                            fallbackFactory: { [webPAnimation] fallbackCancellation in
                                let displayAsset = try webPAnimation.decode(
                                    url: url,
                                    cancellation: fallbackCancellation
                                )
                                guard case let .animation(asset) = displayAsset else {
                                    throw ImageLoadError.decodeFailed(
                                        "WebP fallback returned a non-animation asset"
                                    )
                                }
                                return asset.provider
                            }
                        )
                        return AnimationAsset(
                            provider: provider,
                            format: .webP,
                            metadata: native.metadata
                        )
                    } catch {
                        try cancellation.throwIfCancelled()
                    }
                }
            } catch {
                try cancellation.throwIfCancelled()
            }
            do {
                return try animation(from: webPAnimation.decode(url: url, cancellation: cancellation))
            } catch ImageLoadError.corrupt {
                return nil
            }
        default:
            return nil
        }
    }

    private func animation(from displayAsset: DisplayAsset) throws -> AnimationAsset {
        guard case let .animation(asset) = displayAsset else {
            throw ImageLoadError.decodeFailed("Animation decoder returned a non-animation asset")
        }
        return asset
    }

    private func format(for url: URL) throws -> ImageFormat? {
        let normalizedURL = url.standardizedFileURL
        guard let handle = try? FileHandle(forReadingFrom: normalizedURL) else {
            if FileManager.default.fileExists(atPath: normalizedURL.path) {
                throw ImageLoadError.accessDenied(normalizedURL)
            }
            throw ImageLoadError.missing(normalizedURL)
        }
        defer { try? handle.close() }
        return FileSignatureDetector.detect(
            handle.readData(ofLength: FileSignatureDetector.maximumHeaderByteCount)
        )
    }
}

private final class NativeThenFallbackAnimationFrameProvider: AnimationFrameProvider, @unchecked Sendable {
    let descriptor: AnimationDescriptor
    private let primary: any AnimationFrameProvider
    private let fallbackFactory: @Sendable (DecodeCancellation) throws -> any AnimationFrameProvider
    private let lock = NSLock()
    private var fallback: (any AnimationFrameProvider)?
    private var primaryFailed = false

    init(
        primary: any AnimationFrameProvider,
        fallbackFactory: @escaping @Sendable (DecodeCancellation) throws -> any AnimationFrameProvider
    ) {
        self.primary = primary
        self.fallbackFactory = fallbackFactory
        descriptor = primary.descriptor
    }

    func frame(at index: Int) throws -> AnimationFrame {
        try frame(at: index, cancellation: DecodeCancellation())
    }

    func frame(at index: Int, cancellation: DecodeCancellation) throws -> AnimationFrame {
        try cancellation.throwIfCancelled()
        lock.lock()
        defer { lock.unlock() }

        if !primaryFailed {
            do {
                return try primary.frame(at: index, cancellation: cancellation)
            } catch {
                try cancellation.throwIfCancelled()
                primaryFailed = true
            }
        }
        if fallback == nil {
            let created = try fallbackFactory(cancellation)
            guard created.descriptor.canvasPixelSize == descriptor.canvasPixelSize,
                  created.descriptor.frameCount == descriptor.frameCount else {
                throw ImageLoadError.decodeFailed("Native and fallback WebP animation metadata differ")
            }
            fallback = created
        }
        guard let fallback else {
            throw ImageLoadError.decodeFailed("WebP fallback provider is unavailable")
        }
        return try fallback.frame(at: index, cancellation: cancellation)
    }
}
