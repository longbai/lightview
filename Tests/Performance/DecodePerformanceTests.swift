import CoreGraphics
import XCTest
@testable import LightViewCore

final class DecodePerformanceTests: XCTestCase {
    func testFourThousandPixelJPEGPreviewDecode() {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Static/oriented-6.jpg")
        let request = DecodeRequest(
            url: url,
            targetPixelSize: CGSize(width: 1_920, height: 1_080),
            requiresFullResolution: false,
            generation: 1
        )
        measure {
            do {
                _ = try ImageIODecoder().decode(request, cancellation: DecodeCancellation())
            } catch {
                XCTFail("Decode failed: \(error)")
            }
        }
    }
}
