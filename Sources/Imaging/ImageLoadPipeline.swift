import Foundation

public protocol ImageLoading: Sendable {
    @discardableResult
    func load(
        _ request: DecodeRequest,
        completion: @escaping @Sendable (Result<RasterAsset, ImageLoadError>) -> Void
    ) -> DecodeCancellation

    func preload(_ requests: [DecodeRequest])
}

public extension ImageLoading {
    func preload(_ requests: [DecodeRequest]) {}
}

public final class ImageLoadPipeline: ImageLoading, @unchecked Sendable {
    private let decoder: any ImageDecoding
    private let cache: RasterCache
    private let decodeQueue: OperationQueue
    private let callbackQueue: DispatchQueue

    public init(
        decoder: any ImageDecoding = ImageDecoderRouter(),
        cache: RasterCache = RasterCache(byteLimit: 256 * 1_024 * 1_024),
        decodeQueue: OperationQueue? = nil,
        callbackQueue: DispatchQueue = .main
    ) {
        self.decoder = decoder
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
        completion: @escaping @Sendable (Result<RasterAsset, ImageLoadError>) -> Void
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
                completion(.success(cached))
            }
            return cancellation
        }

        decodeQueue.addOperation { [decoder, cache, callbackQueue] in
            let result: Result<RasterAsset, ImageLoadError>
            do {
                let asset = try decoder.decode(request, cancellation: cancellation)
                cache.insert(asset, for: key)
                result = .success(asset)
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
