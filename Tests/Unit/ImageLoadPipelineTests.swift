import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import LightViewCore

final class ImageLoadPipelineTests: XCTestCase {
    func testMatchingSecondLoadUsesRasterCache() throws {
        let decoder = CountingDecoder(asset: try makeAsset(cost: 16))
        let cache = RasterCache(byteLimit: 1_024)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let pipeline = ImageLoadPipeline(decoder: decoder, cache: cache, decodeQueue: queue)
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
