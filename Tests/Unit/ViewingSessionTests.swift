import CoreGraphics
import Foundation
import XCTest
@testable import LightViewCore

final class ViewingSessionTests: XCTestCase {
    @MainActor
    func testLateResultCannotReplaceNewerImage() async throws {
        let loader = ControlledImageLoader()
        let session = ViewingSession(loader: loader)
        let firstURL = URL(fileURLWithPath: "/tmp/first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/second.png")

        session.open(firstURL)
        let firstGeneration = session.generation
        session.open(secondURL)
        let secondGeneration = session.generation

        loader.complete(generation: secondGeneration, with: .success(try makeSessionAsset(cost: 8)))
        await Task.yield()
        XCTAssertEqual(session.currentURL, secondURL)
        XCTAssertNotNil(session.currentAsset)

        loader.complete(generation: firstGeneration, with: .success(try makeSessionAsset(cost: 8)))
        await Task.yield()
        XCTAssertEqual(session.currentURL, secondURL)
        XCTAssertEqual(session.generation, secondGeneration)
    }

    @MainActor
    func testNavigationWrapsOnlyWhenEnabled() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightViewSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("1.png")
        let secondURL = directory.appendingPathComponent("2.png")
        try Data().write(to: firstURL)
        try Data().write(to: secondURL)

        let loader = ControlledImageLoader()
        let session = ViewingSession(loader: loader)
        session.catalog = try FolderCatalog(directoryURL: directory)
        session.open(secondURL)
        let requestCountAtEnd = loader.requestCount

        session.navigationWraps = false
        session.navigate(.next)
        XCTAssertEqual(loader.requestCount, requestCountAtEnd)

        session.navigationWraps = true
        session.navigate(.next)
        XCTAssertEqual(loader.lastRequest?.url, firstURL)
    }

    @MainActor
    func testReloadReopensCurrentURLWithoutOwningViewportState() {
        let loader = ControlledImageLoader()
        let session = ViewingSession(loader: loader)
        let url = URL(fileURLWithPath: "/tmp/reload.png")
        var viewport = ViewportState(mode: .fill, magnification: 2, translation: CGPoint(x: 4, y: 8))

        session.open(url)
        let firstGeneration = session.generation
        session.reload()

        XCTAssertEqual(session.currentURL, url)
        XCTAssertEqual(session.generation, firstGeneration + 1)
        XCTAssertEqual(loader.lastRequest?.url, url)
        XCTAssertEqual(viewport.mode, .fill)
        XCTAssertEqual(viewport.translation, CGPoint(x: 4, y: 8))
        viewport.rotationDegrees = 90
        XCTAssertEqual(viewport.rotationDegrees, 90)
    }

    @MainActor
    func testResolutionRefinementKeepsCurrentImageVisibleAndUsesRequestedSize() async throws {
        let loader = ControlledImageLoader()
        let session = ViewingSession(loader: loader)
        let url = URL(fileURLWithPath: "/tmp/large.png")
        session.open(url, targetPixelSize: CGSize(width: 1_280, height: 800))
        loader.complete(generation: session.generation, with: .success(try makeSessionAsset(cost: 8)))
        await Task.yield()

        var publishedLoading = false
        session.onStateChange = { state in
            if case .loading = state { publishedLoading = true }
        }
        session.refineCurrentRaster(at: url, targetPixelSize: CGSize(width: 2_560, height: 1_600))

        XCTAssertFalse(publishedLoading)
        XCTAssertNotNil(session.currentAsset)
        XCTAssertEqual(loader.lastRequest?.targetPixelSize, CGSize(width: 2_560, height: 1_600))
        XCTAssertEqual(loader.lastRequest?.requiresFullResolution, false)
    }

    @MainActor
    func testFailedResolutionRefinementFallsBackToCurrentImage() async throws {
        let loader = ControlledImageLoader()
        let session = ViewingSession(loader: loader)
        let url = URL(fileURLWithPath: "/tmp/large.png")
        session.open(url)
        loader.complete(generation: session.generation, with: .success(try makeSessionAsset(cost: 8)))
        await Task.yield()

        var presentationCount = 0
        session.onStateChange = { state in
            if case .presenting = state { presentationCount += 1 }
        }
        session.refineCurrentRaster(at: url, targetPixelSize: CGSize(width: 4_000, height: 3_000))
        loader.complete(
            generation: session.generation,
            with: .failure(.decodedImageTooLarge(required: 1_000, limit: 500))
        )
        await Task.yield()

        XCTAssertEqual(presentationCount, 0)
        XCTAssertNotNil(session.currentAsset)
        if case .presenting = session.state {
            // Expected: the lower-resolution image remains usable.
        } else {
            XCTFail("Expected the prior image to remain presented")
        }
    }
}

private final class ControlledImageLoader: ImageLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [DecodeRequest] = []
    private var completions: [UInt64: @Sendable (Result<DisplayAsset, ImageLoadError>) -> Void] = [:]

    var requestCount: Int { lock.withLock { requests.count } }
    var lastRequest: DecodeRequest? { lock.withLock { requests.last } }

    func load(
        _ request: DecodeRequest,
        completion: @escaping @Sendable (Result<DisplayAsset, ImageLoadError>) -> Void
    ) -> DecodeCancellation {
        lock.withLock {
            requests.append(request)
            completions[request.generation] = completion
        }
        return DecodeCancellation()
    }

    func complete(generation: UInt64, with result: Result<DisplayAsset, ImageLoadError>) {
        let completion = lock.withLock { completions.removeValue(forKey: generation) }
        completion?(result)
    }
}

private func makeSessionAsset(cost: Int) throws -> DisplayAsset {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let image = context.makeImage() else {
        throw ImageLoadError.decodeFailed("Unable to make session test image")
    }
    let size = CGSize(width: 1, height: 1)
    return .raster(RasterAsset(
        image: image,
        originalPixelSize: size,
        decodedPixelSize: size,
        orientation: .up,
        metadata: ImageMetadata(pixelSize: size),
        decodedByteCost: cost
    ))
}
