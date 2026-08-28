import CoreGraphics
import XCTest
@testable import LightViewCore

final class AllocationLimitTests: XCTestCase {
    func testImageIODecoderRejectsDecodedByteBudgetBeforePublishingAsset() {
        let limits = DecodeSafetyLimits(maxDecodedBytes: 16)
        XCTAssertThrowsError(
            try ImageIODecoder(limits: limits).decode(
                request(path: "Static/alpha.png", target: CGSize(width: 32, height: 16)),
                cancellation: DecodeCancellation()
            )
        ) { error in
            guard case .decodedImageTooLarge(let required, let limit) = error as? ImageLoadError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertGreaterThan(required, limit)
            XCTAssertEqual(limit, 16)
        }
    }

    func testSVGDecoderRejectsRenderTargetBeforeContextAllocation() {
        XCTAssertThrowsError(
            try SVGDecoder(maxDecodedBytes: 64).decode(
                request(path: "SVG/basic.svg", target: CGSize(width: 100, height: 50)),
                cancellation: DecodeCancellation()
            )
        ) { error in
            guard case .decodedImageTooLarge(let required, let limit) = error as? ImageLoadError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(required, 20_000)
            XCTAssertEqual(limit, 64)
        }
    }

    private func request(path: String, target: CGSize) -> DecodeRequest {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(path)
        return DecodeRequest(url: fixture, targetPixelSize: target, requiresFullResolution: false, generation: 1)
    }
}
