import CoreGraphics
import ImageIO
import XCTest
@testable import LightViewCore

final class ImageIODecoderTests: XCTestCase {
    func testEstimatedDecodeCostUsesRequestedThumbnailSize() throws {
        let cost = try ImageIODecoder.estimatedDecodedByteCost(
            rawPixelSize: CGSize(width: 40_000, height: 20_000),
            maximumPixelSize: 2_000
        )
        XCTAssertEqual(cost, 2_000 * 1_000 * 4)
    }

    func testEstimatedFullResolutionCostCanBeRejectedBeforeAllocation() throws {
        let limits = DecodeSafetyLimits(maxDecodedBytes: 512 * 1_024 * 1_024)
        let cost = try ImageIODecoder.estimatedDecodedByteCost(
            rawPixelSize: CGSize(width: 40_000, height: 20_000),
            maximumPixelSize: 40_000
        )
        XCTAssertThrowsError(try limits.validateDecodedByteCount(cost))
    }

    func testOrientationIsAppliedAndPreviewIsDownsampled() throws {
        let url = fixtureURL("oriented-6.jpg")
        let decoder = ImageIODecoder()
        let inspection = try decoder.inspect(url: url)

        XCTAssertEqual(inspection.orientation, .right)
        XCTAssertEqual(inspection.rawPixelSize, CGSize(width: 4_000, height: 2_000))

        let asset = try decoder.decode(
            DecodeRequest(
                url: url,
                targetPixelSize: CGSize(width: 800, height: 800),
                requiresFullResolution: false,
                generation: 1
            ),
            cancellation: DecodeCancellation()
        )

        XCTAssertEqual(asset.originalPixelSize, CGSize(width: 2_000, height: 4_000))
        XCTAssertEqual(asset.decodedPixelSize, CGSize(width: 400, height: 800))
        XCTAssertLessThanOrEqual(max(asset.image.width, asset.image.height), 800)
    }

    func testPngAlphaRemainsPresent() throws {
        let asset = try ImageIODecoder().decode(
            DecodeRequest(
                url: fixtureURL("alpha.png"),
                targetPixelSize: CGSize(width: 100, height: 100),
                requiresFullResolution: false,
                generation: 2
            ),
            cancellation: DecodeCancellation()
        )

        XCTAssertTrue(asset.image.alphaInfo.hasAlpha)
    }

    func testOverflowByteCostFailsBeforeAllocation() {
        XCTAssertThrowsError(
            try ImageIODecoder.decodedByteCost(width: Int.max, height: 2, bytesPerPixel: 4)
        )
    }

    func testCancelledDecodeStopsBeforeImageCreation() {
        let cancellation = DecodeCancellation()
        cancellation.cancel()
        XCTAssertThrowsError(
            try ImageIODecoder().decode(
                DecodeRequest(
                    url: fixtureURL("alpha.png"),
                    targetPixelSize: CGSize(width: 100, height: 100),
                    requiresFullResolution: false,
                    generation: 3
                ),
                cancellation: cancellation
            )
        ) { error in
            XCTAssertEqual(error as? ImageLoadError, .cancelled)
        }
    }

    func testExtractsStructuredEXIFFromImageIOProperties() throws {
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Apple",
                kCGImagePropertyTIFFModel: "iPhone 15 Pro",
                kCGImagePropertyTIFFSoftware: "Camera",
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:08:29 10:11:12",
                kCGImagePropertyExifLensModel: "iPhone 15 Pro back camera",
                kCGImagePropertyExifFocalLength: 6.8,
                kCGImagePropertyExifFocalLenIn35mmFilm: 24,
                kCGImagePropertyExifFNumber: 1.8,
                kCGImagePropertyExifExposureTime: 0.008,
                kCGImagePropertyExifISOSpeedRatings: [80],
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 31.2304,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 121.4737,
                kCGImagePropertyGPSLongitudeRef: "E",
            ],
        ]

        let exif = try XCTUnwrap(ImageIODecoder.exifMetadata(from: properties))
        XCTAssertEqual(exif.cameraMake, "Apple")
        XCTAssertEqual(exif.cameraModel, "iPhone 15 Pro")
        XCTAssertEqual(exif.lensModel, "iPhone 15 Pro back camera")
        XCTAssertEqual(exif.iso, 80)
        XCTAssertEqual(try XCTUnwrap(exif.latitude), 31.2304, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(exif.longitude), 121.4737, accuracy: 0.000_001)
    }

    func testInspectsRealHEICFixtureWithEXIF() throws {
        let inspection = try ImageIODecoder().inspect(url: fixtureURL("exif.heic"))

        XCTAssertEqual(inspection.format, .heif)
        XCTAssertEqual(inspection.metadata.pixelSize, CGSize(width: 64, height: 48))
        let exif = try XCTUnwrap(inspection.metadata.exif)
        XCTAssertEqual(exif.cameraMake, "LightView")
        XCTAssertEqual(exif.cameraModel, "Fixture Camera")
        XCTAssertEqual(exif.lensModel, "Fixture 24mm")
        XCTAssertEqual(exif.iso, 100)
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Static/\(name)")
    }
}

private extension CGImageAlphaInfo {
    var hasAlpha: Bool {
        switch self {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            true
        case .none, .noneSkipFirst, .noneSkipLast:
            false
        @unknown default:
            false
        }
    }
}
