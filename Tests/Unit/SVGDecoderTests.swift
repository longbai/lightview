import CoreGraphics
import XCTest
@testable import LightViewCore

final class SVGDecoderTests: XCTestCase {
    func testInspectReportsIntrinsicViewBoxAndDecodeRendersPixels() throws {
        let decoder = SVGDecoder()
        let inspection = try decoder.inspect(url: fixtureURL("basic.svg"))

        XCTAssertEqual(inspection.format, .svg)
        XCTAssertEqual(inspection.rawPixelSize, CGSize(width: 100, height: 50))

        let asset = try decoder.decode(
            request(for: "basic.svg", target: CGSize(width: 64, height: 64)),
            cancellation: DecodeCancellation()
        )

        XCTAssertEqual(asset.originalPixelSize, CGSize(width: 100, height: 50))
        XCTAssertEqual(asset.decodedPixelSize, CGSize(width: 64, height: 32))
        XCTAssertGreaterThan(nontransparentPixelCount(in: asset.image), 0)
    }

    func testTransformMovesRenderedGeometry() throws {
        let image = try SVGDecoder().decode(
            request(for: "basic.svg", target: CGSize(width: 100, height: 50)),
            cancellation: DecodeCancellation()
        ).image

        XCTAssertEqual(alpha(in: image, x: 10, y: 10), 0)
        XCTAssertGreaterThan(alpha(in: image, x: 25, y: 15), 0)
    }

    func testExternalImageReferenceIsRejectedBeforeParsing() {
        let url = fixtureURL("external-resource.svg")

        XCTAssertThrowsError(try SVGDecoder().inspect(url: url)) { error in
            XCTAssertEqual(error as? ImageLoadError, .unsafeExternalResource(url))
        }
    }

    func testSourceByteCeilingRejectsInputBeforeParsing() {
        let url = fixtureURL("basic.svg")

        XCTAssertThrowsError(try SVGDecoder(maxSourceBytes: 32).inspect(url: url)) { error in
            guard case .sourceTooLarge(let actual, let limit) = error as? ImageLoadError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertGreaterThan(actual, limit)
            XCTAssertEqual(limit, 32)
        }
    }

    func testImageDecoderRouterUsesSVGAdapterForSVGSignature() throws {
        let router = ImageDecoderRouter(imageIO: RejectingImageDecoder(), svg: SVGDecoder())

        XCTAssertEqual(try router.inspect(url: fixtureURL("basic.svg")).format, .svg)
    }

    func testLinearGradientPreservesDistinctEndpointColors() throws {
        let image = try SVGDecoder().decode(
            request(for: "gradient.svg", target: CGSize(width: 100, height: 50)),
            cancellation: DecodeCancellation()
        ).image

        let left = rgba(in: image, x: 5, y: 25)
        let right = rgba(in: image, x: 94, y: 25)
        XCTAssertGreaterThan(left.red, left.blue)
        XCTAssertGreaterThan(right.blue, right.red)
        XCTAssertGreaterThan(left.alpha, 0)
        XCTAssertGreaterThan(right.alpha, 0)
    }

    func testNonFiniteTargetSizeIsRejectedWithoutAllocation() {
        XCTAssertThrowsError(
            try SVGDecoder().decode(
                request(for: "basic.svg", target: CGSize(width: CGFloat.infinity, height: 100)),
                cancellation: DecodeCancellation()
            )
        )
    }

    func testMalformedSourceFailsWithoutProducingAnImage() {
        let url = fixtureURL("malformed.svg")

        XCTAssertThrowsError(try SVGDecoder().inspect(url: url)) { error in
            XCTAssertEqual(error as? ImageLoadError, .corrupt(url))
        }
    }

    private func request(for name: String, target: CGSize) -> DecodeRequest {
        DecodeRequest(
            url: fixtureURL(name),
            targetPixelSize: target,
            requiresFullResolution: false,
            generation: 1
        )
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SVG/\(name)")
    }

    private func nontransparentPixelCount(in image: CGImage) -> Int {
        rgbaBytes(for: image).enumerated().reduce(into: 0) { count, entry in
            if entry.offset % 4 == 3, entry.element > 0 { count += 1 }
        }
    }

    private func alpha(in image: CGImage, x: Int, y: Int) -> UInt8 {
        rgbaBytes(for: image)[(y * image.width + x) * 4 + 3]
    }

    private func rgba(in image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let bytes = rgbaBytes(for: image)
        let offset = (y * image.width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }

    private func rgbaBytes(for image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }
}

private struct RejectingImageDecoder: ImageDecoding {
    func inspect(url: URL) throws -> ImageInspection {
        throw ImageLoadError.decodeFailed("Unexpected ImageIO route")
    }

    func decode(_ request: DecodeRequest, cancellation: DecodeCancellation) throws -> RasterAsset {
        throw ImageLoadError.decodeFailed("Unexpected ImageIO route")
    }
}
