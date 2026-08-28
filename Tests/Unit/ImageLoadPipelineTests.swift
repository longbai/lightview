import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import LightViewCore

final class ImageLoadPipelineTests: XCTestCase {
    func testAnimatedImageReturnsDisplayAssetWithoutEagerFrameDecode() {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let pipeline = ImageLoadPipeline(decodeQueue: queue)
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Animation/disposal.gif")
        let request = DecodeRequest(
            url: url,
            targetPixelSize: CGSize(width: 100, height: 100),
            requiresFullResolution: false,
            generation: 1
        )
        let loaded = expectation(description: "animation loaded")

        _ = pipeline.load(request) { result in
            guard case let .success(.animation(asset)) = result else {
                XCTFail("Expected animation display asset")
                return loaded.fulfill()
            }
            XCTAssertEqual(asset.frameCount, 3)
            loaded.fulfill()
        }

        wait(for: [loaded], timeout: 2)
    }

    func testMatchingSecondLoadUsesRasterCache() throws {
        let decoder = CountingDecoder(asset: try makeAsset(cost: 16))
        let cache = RasterCache(byteLimit: 1_024)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let pipeline = ImageLoadPipeline(
            decoder: decoder,
            animationDecoder: nil,
            cache: cache,
            decodeQueue: queue
        )
        let request = DecodeRequest(
            url: URL(fileURLWithPath: "/tmp/cached.png"),
            targetPixelSize: CGSize(width: 100, height: 100),
            requiresFullResolution: false,
            generation: 1
        )

        let first = expectation(description: "first decode")
        _ = pipeline.load(request) { result in
            if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
            first.fulfill()
        }
        wait(for: [first], timeout: 2)

        let second = expectation(description: "cached decode")
        _ = pipeline.load(request) { result in
            if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
            second.fulfill()
        }
        wait(for: [second], timeout: 2)

        XCTAssertEqual(decoder.decodeCount, 1)
    }

    func testMemoryPressureEvictsReusableRaster() throws {
        let decoder = CountingDecoder(asset: try makeAsset(cost: 16))
        let cache = RasterCache(byteLimit: 1_024)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let pipeline = ImageLoadPipeline(
            decoder: decoder,
            animationDecoder: nil,
            cache: cache,
            decodeQueue: queue
        )
        let request = DecodeRequest(
            url: URL(fileURLWithPath: "/tmp/memory-pressure.png"),
            targetPixelSize: CGSize(width: 100, height: 100),
            requiresFullResolution: false,
            generation: 1
        )

        let first = expectation(description: "initial decode")
        _ = pipeline.load(request) { _ in first.fulfill() }
        wait(for: [first], timeout: 2)
        XCTAssertEqual(cache.totalByteCost, 16)

        pipeline.handleMemoryPressure()
        XCTAssertEqual(cache.totalByteCost, 0)

        let second = expectation(description: "decode after pressure")
        _ = pipeline.load(request) { _ in second.fulfill() }
        wait(for: [second], timeout: 2)
        XCTAssertEqual(decoder.decodeCount, 2)
    }

    func testPreloadedAnimationIsRetainedForNextLoad() throws {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let animationDecoder = CountingAnimationDecoder(asset: try makeAnimationAsset())
        let pipeline = ImageLoadPipeline(
            animationDecoder: animationDecoder,
            decodeQueue: queue
        )
        let request = DecodeRequest(
            url: URL(fileURLWithPath: "/tmp/preloaded.gif"),
            targetPixelSize: CGSize(width: 100, height: 100),
            requiresFullResolution: false,
            generation: 1
        )

        pipeline.preload([request])
        queue.waitUntilAllOperationsAreFinished()

        let loaded = expectation(description: "cached animation loaded")
        _ = pipeline.load(request) { result in
            guard case .success(.animation) = result else {
                XCTFail("Expected cached animation")
                return loaded.fulfill()
            }
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 2)
        XCTAssertEqual(animationDecoder.decodeCount, 1)
    }
}

private final class CountingDecoder: ImageDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private let asset: RasterAsset
    private var count = 0

    init(asset: RasterAsset) {
        self.asset = asset
    }

    var decodeCount: Int {
        lock.withLock { count }
    }

    func inspect(url: URL) throws -> ImageInspection {
        throw ImageLoadError.decodeFailed("Inspection is not used by this test")
    }

    func decode(_ request: DecodeRequest, cancellation: DecodeCancellation) throws -> RasterAsset {
        try cancellation.throwIfCancelled()
        lock.withLock { count += 1 }
        return asset
    }
}

private final class CountingAnimationDecoder: AnimationAssetDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private let asset: AnimationAsset
    private var count = 0

    init(asset: AnimationAsset) { self.asset = asset }
    var decodeCount: Int { lock.withLock { count } }

    func decodeIfPresent(url: URL, cancellation: DecodeCancellation) throws -> AnimationAsset? {
        try cancellation.throwIfCancelled()
        lock.withLock { count += 1 }
        return asset
    }
}

private final class PipelineAnimationFrameProvider: AnimationFrameProvider, @unchecked Sendable {
    let descriptor = AnimationDescriptor(
        canvasPixelSize: CGSize(width: 1, height: 1),
        frameDurations: [0.1, 0.1],
        loopCount: nil
    )
    private let image: CGImage

    init(image: CGImage) { self.image = image }

    func frame(at index: Int) throws -> AnimationFrame {
        AnimationFrame(index: index, image: image, decodedByteCost: 4)
    }
}

private func makeAsset(cost: Int) throws -> RasterAsset {
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
        throw ImageLoadError.decodeFailed("Unable to make pipeline test image")
    }
    let size = CGSize(width: 1, height: 1)
    return RasterAsset(
        image: image,
        originalPixelSize: size,
        decodedPixelSize: size,
        orientation: .up,
        metadata: ImageMetadata(pixelSize: size),
        decodedByteCost: cost
    )
}

private func makeAnimationAsset() throws -> AnimationAsset {
    let raster = try makeAsset(cost: 4)
    return AnimationAsset(provider: PipelineAnimationFrameProvider(image: raster.image), format: .gif)
}
