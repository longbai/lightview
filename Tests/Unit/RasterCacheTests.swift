import CoreGraphics
import ImageIO
import XCTest
@testable import LightViewCore

final class RasterCacheTests: XCTestCase {
    func testEvictsLeastRecentlyUsedAssetByDecodedByteCost() throws {
        let cache = RasterCache(byteLimit: 100)
        let firstKey = key("first")
        let secondKey = key("second")

        cache.insert(try asset(cost: 60), for: firstKey)
        cache.insert(try asset(cost: 60), for: secondKey)

        XCTAssertNil(cache.value(for: firstKey))
        XCTAssertNotNil(cache.value(for: secondKey))
        XCTAssertEqual(cache.totalByteCost, 60)
    }

    func testMemoryPressureCleanupKeepsOnlyPinnedAssets() throws {
        let cache = RasterCache(byteLimit: 100)
        let pinnedKey = key("pinned")
        let transientKey = key("transient")
        cache.insert(try asset(cost: 60), for: pinnedKey, pinned: true)
        cache.insert(try asset(cost: 20), for: transientKey)

        cache.removeAllNonessential()

        XCTAssertNotNil(cache.value(for: pinnedKey))
        XCTAssertNil(cache.value(for: transientKey))
        XCTAssertEqual(cache.totalByteCost, 60)
    }

    private func key(_ name: String) -> RasterCacheKey {
        RasterCacheKey(
            sourceURL: URL(fileURLWithPath: "/tmp/\(name).png"),
            targetPixelSize: CGSize(width: 10, height: 10),
            requiresFullResolution: false
        )
    }

    private func asset(cost: Int) throws -> RasterAsset {
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
            throw ImageLoadError.decodeFailed("Unable to make cache test image")
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
}
