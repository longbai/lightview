import CoreGraphics
import XCTest
@testable import LightViewCore

final class AnimationDecoderTests: XCTestCase {
    func testImageIOGIFReadsTimingLoopingAndFramesLazily() throws {
        let counter = DecodeCounter()
        let decoder = ImageIOAnimationDecoder(
            maxDecodedBytes: 1_024,
            frameDecodeObserver: { counter.indices.append($0) }
        )

        let displayAsset = try decoder.decode(url: fixtureURL("disposal.gif"))
        guard case let .animation(asset) = displayAsset else {
            return XCTFail("Expected an animated GIF asset")
        }
        XCTAssertEqual(asset.frameCount, 3)
        XCTAssertEqual(asset.loopCount, 2)
        XCTAssertDurationsEqual(asset.frameDurations, [0.10, 0.20, 0.30])
        XCTAssertTrue(counter.indices.isEmpty)

        let frame = try asset.provider.frame(at: 1)
        XCTAssertEqual(counter.indices, [1])
        XCTAssertEqual(pixel(in: frame.image, x: 0), red)
        XCTAssertEqual(pixel(in: frame.image, x: 2), blue)

        let disposed = try asset.provider.frame(at: 2)
        XCTAssertEqual(counter.indices, [1, 2])
        XCTAssertEqual(pixel(in: disposed.image, x: 0), green)
        XCTAssertEqual(pixel(in: disposed.image, x: 2), transparent)
    }

    func testImageIOAPNGMapsZeroLoopCountToInfinitePlayback() throws {
        let decoder = ImageIOAnimationDecoder(maxDecodedBytes: 1_024)

        let displayAsset = try decoder.decode(url: fixtureURL("sample.apng"))
        guard case let .animation(asset) = displayAsset else {
            return XCTFail("Expected an animated PNG asset")
        }

        XCTAssertEqual(asset.frameCount, 3)
        XCTAssertNil(asset.loopCount)
        XCTAssertDurationsEqual(asset.frameDurations, [0.10, 0.20, 0.30])
        XCTAssertEqual(pixel(in: try asset.provider.frame(at: 2).image, x: 0), blue)
    }

    func testAnimatedWebPReadsMetadataAndCompositesBlendAndDisposalLazily() throws {
        let counter = DecodeCounter()
        let decoder = WebPAnimationDecoder(
            maxDecodedBytes: 1_024,
            frameDecodeObserver: { counter.indices.append($0) }
        )

        let displayAsset = try decoder.decode(url: fixtureURL("blend.webp"))
        guard case let .animation(asset) = displayAsset else {
            return XCTFail("Expected an animated WebP asset")
        }
        XCTAssertEqual(asset.canvasPixelSize, CGSize(width: 4, height: 2))
        XCTAssertEqual(asset.frameCount, 3)
        XCTAssertEqual(asset.loopCount, 2)
        XCTAssertDurationsEqual(asset.frameDurations, [0.10, 0.20, 0.30])
        XCTAssertTrue(counter.indices.isEmpty)

        let blended = try asset.provider.frame(at: 1)
        XCTAssertEqual(counter.indices, [0, 1])
        XCTAssertEqual(pixel(in: blended.image, x: 0), blue)
        XCTAssertEqual(pixel(in: blended.image, x: 2), (128, 0, 127, 255))

        let disposed = try asset.provider.frame(at: 2)
        XCTAssertEqual(counter.indices, [0, 1, 2])
        XCTAssertEqual(pixel(in: disposed.image, x: 0), green)
        XCTAssertEqual(pixel(in: disposed.image, x: 2), transparent)
    }

    func testAnimatedWebPSequentialAccessDecodesEachFragmentOnce() throws {
        let counter = DecodeCounter()
        let decoder = WebPAnimationDecoder(
            maxDecodedBytes: 1_024,
            frameDecodeObserver: { counter.indices.append($0) }
        )
        guard case let .animation(asset) = try decoder.decode(url: fixtureURL("blend.webp")) else {
            return XCTFail("Expected an animated WebP asset")
        }

        _ = try asset.provider.frame(at: 0)
        _ = try asset.provider.frame(at: 1)
        _ = try asset.provider.frame(at: 2)
        XCTAssertEqual(counter.indices, [0, 1, 2])

        _ = try asset.provider.frame(at: 0)
        XCTAssertEqual(counter.indices, [0, 1, 2, 0])
    }

    func testAnimatedWebPForwardJumpContinuesFromCurrentCanvas() throws {
        let counter = DecodeCounter()
        let decoder = WebPAnimationDecoder(
            maxDecodedBytes: 1_024,
            frameDecodeObserver: { counter.indices.append($0) }
        )
        guard case let .animation(asset) = try decoder.decode(url: fixtureURL("blend.webp")) else {
            return XCTFail("Expected an animated WebP asset")
        }

        _ = try asset.provider.frame(at: 0)
        _ = try asset.provider.frame(at: 2)
        XCTAssertEqual(counter.indices, [0, 1, 2])
    }

    func testAnimatedWebPFrameCompositionHonorsCancellation() throws {
        let counter = DecodeCounter()
        let decoder = WebPAnimationDecoder(
            maxDecodedBytes: 1_024,
            frameDecodeObserver: { counter.indices.append($0) }
        )
        guard case let .animation(asset) = try decoder.decode(url: fixtureURL("blend.webp")) else {
            return XCTFail("Expected an animated WebP asset")
        }
        let cancellation = DecodeCancellation()
        cancellation.cancel()

        XCTAssertThrowsError(try asset.provider.frame(at: 2, cancellation: cancellation)) { error in
            XCTAssertEqual(error as? ImageLoadError, .cancelled)
        }
        XCTAssertTrue(counter.indices.isEmpty)
    }

    func testAnimationRouterReturnsOnlyMultiFrameAssets() throws {
        let router = AnimationDecoderRouter()

        XCTAssertNotNil(try router.decodeIfPresent(url: fixtureURL("disposal.gif")))
        XCTAssertNotNil(try router.decodeIfPresent(url: fixtureURL("blend.webp")))
        XCTAssertNil(try router.decodeIfPresent(url: staticFixtureURL("alpha.png")))
    }

    func testAnimationRouterUsesNativeImageIOBeforeWebPFallback() throws {
        let asset = try makeAnimationAsset(format: .webP)
        let native = SpyAnimationDisplayDecoder(result: .success(.animation(asset)))
        let fallback = SpyAnimationDisplayDecoder(result: .failure(ImageLoadError.decodeFailed("unused")))
        let router = AnimationDecoderRouter(
            imageIOInspector: StubInspectionProvider(frameCount: 3),
            imageIOAnimation: native,
            webPAnimation: fallback
        )

        XCTAssertNotNil(try router.decodeIfPresent(url: fixtureURL("blend.webp")))
        XCTAssertEqual(native.callCount, 1)
        XCTAssertEqual(fallback.callCount, 0)
    }

    func testAnimationRouterFallsBackWhenNativeWebPDecodeFails() throws {
        let asset = try makeAnimationAsset(format: .webP)
        let native = SpyAnimationDisplayDecoder(result: .failure(ImageLoadError.decodeFailed("native")))
        let fallback = SpyAnimationDisplayDecoder(result: .success(.animation(asset)))
        let router = AnimationDecoderRouter(
            imageIOInspector: StubInspectionProvider(frameCount: 3),
            imageIOAnimation: native,
            webPAnimation: fallback
        )

        XCTAssertNotNil(try router.decodeIfPresent(url: fixtureURL("blend.webp")))
        XCTAssertEqual(native.callCount, 1)
        XCTAssertEqual(fallback.callCount, 1)
    }

    func testAnimationRouterFallsBackWhenImageIOReportsOneWebPFrame() throws {
        let fallback = SpyAnimationDisplayDecoder(
            result: .success(.animation(try makeAnimationAsset(format: .webP)))
        )
        let native = SpyAnimationDisplayDecoder(
            result: .failure(ImageLoadError.decodeFailed("unused"))
        )
        let router = AnimationDecoderRouter(
            imageIOInspector: StubInspectionProvider(frameCount: 1),
            imageIOAnimation: native,
            webPAnimation: fallback
        )

        XCTAssertNotNil(try router.decodeIfPresent(url: fixtureURL("blend.webp")))
        XCTAssertEqual(native.callCount, 0)
        XCTAssertEqual(fallback.callCount, 1)
    }

    func testAnimationRouterLazilyFallsBackWhenNativeWebPFrameFails() throws {
        let nativeAsset = AnimationAsset(provider: FailingFrameProvider(), format: .webP)
        let fallback = SpyAnimationDisplayDecoder(
            result: .success(.animation(try makeAnimationAsset(format: .webP)))
        )
        let router = AnimationDecoderRouter(
            imageIOInspector: StubInspectionProvider(frameCount: 2),
            imageIOAnimation: SpyAnimationDisplayDecoder(result: .success(.animation(nativeAsset))),
            webPAnimation: fallback
        )

        guard let asset = try router.decodeIfPresent(url: fixtureURL("blend.webp")) else {
            return XCTFail("Expected an animated WebP asset")
        }
        XCTAssertEqual(fallback.callCount, 0)
        XCTAssertEqual(try asset.provider.frame(at: 0).index, 0)
        XCTAssertEqual(fallback.callCount, 1)
    }

    func testAnimationDecodersRejectConfiguredFrameLimit() {
        XCTAssertThrowsError(
            try ImageIOAnimationDecoder(maxDecodedBytes: 1_024, maxFrameCount: 2)
                .decode(url: fixtureURL("sample.apng"))
        )
        XCTAssertThrowsError(
            try WebPAnimationDecoder(maxDecodedBytes: 1_024, maxFrameCount: 2)
                .decode(url: fixtureURL("blend.webp"))
        )
    }

    func testAnimationRouterHonorsCancellationBeforeInspection() {
        let cancellation = DecodeCancellation()
        cancellation.cancel()
        let router = AnimationDecoderRouter()

        XCTAssertThrowsError(
            try router.decodeIfPresent(url: fixtureURL("blend.webp"), cancellation: cancellation)
        ) { error in
            XCTAssertEqual(error as? ImageLoadError, .cancelled)
        }
    }

    func testCompositorAppliesSourceBlendAndDisposalToBackground() throws {
        let compositor = try FrameCompositor(
            canvasWidth: 3,
            canvasHeight: 1,
            maxDecodedBytes: 12
        )

        _ = try compositor.render(fragment(
            x: 0,
            width: 3,
            pixels: [red, red, red],
            blend: .source,
            disposal: .none
        ))
        let middle = try compositor.render(fragment(
            x: 1,
            width: 1,
            pixels: [blue],
            blend: .source,
            disposal: .background
        ))
        XCTAssertEqual(pixel(in: middle, x: 0), red)
        XCTAssertEqual(pixel(in: middle, x: 1), blue)
        XCTAssertEqual(pixel(in: middle, x: 2), red)

        let final = try compositor.render(fragment(
            x: 2,
            width: 1,
            pixels: [green],
            blend: .source,
            disposal: .none
        ))
        XCTAssertEqual(pixel(in: final, x: 0), red)
        XCTAssertEqual(pixel(in: final, x: 1), transparent)
        XCTAssertEqual(pixel(in: final, x: 2), green)
    }

    func testCompositorUsesPremultipliedSourceOverAlpha() throws {
        let compositor = try FrameCompositor(
            canvasWidth: 1,
            canvasHeight: 1,
            maxDecodedBytes: 4
        )
        _ = try compositor.render(fragment(
            x: 0,
            width: 1,
            pixels: [blue],
            blend: .source,
            disposal: .none
        ))

        let result = try compositor.render(fragment(
            x: 0,
            width: 1,
            pixels: [(128, 0, 0, 128)],
            blend: .over,
            disposal: .none
        ))

        XCTAssertEqual(pixel(in: result, x: 0), (128, 0, 127, 255))
    }

    func testCompositorHandlesTransparentSourceAndDestinationAlpha() throws {
        let compositor = try FrameCompositor(canvasWidth: 1, canvasHeight: 1, maxDecodedBytes: 4)
        _ = try compositor.render(fragment(
            x: 0,
            width: 1,
            pixels: [(0, 0, 128, 128)],
            blend: .source,
            disposal: .none
        ))
        let blended = try compositor.render(fragment(
            x: 0,
            width: 1,
            pixels: [(64, 0, 0, 128)],
            blend: .over,
            disposal: .none
        ))
        XCTAssertEqual(pixel(in: blended, x: 0), (64, 0, 64, 192))

        let cleared = try compositor.render(fragment(
            x: 0,
            width: 1,
            pixels: [transparent],
            blend: .source,
            disposal: .none
        ))
        XCTAssertEqual(pixel(in: cleared, x: 0), transparent)
    }

    func testCompositorPlacesFragmentAtVerticalOffset() throws {
        let compositor = try FrameCompositor(canvasWidth: 1, canvasHeight: 2, maxDecodedBytes: 8)
        let result = try compositor.render(fragment(
            x: 0,
            y: 1,
            width: 1,
            pixels: [green],
            blend: .source,
            disposal: .none
        ))

        XCTAssertEqual(pixel(in: result, x: 0, y: 0), transparent)
        XCTAssertEqual(pixel(in: result, x: 0, y: 1), green)
    }

    func testAnimatedWebPRejectsInvalidFrameIndex() throws {
        guard case let .animation(asset) = try WebPAnimationDecoder(maxDecodedBytes: 1_024)
            .decode(url: fixtureURL("blend.webp")) else {
            return XCTFail("Expected an animated WebP asset")
        }
        XCTAssertThrowsError(try asset.provider.frame(at: -1))
        XCTAssertThrowsError(try asset.provider.frame(at: asset.frameCount))
    }

    func testAnimatedWebPIgnoresBytesOutsideDeclaredRIFFContainer() throws {
        var data = try Data(contentsOf: fixtureURL("blend.webp"))
        data.append(contentsOf: Array("ANMF".utf8))
        data.append(contentsOf: [0xff, 0xff, 0xff, 0x7f])

        try withTemporaryWebP(data) { url in
            guard case let .animation(asset) = try WebPAnimationDecoder(maxDecodedBytes: 1_024)
                .decode(url: url) else {
                return XCTFail("Expected trailing bytes outside RIFF to be ignored")
            }
            XCTAssertEqual(asset.frameCount, 3)
        }
    }

    func testAnimatedWebPRejectsDuplicateVP8XChunk() throws {
        var data = try Data(contentsOf: fixtureURL("blend.webp"))
        let firstChunk = try riffChunk(in: data, named: "VP8X")
        data.append(data[firstChunk])
        writeUInt32(UInt32(data.count - 8), to: &data, at: 4)

        try withTemporaryWebP(data) { url in
            XCTAssertThrowsError(
                try WebPAnimationDecoder(maxDecodedBytes: 1_024).decode(url: url)
            )
        }
    }

    func testAnimatedWebPRejectsFrameHeaderDimensionMismatch() throws {
        var data = try Data(contentsOf: fixtureURL("blend.webp"))
        let frame = try riffChunk(in: data, named: "ANMF")
        let payloadStart = frame.lowerBound + 8
        data[payloadStart + 6] = 2 // Declare width 3 while embedded image remains width 4.
        data[payloadStart + 7] = 0
        data[payloadStart + 8] = 0

        try withTemporaryWebP(data) { url in
            XCTAssertThrowsError(
                try WebPAnimationDecoder(maxDecodedBytes: 1_024).decode(url: url)
            )
        }
    }

    func testAnimatedWebPRejectsTruncatedInnerImageChunk() throws {
        var data = try Data(contentsOf: fixtureURL("blend.webp"))
        let frame = try riffChunk(in: data, named: "ANMF")
        let innerChunkOffset = frame.lowerBound + 8 + 16
        writeUInt32(UInt32.max, to: &data, at: innerChunkOffset + 4)

        try withTemporaryWebP(data) { url in
            XCTAssertThrowsError(
                try WebPAnimationDecoder(maxDecodedBytes: 1_024).decode(url: url)
            )
        }
    }

    func testAnimatedWebPInnerChunkScanHonorsCancellation() {
        let cancellation = DecodeCancellation()
        let counter = CallbackCounter {
            cancellation.cancel()
        }
        let decoder = WebPAnimationDecoder(
            maxDecodedBytes: 1_024,
            frameDecodeObserver: { _ in },
            indexChunkObserver: { counter.recordAndCancel(on: 4) }
        )

        XCTAssertThrowsError(
            try decoder.decode(url: fixtureURL("blend.webp"), cancellation: cancellation)
        ) { error in
            XCTAssertEqual(error as? ImageLoadError, .cancelled)
        }
        XCTAssertEqual(counter.count, 4)
    }

    func testCompositorRejectsCanvasBeyondDecodedBudget() {
        XCTAssertThrowsError(
            try FrameCompositor(canvasWidth: 2, canvasHeight: 2, maxDecodedBytes: 15)
        ) { error in
            XCTAssertEqual(
                error as? ImageLoadError,
                .decodedImageTooLarge(required: 16, limit: 15)
            )
        }
    }

    private let red: Pixel = (255, 0, 0, 255)
    private let green: Pixel = (0, 255, 0, 255)
    private let blue: Pixel = (0, 0, 255, 255)
    private let transparent: Pixel = (0, 0, 0, 0)

    private func fragment(
        x: Int,
        y: Int = 0,
        width: Int,
        pixels: [Pixel],
        blend: AnimationBlendMode,
        disposal: AnimationDisposalMode
    ) -> AnimationFrameFragment {
        var bytes: [UInt8] = []
        for pixel in pixels {
            bytes.append(contentsOf: [pixel.0, pixel.1, pixel.2, pixel.3])
        }
        return AnimationFrameFragment(
            xOffset: x,
            yOffset: y,
            width: width,
            height: 1,
            rowBytes: width * 4,
            premultipliedRGBA: Data(bytes),
            blendMode: blend,
            disposalMode: disposal
        )
    }

    private func pixel(in image: CGImage, x: Int, y: Int = 0) -> Pixel {
        var bytes = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.interpolationQuality = .none
        context.draw(
            image,
            in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height)
        )
        return (bytes[0], bytes[1], bytes[2], bytes[3])
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Animation")
            .appendingPathComponent(name)
    }

    private func staticFixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Static")
            .appendingPathComponent(name)
    }

    private func riffChunk(in data: Data, named name: String) throws -> Range<Int> {
        let expected = Array(name.utf8)
        var cursor = 12
        while cursor <= data.count - 8 {
            let nameBytes = Array(data[cursor..<(cursor + 4)])
            let size = Int(readUInt32(data, at: cursor + 4))
            let paddedSize = size + (size & 1)
            guard paddedSize <= data.count - cursor - 8 else {
                throw ImageLoadError.decodeFailed("Malformed test fixture")
            }
            let range = cursor..<(cursor + 8 + paddedSize)
            if nameBytes == expected { return range }
            cursor = range.upperBound
        }
        throw ImageLoadError.decodeFailed("Missing \(name) test chunk")
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private func writeUInt32(_ value: UInt32, to data: inout Data, at offset: Int) {
        data[offset] = UInt8(truncatingIfNeeded: value)
        data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        data[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        data[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }

    private func withTemporaryWebP(_ data: Data, body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("webp")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }

    private func makeAnimationAsset(format: ImageFormat) throws -> AnimationAsset {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw ImageLoadError.decodeFailed("Could not create test frame")
        }
        return AnimationAsset(provider: SingleFrameProvider(image: image), format: format)
    }
}

private final class DecodeCounter: @unchecked Sendable {
    var indices: [Int] = []
}

private final class CallbackCounter: @unchecked Sendable {
    private(set) var count = 0
    private let onThreshold: () -> Void

    init(onThreshold: @escaping () -> Void) {
        self.onThreshold = onThreshold
    }

    func recordAndCancel(on threshold: Int) {
        count += 1
        if count == threshold { onThreshold() }
    }
}

private struct StubInspectionProvider: ImageInspectionProviding {
    let frameCount: Int

    func inspect(url: URL) throws -> ImageInspection {
        ImageInspection(
            format: .webP,
            rawPixelSize: CGSize(width: 1, height: 1),
            orientedPixelSize: CGSize(width: 1, height: 1),
            orientation: .up,
            frameCount: frameCount,
            metadata: ImageMetadata(pixelSize: CGSize(width: 1, height: 1))
        )
    }
}

private final class SpyAnimationDisplayDecoder: AnimationDisplayDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<DisplayAsset, Error>
    private var calls = 0

    init(result: Result<DisplayAsset, Error>) { self.result = result }
    var callCount: Int { lock.withLock { calls } }

    func decode(url: URL, cancellation: DecodeCancellation) throws -> DisplayAsset {
        lock.withLock { calls += 1 }
        return try result.get()
    }
}

private final class SingleFrameProvider: AnimationFrameProvider, @unchecked Sendable {
    let descriptor = AnimationDescriptor(
        canvasPixelSize: CGSize(width: 1, height: 1),
        frameDurations: [0.1, 0.1],
        loopCount: nil
    )
    private let image: CGImage

    init(image: CGImage) { self.image = image }

    func frame(at index: Int) throws -> AnimationFrame {
        AnimationFrame(index: index, image: image, decodedByteCost: 4)
    }
}

private struct FailingFrameProvider: AnimationFrameProvider {
    let descriptor = AnimationDescriptor(
        canvasPixelSize: CGSize(width: 1, height: 1),
        frameDurations: [0.1, 0.1],
        loopCount: nil
    )

    func frame(at index: Int) throws -> AnimationFrame {
        throw ImageLoadError.decodeFailed("native frame failure")
    }
}

private typealias Pixel = (UInt8, UInt8, UInt8, UInt8)

private func XCTAssertEqual(
    _ lhs: Pixel,
    _ rhs: Pixel,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual([lhs.0, lhs.1, lhs.2, lhs.3], [rhs.0, rhs.1, rhs.2, rhs.3], file: file, line: line)
}

private func XCTAssertDurationsEqual(
    _ lhs: [TimeInterval],
    _ rhs: [TimeInterval],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
    for (actual, expected) in zip(lhs, rhs) {
        XCTAssertEqual(actual, expected, accuracy: 0.000_001, file: file, line: line)
    }
}
