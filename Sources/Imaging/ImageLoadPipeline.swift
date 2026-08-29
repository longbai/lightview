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
    private let preloadQueue: OperationQueue
    private let callbackQueue: DispatchQueue
    private let preloadLock = NSLock()
    private var preloadTasks: [(cancellation: DecodeCancellation, operation: Operation)] = []

    public init(
        decoder: (any ImageDecoding)? = nil,
        animationDecoder: (any AnimationAssetDecoding)? = AnimationDecoderRouter(),
        cache: RasterCache = RasterCache(byteLimit: 256 * 1_024 * 1_024),
        decodeQueue: OperationQueue? = nil,
        preloadQueue: OperationQueue? = nil,
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
        if let preloadQueue {
            self.preloadQueue = preloadQueue
        } else {
            let queue = OperationQueue()
            queue.name = "app.lightview.image-preload"
            queue.qualityOfService = .utility
            queue.maxConcurrentOperationCount = 1
            self.preloadQueue = queue
        }
    }

    @discardableResult
    public func load(
        _ request: DecodeRequest,
        completion: @escaping @Sendable (Result<DisplayAsset, ImageLoadError>) -> Void
    ) -> DecodeCancellation {
        cancelPreloads()
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

        let operation = BlockOperation { [decoder, animationDecoder, cache, animationCache, callbackQueue] in
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
        operation.queuePriority = .veryHigh
        decodeQueue.addOperation(operation)
        return cancellation
    }

    public func preload(_ requests: [DecodeRequest]) {
        cancelPreloads()
        var seen: Set<RasterCacheKey> = []
        var tasks: [(cancellation: DecodeCancellation, operation: Operation)] = []
        for request in requests.prefix(4) {
            let key = RasterCacheKey(
                sourceURL: request.url,
                targetPixelSize: request.targetPixelSize,
                requiresFullResolution: request.requiresFullResolution
            )
            guard seen.insert(key).inserted,
                  cache.value(for: key) == nil,
                  animationCache.value(for: request.url) == nil else { continue }
            let cancellation = DecodeCancellation()
            let operation = BlockOperation { [decoder, animationDecoder, cache, animationCache] in
                do {
                    try cancellation.throwIfCancelled()
                    if let animation = try animationDecoder?.decodeIfPresent(
                        url: request.url,
                        cancellation: cancellation
                    ) {
                        try cancellation.throwIfCancelled()
                        animationCache.insert(animation, for: request.url)
                    } else {
                        let asset = try decoder.decode(request, cancellation: cancellation)
                        try cancellation.throwIfCancelled()
                        cache.insert(asset, for: key)
                    }
                } catch {
                    // Preloading is opportunistic. Foreground loads report their own failures.
                }
            }
            operation.queuePriority = .veryLow
            tasks.append((cancellation, operation))
        }
        preloadLock.withLock {
            preloadTasks = tasks
        }
        for task in tasks {
            preloadQueue.addOperation(task.operation)
        }
    }

    public func handleMemoryPressure() {
        cancelPreloads()
        cache.removeAllNonessential()
        animationCache.removeAll()
    }

    private func cancelPreloads() {
        let tasks = preloadLock.withLock { () -> [(DecodeCancellation, Operation)] in
            let tasks = preloadTasks
            preloadTasks.removeAll(keepingCapacity: false)
            return tasks
        }
        for task in tasks {
            task.0.cancel()
            task.1.cancel()
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

    func removeAll() {
        lock.withLock {
            values.removeAll(keepingCapacity: false)
            recency.removeAll(keepingCapacity: false)
        }
    }
}
