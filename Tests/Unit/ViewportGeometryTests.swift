import CoreGraphics
import XCTest
@testable import LightViewCore

final class ViewportGeometryTests: XCTestCase {
    func testFitFillRotationAndActualSize() throws {
        let imageSize = CGSize(width: 4_000, height: 2_000)
        let viewportSize = CGSize(width: 1_000, height: 1_000)

        XCTAssertEqual(try XCTUnwrap(ViewportGeometry.fitScale(imageSize: imageSize, viewportSize: viewportSize)), 0.25)
        XCTAssertEqual(try XCTUnwrap(ViewportGeometry.fillScale(imageSize: imageSize, viewportSize: viewportSize)), 0.5)
        XCTAssertEqual(
            try XCTUnwrap(ViewportGeometry.displayedSize(imageSize: imageSize, scale: 0.25, rotationDegrees: 90)),
            CGSize(width: 500, height: 1_000)
        )
        XCTAssertEqual(ViewportGeometry.actualSizeScale(backingScale: 2), 0.5)
    }

    func testAnchoredZoomPreservesImagePoint() {
        let viewportSize = CGSize(width: 1_000, height: 1_000)
        let anchor = CGPoint(x: 250, y: 300)
        let oldScale: CGFloat = 0.25
        let oldTranslation = CGPoint.zero

        let result = ViewportGeometry.anchoredZoom(
            from: oldScale,
            to: 0.5,
            translation: oldTranslation,
            anchor: anchor,
            viewportSize: viewportSize
        )

        XCTAssertEqual(result.scale, 0.5)
        XCTAssertEqual(result.translation.x, 250, accuracy: 0.000_001)
        XCTAssertEqual(result.translation.y, 200, accuracy: 0.000_001)
        XCTAssertEqual(
            imagePoint(at: anchor, scale: oldScale, translation: oldTranslation, viewportSize: viewportSize),
            imagePoint(at: anchor, scale: result.scale, translation: result.translation, viewportSize: viewportSize)
        )
    }

    func testTranslationCentersSmallAxesAndClampsLargeAxes() throws {
        let viewport = CGSize(width: 1_000, height: 1_000)
        XCTAssertEqual(
            try XCTUnwrap(ViewportGeometry.clampedTranslation(
                imageSize: CGSize(width: 2_000, height: 1_000),
                viewportSize: viewport,
                scale: 0.25,
                rotationDegrees: 0,
                proposed: CGPoint(x: 90, y: -40)
            )),
            .zero
        )
        XCTAssertEqual(
            try XCTUnwrap(ViewportGeometry.clampedTranslation(
                imageSize: CGSize(width: 2_000, height: 1_000),
                viewportSize: viewport,
                scale: 1,
                rotationDegrees: 0,
                proposed: CGPoint(x: 900, y: -200)
            )),
            CGPoint(x: 500, y: 0)
        )
    }

    func testRejectsInvalidSizesAndClampsMagnification() {
        XCTAssertNil(ViewportGeometry.fitScale(imageSize: .zero, viewportSize: CGSize(width: 100, height: 100)))
        XCTAssertNil(ViewportGeometry.displayedSize(
            imageSize: CGSize(width: CGFloat.infinity, height: 100),
            scale: 1,
            rotationDegrees: 0
        ))
        XCTAssertEqual(ViewportGeometry.clampedMagnification(0), 0.01)
        XCTAssertEqual(ViewportGeometry.clampedMagnification(1_000), 128)
    }

    private func imagePoint(
        at viewPoint: CGPoint,
        scale: CGFloat,
        translation: CGPoint,
        viewportSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: (viewPoint.x - viewportSize.width / 2 - translation.x) / scale,
            y: (viewPoint.y - viewportSize.height / 2 - translation.y) / scale
        )
    }
}
