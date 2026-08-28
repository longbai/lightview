import CoreGraphics
import XCTest
@testable import LightViewCore

final class GeometryPerformanceTests: XCTestCase {
    func testViewportTransformThroughput() {
        measure {
            let imageSize = CGSize(width: 12_000, height: 8_000)
            let viewportSize = CGSize(width: 1_920, height: 1_080)
            var scale: CGFloat = 0.135
            var translation = CGPoint.zero
            for index in 0..<10_000 {
                let result = ViewportGeometry.anchoredZoom(
                    from: scale,
                    to: scale * (index.isMultiple(of: 2) ? 1.01 : 1 / 1.01),
                    translation: translation,
                    anchor: CGPoint(x: 960, y: 540),
                    viewportSize: viewportSize
                )
                scale = result.scale
                translation = ViewportGeometry.clampedTranslation(
                    imageSize: imageSize,
                    viewportSize: viewportSize,
                    scale: scale,
                    rotationDegrees: index % 360,
                    proposed: CGPoint(x: result.translation.x + 1, y: result.translation.y - 1)
                ) ?? .zero
            }
            XCTAssertGreaterThan(scale, 0)
        }
    }
}
