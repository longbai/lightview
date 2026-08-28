import Foundation

public protocol ImageLoading: Sendable {
    @discardableResult
    func load(
        _ request: DecodeRequest,
        completion: @escaping @Sendable (Result<DisplayAsset, ImageLoadError>) -> Void
    ) -> DecodeCancellation

    func preload(_ requests: [DecodeRequest])
}

public extension ImageLoading {
    func preload(_ requests: [DecodeRequest]) {}
}

public final class ImageLoadPipeline: ImageLoading, @unchecked Sendable {
    private let decoder: any ImageDecoding
    private let animationDecoder: (any AnimationAssetDecoding)?
    private let cache: RasterCache
    private let animationCache = AnimationAssetCache(countLimit: 4)
    private let decodeQueue: OperationQueue
    private let callbackQueue: DispatchQueue

    public init(
        decoder: (any ImageDecoding)? = nil,
        animationDecoder: (any AnimationAssetDecoding)? = AnimationDecoderRouter(),
        cache: RasterCache = RasterCache(byteLimit: 256 * 1_024 * 1_024),
        decodeQueue: OperationQueue? = nil,
        callbackQueue: DispatchQueue = .main,
        nativeFormatPolicy: NativeFormatPolicy = NativeFormatPolicy(),
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) {
        self.decoder = decoder ?? ImageDecoderRouter(
            nativeFormatPolicy: nativeFormatPolicy,
            operatingSystemVersion: operatingSystemVersion
        )
        self.animationDecoder = animationDecoder
        self.cache = cache
        self.callbackQueue = callbackQueue
        if let decodeQueue {
            self.decodeQueue = decodeQueue
        } else {
            let queue = OperationQueue()
            queue.name = "app.lightview.image-decode"
            queue.qualityOfService = .userInitiated
            queue.maxConcurrentOperationCount = 2
            self.decodeQueue = queue
        }
    }

    @discardableResult
    public func load(
        _ request: DecodeRequest,
        completion: @escaping @Sendable (Result<DisplayAsset, ImageLoadError>) -> Void
    ) -> DecodeCancellation {
        let cancellation = DecodeCancellation()
        let key = RasterCacheKey(
            sourceURL: request.url,
            targetPixelSize: request.targetPixelSize,
            requiresFullResolution: request.requiresFullResolution
        )
        if let cached = cache.value(for: key) {
            callbackQueue.async {
                guard !cancellation.isCancelled else { return }
                completion(.success(.raster(cached)))
            }
            return cancellation
        }
        if let cached = animationCache.value(for: request.url) {
            callbackQueue.async {
                guard !cancellation.isCancelled else { return }
                completion(.success(.animation(cached)))
            }
            return cancellation
        }

        decodeQueue.addOperation { [decoder, animationDecoder, cache, animationCache, callbackQueue] in
            let result: Result<DisplayAsset, ImageLoadError>
            do {
                try cancellation.throwIfCancelled()
                if let animation = try animationDecoder?.decodeIfPresent(
                    url: request.url,
                    cancellation: cancellation
                ) {
                    animationCache.insert(animation, for: request.url)
                    result = .success(.animation(animation))
                } else {
                    let asset = try decoder.decode(request, cancellation: cancellation)
                    cache.insert(asset, for: key)
                    result = .success(.raster(asset))
                }
            } catch let error as ImageLoadError {
                result = .failure(error)
            } catch {
                result = .failure(.decodeFailed(error.localizedDescription))
            }
            callbackQueue.async {
                guard !cancellation.isCancelled else { return }
                completion(result)
            }
        }
        return cancellation
    }

    public func preload(_ requests: [DecodeRequest]) {
        for request in requests.prefix(4) {
            _ = load(request) { _ in }
        }
    }
}

private final class AnimationAssetCache: @unchecked Sendable {
    private let countLimit: Int
    private let lock = NSLock()
    private var values: [URL: AnimationAsset] = [:]
    private var recency: [URL] = []

    init(countLimit: Int) {
        self.countLimit = max(0, countLimit)
    }

    func value(for url: URL) -> AnimationAsset? {
        let key = url.standardizedFileURL
        return lock.withLock {
            guard let value = values[key] else { return nil }
            recency.removeAll { $0 == key }
            recency.append(key)
            return value
        }
    }

    func insert(_ asset: AnimationAsset, for url: URL) {
        guard countLimit > 0 else { return }
        let key = url.standardizedFileURL
        lock.withLock {
            values[key] = asset
            recency.removeAll { $0 == key }
            recency.append(key)
            while recency.count > countLimit {
                values.removeValue(forKey: recency.removeFirst())
            }
        }
    }
}
