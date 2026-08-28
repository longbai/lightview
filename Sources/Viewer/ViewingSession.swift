import CoreGraphics
import Foundation

public enum ViewingState: Sendable {
    case empty
    case loading(url: URL, generation: UInt64)
    case presenting(url: URL, asset: RasterAsset, generation: UInt64)
    case failed(url: URL, error: ImageLoadError, generation: UInt64)
}

@MainActor
public final class ViewingSession {
    public var onStateChange: ((ViewingState) -> Void)?
    public var catalog: FolderCatalog?
    public var navigationWraps = false
    public var neighborPreloadCount = 0
    public var targetPixelSize = CGSize(width: 1_280, height: 800)

    public private(set) var state: ViewingState = .empty
    public private(set) var generation: UInt64 = 0
    public private(set) var currentURL: URL?
    public private(set) var currentAsset: RasterAsset?

    private let loader: any ImageLoading
    private var activeCancellation: DecodeCancellation?

    public init(loader: any ImageLoading = ImageLoadPipeline()) {
        self.loader = loader
    }

    public func open(
        _ url: URL,
        targetPixelSize: CGSize? = nil,
        requiresFullResolution: Bool = false
    ) {
        activeCancellation?.cancel()
        generation &+= 1
        let normalizedURL = url.standardizedFileURL
        currentURL = normalizedURL
        currentAsset = nil
        let request = DecodeRequest(
            url: normalizedURL,
            targetPixelSize: targetPixelSize ?? self.targetPixelSize,
            requiresFullResolution: requiresFullResolution,
            generation: generation
        )
        publish(.loading(url: normalizedURL, generation: generation))
        activeCancellation = loader.load(request) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.receive(result, for: request)
            }
        }
    }

    public func navigate(_ direction: CatalogDirection) {
        guard let catalog, let currentURL,
              let entry = catalog.neighbor(
                  from: currentURL,
                  direction: direction,
                  wraps: navigationWraps
              ) else { return }
        open(entry.url)
    }

    public func clear() {
        activeCancellation?.cancel()
        activeCancellation = nil
        generation &+= 1
        currentURL = nil
        currentAsset = nil
        publish(.empty)
    }

    private func receive(
        _ result: Result<RasterAsset, ImageLoadError>,
        for request: DecodeRequest
    ) {
        guard request.generation == generation, request.url == currentURL else { return }
        activeCancellation = nil
        switch result {
        case .success(let asset):
            currentAsset = asset
            publish(.presenting(url: request.url, asset: asset, generation: generation))
            scheduleNeighborPreviews(around: request.url)
        case .failure(let error):
            currentAsset = nil
            publish(.failed(url: request.url, error: error, generation: generation))
        }
    }

    private func publish(_ state: ViewingState) {
        self.state = state
        onStateChange?(state)
    }

    private func scheduleNeighborPreviews(around url: URL) {
        guard neighborPreloadCount > 0, let catalog else { return }
        var requests: [DecodeRequest] = []
        for direction in [CatalogDirection.previous, .next] {
            var cursor = url
            for _ in 0..<min(neighborPreloadCount, 2) {
                guard let entry = catalog.neighbor(from: cursor, direction: direction, wraps: false) else {
                    break
                }
                cursor = entry.url
                requests.append(DecodeRequest(
                    url: entry.url,
                    targetPixelSize: targetPixelSize,
                    requiresFullResolution: false,
                    generation: generation
                ))
            }
        }
        loader.preload(requests)
    }
}
