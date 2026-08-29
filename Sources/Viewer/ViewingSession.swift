import CoreGraphics
import Foundation

public enum ViewingState: Sendable {
    case empty
    case loading(url: URL, generation: UInt64)
    case presenting(url: URL, asset: DisplayAsset, generation: UInt64)
    case failed(url: URL, error: ImageLoadError, generation: UInt64)
}

public final class ViewingSession: @unchecked Sendable {
    public var onStateChange: ((ViewingState) -> Void)?
    public var catalog: FolderCatalog?
    public var navigationWraps = false
    public var neighborPreloadCount = 0
    public var targetPixelSize = CGSize(width: 1_280, height: 800)

    public private(set) var state: ViewingState = .empty
    public private(set) var generation: UInt64 = 0
    public private(set) var currentURL: URL?
    public private(set) var currentAsset: DisplayAsset?

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
        startLoad(
            url,
            targetPixelSize: targetPixelSize ?? self.targetPixelSize,
            requiresFullResolution: requiresFullResolution,
            preservingCurrentAsset: false
        )
    }

    public func refineCurrentRaster(at url: URL, targetPixelSize: CGSize) {
        let normalizedURL = url.standardizedFileURL
        guard normalizedURL == currentURL, case .raster = currentAsset else { return }
        startLoad(
            normalizedURL,
            targetPixelSize: targetPixelSize,
            requiresFullResolution: false,
            preservingCurrentAsset: true
        )
    }

    private func startLoad(
        _ url: URL,
        targetPixelSize: CGSize,
        requiresFullResolution: Bool,
        preservingCurrentAsset: Bool
    ) {
        activeCancellation?.cancel()
        generation &+= 1
        let normalizedURL = url.standardizedFileURL
        let fallbackAsset = preservingCurrentAsset ? currentAsset : nil
        currentURL = normalizedURL
        if !preservingCurrentAsset {
            currentAsset = nil
        }
        let request = DecodeRequest(
            url: normalizedURL,
            targetPixelSize: targetPixelSize,
            requiresFullResolution: requiresFullResolution,
            generation: generation
        )
        if !preservingCurrentAsset {
            publish(.loading(url: normalizedURL, generation: generation))
        }
        activeCancellation = loader.load(request) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                self?.receive(result, for: request, fallbackAsset: fallbackAsset)
            }
        }
    }

    @discardableResult
    public func navigate(_ direction: CatalogDirection) -> Bool {
        guard let catalog, let currentURL,
              let entry = catalog.neighbor(
                  from: currentURL,
                  direction: direction,
                  wraps: navigationWraps
              ) else { return false }
        open(entry.url)
        return true
    }

    public func reload(targetPixelSize: CGSize? = nil) {
        guard let currentURL else { return }
        open(currentURL, targetPixelSize: targetPixelSize)
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
        _ result: Result<DisplayAsset, ImageLoadError>,
        for request: DecodeRequest,
        fallbackAsset: DisplayAsset?
    ) {
        guard request.generation == generation, request.url == currentURL else { return }
        activeCancellation = nil
        switch result {
        case .success(let asset):
            currentAsset = asset
            publish(.presenting(url: request.url, asset: asset, generation: generation))
            scheduleNeighborPreviews(around: request.url)
        case .failure(let error):
            if let fallbackAsset {
                currentAsset = fallbackAsset
                // The existing raster never left the screen while refinement was running.
                // Update the session bookkeeping without presenting it again: publishing
                // would reset the canvas refinement guard and immediately retry the same
                // failed request forever.
                state = .presenting(url: request.url, asset: fallbackAsset, generation: generation)
            } else {
                currentAsset = nil
                publish(.failed(url: request.url, error: error, generation: generation))
            }
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
