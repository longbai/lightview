import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import LightViewCore

final class WebPDecoderTests: XCTestCase {
    func testInspectReportsDimensionsAndAlpha() throws {
        let decoder = WebPDecoder()

        XCTAssertEqual(
            try decoder.inspect(url: fixtureURL("static-lossy.webp")).rawPixelSize,
            CGSize(width: 4_000, height: 2_000)
        )
        XCTAssertEqual(
            try decoder.inspect(url: fixtureURL("static-alpha.webp")).rawPixelSize,
            CGSize(width: 32, height: 16)
        )
    }

    func testDecodeScalesAtDecoderAndPreservesAlpha() throws {
        let decoder = WebPDecoder()
        let lossy = try decoder.decode(
            request("static-lossy.webp", target: CGSize(width: 200, height: 200)),
            cancellation: DecodeCancellation()
        )
        let alpha = try decoder.decode(
            request("static-alpha.webp", target: CGSize(width: 32, height: 16)),
            cancellation: DecodeCancellation()
        )

        XCTAssertEqual(lossy.decodedPixelSize, CGSize(width: 200, height: 100))
        XCTAssertEqual(lossy.format, .webP)
        XCTAssertTrue(alpha.image.alphaInfo.hasAlpha)
        let alphaBytes = rgbaBytes(for: alpha.image)
        let alphaValues = stride(from: 3, to: alphaBytes.count, by: 4).map { alphaBytes[$0] }
        XCTAssertEqual(alphaValues.min(), 0)
        XCTAssertEqual(alphaValues.max(), 255)
    }

    func testSourceByteLimitIsCheckedBeforeDecode() {
        XCTAssertThrowsError(try WebPDecoder(maxSourceBytes: 8).inspect(url: fixtureURL("static-alpha.webp"))) { caughtError in
            guard case .sourceTooLarge(let actual, let limit) = caughtError as? ImageLoadError else {
                return XCTFail("Unexpected error: \(caughtError)")
            }
            XCTAssertGreaterThan(actual, limit)
            XCTAssertEqual(limit, 8)
        }
    }

    func testInvalidRiffIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".webp")
        try Data("RIFF0000WEBPbroken".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try WebPDecoder().inspect(url: url))
    }

    func testDecodedByteLimitIsCheckedBeforeAllocation() {
        XCTAssertThrowsError(
            try WebPDecoder(maxDecodedBytes: 64).decode(
                request("static-alpha.webp", target: CGSize(width: 32, height: 16)),
                cancellation: DecodeCancellation()
            )
        ) { error in
            guard case .decodedImageTooLarge(let required, let limit) = error as? ImageLoadError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertGreaterThan(required, limit)
            XCTAssertEqual(limit, 64)
        }
    }

    func testCancelledDecodeDoesNotAllocateOutput() {
        let cancellation = DecodeCancellation()
        cancellation.cancel()

        XCTAssertThrowsError(
            try WebPDecoder().decode(
                request("static-alpha.webp", target: CGSize(width: 32, height: 16)),
                cancellation: cancellation
            )
        ) { error in
            XCTAssertEqual(error as? ImageLoadError, .cancelled)
        }
    }

    func testAllocationFailureReturnsErrorInsteadOfTrapping() {
        let decoder = WebPDecoder(outputAllocator: { _ in nil })

        XCTAssertThrowsError(
            try decoder.decode(
                request("static-alpha.webp", target: CGSize(width: 32, height: 16)),
                cancellation: DecodeCancellation()
            )
        ) { error in
            XCTAssertEqual(error as? ImageLoadError, .allocationFailed(required: 2_048))
        }
    }

    func testCAdapterRejectsStrideSmallerThanOneRGBARow() throws {
        let data = try Data(contentsOf: fixtureURL("static-alpha.webp"))
        var output = [UInt8](repeating: 0, count: 32 * 16 * 4)
        let outputCapacity = output.count
        let status = data.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                LVWebPDecodePremultipliedRGBA(
                    source.bindMemory(to: UInt8.self).baseAddress,
                    data.count,
                    32,
                    16,
                    destination.bindMemory(to: UInt8.self).baseAddress,
                    outputCapacity,
                    1
                )
            }
        }

        XCTAssertEqual(status, Int32(LVWebPStatusInvalidArgument))
    }

    func testNativeSuccessSkipsWebPFallback() throws {
        let native = InspectSpy(result: .success(inspection(format: .webP)))
        let fallback = InspectSpy(result: .failure(.decodeFailed("Fallback should not run")))
        let router = ImageDecoderRouter(imageIO: native, svg: SVGDecoder(), webPFallback: fallback)

        _ = try router.inspect(url: fixtureURL("static-lossy.webp"))

        XCTAssertEqual(native.inspectCount, 1)
        XCTAssertEqual(fallback.inspectCount, 0)
    }

    func testNativeFailureInvokesWebPFallbackOnce() throws {
        let native = InspectSpy(result: .failure(.decodeFailed("Native unavailable")))
        let fallback = InspectSpy(result: .success(inspection(format: .webP)))
        let router = ImageDecoderRouter(imageIO: native, svg: SVGDecoder(), webPFallback: fallback)

        _ = try router.inspect(url: fixtureURL("static-lossy.webp"))

        XCTAssertEqual(native.inspectCount, 1)
        XCTAssertEqual(fallback.inspectCount, 1)
    }

    func testNativeDecodeFailureInvokesWebPFallbackOnce() throws {
        let expected = try WebPDecoder().decode(
            request("static-alpha.webp", target: CGSize(width: 16, height: 8)),
            cancellation: DecodeCancellation()
        )
        let native = DecodeSpy(result: .failure(.decodeFailed("Native unavailable")))
        let fallback = DecodeSpy(result: .success(expected))
        let router = ImageDecoderRouter(imageIO: native, svg: SVGDecoder(), webPFallback: fallback)

        let decoded = try router.decode(
            request("static-alpha.webp", target: CGSize(width: 16, height: 8)),
            cancellation: DecodeCancellation()
        )

        XCTAssertEqual(decoded.decodedPixelSize, CGSize(width: 16, height: 8))
        XCTAssertEqual(native.decodeCount, 1)
        XCTAssertEqual(fallback.decodeCount, 1)
    }

    private func request(_ name: String, target: CGSize) -> DecodeRequest {
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
            .appendingPathComponent("Fixtures/WebP/\(name)")
    }

    private func inspection(format: ImageFormat) -> ImageInspection {
        let size = CGSize(width: 10, height: 10)
        return ImageInspection(
            format: format,
            rawPixelSize: size,
            orientedPixelSize: size,
            orientation: .up,
            frameCount: 1,
            metadata: ImageMetadata(pixelSize: size)
        )
    }

    private func rgbaBytes(for image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }
}

private final class DecodeSpy: ImageDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<RasterAsset, ImageLoadError>
    private var count = 0

    init(result: Result<RasterAsset, ImageLoadError>) {
        self.result = result
    }

    var decodeCount: Int { lock.withLock { count } }

    func inspect(url: URL) throws -> ImageInspection {
        throw ImageLoadError.decodeFailed("Inspect is not used by this spy")
    }

    func decode(_ request: DecodeRequest, cancellation: DecodeCancellation) throws -> RasterAsset {
        lock.withLock { count += 1 }
        return try result.get()
    }
}

private final class InspectSpy: ImageDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<ImageInspection, ImageLoadError>
    private var count = 0

    init(result: Result<ImageInspection, ImageLoadError>) {
        self.result = result
    }

    var inspectCount: Int { lock.withLock { count } }

    func inspect(url: URL) throws -> ImageInspection {
        lock.withLock { count += 1 }
        return try result.get()
    }

    func decode(_ request: DecodeRequest, cancellation: DecodeCancellation) throws -> RasterAsset {
        throw ImageLoadError.decodeFailed("Decode is not used by this spy")
    }
}

private extension CGImageAlphaInfo {
    var hasAlpha: Bool {
        switch self {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: true
        case .none, .noneSkipFirst, .noneSkipLast: false
        @unknown default: false
        }
    }
}
