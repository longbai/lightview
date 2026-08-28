import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import LightViewCore

final class NativeFormatPolicyTests: XCTestCase {
    func testAVIFRequiresMacOS13() {
        let policy = NativeFormatPolicy()

        XCTAssertFalse(policy.canAttemptAVIF(on: version(10, 15)))
        XCTAssertFalse(policy.canAttemptAVIF(on: version(11, 0)))
        XCTAssertFalse(policy.canAttemptAVIF(on: version(12, 6)))
        XCTAssertTrue(policy.canAttemptAVIF(on: version(13, 0)))
        XCTAssertTrue(policy.canAttemptAVIF(on: version(26, 0)))
    }

    func testOldSystemRejectsAVIFBeforeCallingImageIO() throws {
        let native = NativeAVIFSpy(result: .failure(.decodeFailed("must not run")))
        let fallback = NativeAVIFSpy(result: .failure(.decodeFailed("must not run")))
        let router = ImageDecoderRouter(
            imageIO: native,
            svg: fallback,
            webPFallback: fallback,
            operatingSystemVersion: version(12, 6)
        )
        let url = try makeAVIFFile()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try router.inspect(url: url)) { error in
            XCTAssertEqual(
                error as? ImageLoadError,
                .unsupportedSystem(format: .avif, minimumMajorVersion: 13)
            )
        }
        XCTAssertEqual(native.inspectCount, 0)
        XCTAssertEqual(fallback.inspectCount, 0)
    }

    func testEveryOldSystemRejectsAVIFDecodeBeforeCallingAnyDecoder() throws {
        let url = try makeAVIFFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let request = DecodeRequest(
            url: url,
            targetPixelSize: CGSize(width: 100, height: 100),
            requiresFullResolution: false,
            generation: 1
        )

        for operatingSystemVersion in [version(10, 15), version(11, 0), version(12, 6)] {
            let native = NativeAVIFSpy(result: .failure(.decodeFailed("must not run")))
            let fallback = NativeAVIFSpy(result: .failure(.decodeFailed("must not run")))
            let router = ImageDecoderRouter(
                imageIO: native,
                svg: fallback,
                webPFallback: fallback,
                operatingSystemVersion: operatingSystemVersion
            )

            XCTAssertThrowsError(try router.decode(request, cancellation: DecodeCancellation())) { error in
                XCTAssertEqual(
                    error as? ImageLoadError,
                    .unsupportedSystem(format: .avif, minimumMajorVersion: 13)
                )
            }
            XCTAssertEqual(native.decodeCount, 0)
            XCTAssertEqual(fallback.decodeCount, 0)
        }
    }

    func testMacOS13AttemptsOnlyNativeAVIFDecoder() throws {
        let native = NativeAVIFSpy(result: .failure(.corrupt(URL(fileURLWithPath: "/native"))))
        let fallback = NativeAVIFSpy(result: .failure(.decodeFailed("must not run")))
        let router = ImageDecoderRouter(
            imageIO: native,
            svg: fallback,
            webPFallback: fallback,
            operatingSystemVersion: version(13, 0)
        )
        let url = try makeAVIFFile()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try router.inspect(url: url))
        XCTAssertEqual(native.inspectCount, 1)
        XCTAssertEqual(fallback.inspectCount, 0)
    }

    func testNativeAVIFDecodeFailureNeverFallsBackToWebP() throws {
        let native = NativeAVIFSpy(result: .failure(.decodeFailed("damaged AVIF")))
        let fallback = NativeAVIFSpy(result: .failure(.decodeFailed("must not run")))
        let router = ImageDecoderRouter(
            imageIO: native,
            svg: fallback,
            webPFallback: fallback,
            operatingSystemVersion: version(13, 0)
        )
        let url = try makeAVIFFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let request = DecodeRequest(
            url: url,
            targetPixelSize: CGSize(width: 100, height: 100),
            requiresFullResolution: false,
            generation: 1
        )

        XCTAssertThrowsError(try router.decode(request, cancellation: DecodeCancellation())) { error in
            XCTAssertEqual(error as? ImageLoadError, .decodeFailed("damaged AVIF"))
        }
        XCTAssertEqual(native.decodeCount, 1)
        XCTAssertEqual(fallback.decodeCount, 0)
    }

    func testCurrentSystemRoundTripsAVIFThroughNativeImageIO() throws {
        guard #available(macOS 13.0, *) else {
            throw XCTSkip("Native AVIF requires macOS 13 or later")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("avif")
        defer { try? FileManager.default.removeItem(at: url) }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.avif" as CFString,
            1,
            nil
        ) else {
            throw XCTSkip("Current ImageIO exposes AVIF decoding but not encoding")
        }
        CGImageDestinationAddImage(destination, try makeTestImage(), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let asset = try ImageDecoderRouter().decode(
            DecodeRequest(
                url: url,
                targetPixelSize: CGSize(width: 2, height: 1),
                requiresFullResolution: false,
                generation: 1
            ),
            cancellation: DecodeCancellation()
        )

        XCTAssertEqual(asset.format, .avif)
        XCTAssertEqual(asset.originalPixelSize, CGSize(width: 2, height: 1))
    }

    private func version(_ major: Int, _ minor: Int) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
    }

    private func makeAVIFFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("avif")
        var data = Data([0, 0, 0, 24])
        data.append(Data("ftypavif".utf8))
        data.append(Data(repeating: 0, count: 12))
        try data.write(to: url)
        return url
    }

    private func makeTestImage() throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: 2,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw ImageLoadError.decodeFailed("Could not create AVIF test image")
        }
        return image
    }
}

private final class NativeAVIFSpy: ImageDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<ImageInspection, ImageLoadError>
    private var inspections = 0
    private var decodes = 0

    init(result: Result<ImageInspection, ImageLoadError>) { self.result = result }

    var inspectCount: Int { lock.withLock { inspections } }
    var decodeCount: Int { lock.withLock { decodes } }

    func inspect(url: URL) throws -> ImageInspection {
        lock.withLock { inspections += 1 }
        return try result.get()
    }

    func decode(_ request: DecodeRequest, cancellation: DecodeCancellation) throws -> RasterAsset {
        lock.withLock { decodes += 1 }
        switch result {
        case .failure(let error): throw error
        case .success: throw ImageLoadError.decodeFailed("Unexpected decode success")
        }
    }
}
