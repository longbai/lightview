import CoreGraphics
import ImageIO
import XCTest
@testable import LightViewCore

final class ImageIODecoderTests: XCTestCase {
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
