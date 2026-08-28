import AVFoundation
import CoreVideo
import XCTest
@testable import LightViewCore

final class ExportFrameComposerTests: XCTestCase {
    func testFitLetterboxesWithConfiguredBackground() throws {
        let red = try solidImage(width: 4, height: 2, red: 255, green: 0, blue: 0)
        let composer = ExportFrameComposer(
            outputSize: CGSize(width: 4, height: 4),
            composition: .fit,
            transition: .none,
            background: .solid(.black),
            sourceImage: { _, _ in red }
        )
        let buffer = try makeBuffer(width: 4, height: 4)

        try composer.compose(instruction(primary: 0), into: buffer)

        XCTAssertEqual(try pixel(buffer, x: 0, y: 0), [0, 0, 0, 255])
        XCTAssertEqual(try pixel(buffer, x: 0, y: 1), [0, 0, 255, 255])
        XCTAssertEqual(try pixel(buffer, x: 3, y: 2), [0, 0, 255, 255])
        XCTAssertEqual(try pixel(buffer, x: 3, y: 3), [0, 0, 0, 255])
    }

    func testFillCropsWithoutLetterboxing() throws {
        let red = try solidImage(width: 4, height: 2, red: 255, green: 0, blue: 0)
        let composer = ExportFrameComposer(
            outputSize: CGSize(width: 2, height: 2),
            composition: .fill,
            transition: .none,
            background: .solid(.black),
            sourceImage: { _, _ in red }
        )
        let buffer = try makeBuffer(width: 2, height: 2)

        try composer.compose(instruction(primary: 0), into: buffer)

        for y in 0..<2 {
            for x in 0..<2 {
                XCTAssertEqual(try pixel(buffer, x: x, y: y), [0, 0, 255, 255])
            }
        }
    }

    func testHalfFadeBlendsRedAndBlueWithinOneChannelUnit() throws {
        let images = [
            try solidImage(width: 4, height: 2, red: 255, green: 0, blue: 0),
            try solidImage(width: 4, height: 2, red: 0, green: 0, blue: 255),
        ]
        let composer = ExportFrameComposer(
            outputSize: CGSize(width: 4, height: 2),
            composition: .fit,
            transition: .fade(duration: CMTime(seconds: 0.25, preferredTimescale: 600)),
            background: .solid(.black),
            sourceImage: { index, _ in images[index] }
        )
        let buffer = try makeBuffer(width: 4, height: 2)

        try composer.compose(instruction(primary: 0, secondary: 1, progress: 0.5), into: buffer)

        let value = try pixel(buffer, x: 2, y: 1)
        XCTAssertEqual(Int(value[0]), 128, accuracy: 1)
        XCTAssertEqual(Int(value[1]), 0, accuracy: 1)
        XCTAssertEqual(Int(value[2]), 127, accuracy: 1)
        XCTAssertEqual(value[3], 255)
    }

    func testHalfSlidePlacesOutgoingAndIncomingImagesSideBySide() throws {
        let images = [
            try solidImage(width: 4, height: 2, red: 255, green: 0, blue: 0),
            try solidImage(width: 4, height: 2, red: 0, green: 0, blue: 255),
        ]
        let composer = ExportFrameComposer(
            outputSize: CGSize(width: 4, height: 2),
            composition: .fit,
            transition: .slide(duration: CMTime(seconds: 0.25, preferredTimescale: 600)),
            background: .solid(.black),
            sourceImage: { index, _ in images[index] }
        )
        let buffer = try makeBuffer(width: 4, height: 2)

        try composer.compose(instruction(primary: 0, secondary: 1, progress: 0.5), into: buffer)

        XCTAssertEqual(try pixel(buffer, x: 0, y: 1), [0, 0, 255, 255])
        XCTAssertEqual(try pixel(buffer, x: 3, y: 1), [255, 0, 0, 255])
    }

    func testPoolReusesReleasedBuffersAndHonorsCountLimit() throws {
        let pool = try PixelBufferPool(width: 4, height: 2, maximumBufferCount: 2)
        let first = try XCTUnwrap(pool.acquire())
        let firstAddress = Unmanaged.passUnretained(first.buffer).toOpaque()
        let second = try XCTUnwrap(pool.acquire())

        XCTAssertNil(pool.acquire())
        XCTAssertEqual(pool.createdBufferCount, 2)
        first.release()
        let reused = try XCTUnwrap(pool.acquire())

        XCTAssertEqual(Unmanaged.passUnretained(reused.buffer).toOpaque(), firstAddress)
        XCTAssertEqual(pool.createdBufferCount, 2)
        second.release()
        reused.release()
    }

    private func instruction(
        primary: Int,
        secondary: Int? = nil,
        progress: Double = 0
    ) -> FrameInstruction {
        FrameInstruction(
            presentationTime: .zero,
            primarySourceIndex: primary,
            secondarySourceIndex: secondary,
            transitionProgress: progress,
            primaryLocalTime: .zero,
            secondaryLocalTime: secondary == nil ? nil : .zero
        )
    }

    private func solidImage(
        width: Int,
        height: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8
    ) throws -> CGImage {
        let bytes: [UInt8] = (0..<(width * height)).flatMap { _ in [red, green, blue, 255] }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { throw MovieExportError.invalidPlan("Could not create test image") }
        return image
    }

    private func makeBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw MovieExportError.invalidPlan("Could not create test pixel buffer")
        }
        return buffer
    }

    private func pixel(_ buffer: CVPixelBuffer, x: Int, y: Int) throws -> [UInt8] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw MovieExportError.invalidPlan("Missing pixel buffer memory")
        }
        let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
        let bytes = base.assumingMemoryBound(to: UInt8.self).advanced(by: offset)
        return Array(UnsafeBufferPointer(start: bytes, count: 4))
    }
}
