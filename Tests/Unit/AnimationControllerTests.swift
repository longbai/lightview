import CoreGraphics
import XCTest
@testable import LightViewCore

final class AnimationControllerTests: XCTestCase {
    func testPlayPauseSpeedAndFrameCommands() throws {
        let provider = TestFrameProvider(descriptor: descriptor(), frameByteCost: 1)
        let controller = AnimationController(provider: provider, cacheByteLimit: 3)

        controller.play(at: 0)
        _ = try controller.advance(to: 0.15)
        XCTAssertEqual(controller.currentFrameIndex, 1)

        controller.pause(at: 0.15)
        _ = try controller.advance(to: 10)
        XCTAssertEqual(controller.currentFrameIndex, 1)

        controller.stepForward(at: 10)
        XCTAssertEqual(controller.currentFrameIndex, 2)
        controller.stepBackward(at: 10)
        XCTAssertEqual(controller.currentFrameIndex, 1)

        controller.setSpeed(2, at: 10)
        controller.play(at: 10)
        _ = try controller.advance(to: 10.15)
        XCTAssertEqual(controller.currentFrameIndex, 1)
    }

    func testSlidingCacheNeverRetainsFourFramesWithThreeFrameBudget() throws {
        let provider = TestFrameProvider(descriptor: descriptor(frameCount: 5), frameByteCost: 1)
        var observedMetrics: [(count: Int, bytes: Int)] = []
        let controller = AnimationController(
            provider: provider,
            cacheByteLimit: 3,
            cacheMutationObserver: { observedMetrics.append(($0, $1)) }
        )
        controller.play(at: 0)

        for time in [0.0, 0.11, 0.21, 0.31, 0.41] {
            _ = try controller.advance(to: time)
            XCTAssertLessThanOrEqual(controller.cachedFrameIndices.count, 3)
        }

        XCTAssertEqual(controller.cachedFrameIndices, Set([3, 4, 0]))
        XCTAssertTrue(observedMetrics.allSatisfy { $0.count <= 3 && $0.bytes <= 3 })
    }

    func testSlidingCacheEvictsPriorBeforeCurrentOrNextUnderPressure() throws {
        let provider = TestFrameProvider(descriptor: descriptor(), frameByteCost: 1)
        let controller = AnimationController(provider: provider, cacheByteLimit: 2)
        controller.play(at: 0)

        _ = try controller.advance(to: 0)
        _ = try controller.advance(to: 0.15)

        XCTAssertEqual(controller.currentFrameIndex, 1)
        XCTAssertEqual(controller.cachedFrameIndices, Set([1, 2]))
        XCTAssertEqual(controller.cachedByteCost, 2)
    }

    func testOversizedCurrentFrameIsReturnedWithoutBeingRetained() throws {
        let provider = TestFrameProvider(descriptor: descriptor(), frameByteCost: 10)
        let controller = AnimationController(provider: provider, cacheByteLimit: 3)

        let frame = try controller.advance(to: 0)

        XCTAssertEqual(frame.decodedByteCost, 10)
        XCTAssertTrue(controller.cachedFrameIndices.isEmpty)
        XCTAssertEqual(controller.cachedByteCost, 0)
    }

    func testZeroCacheBudgetRetainsNoFrame() throws {
        let provider = TestFrameProvider(descriptor: descriptor(), frameByteCost: 1)
        let controller = AnimationController(provider: provider, cacheByteLimit: 0)

        _ = try controller.advance(to: 0)

        XCTAssertTrue(controller.cachedFrameIndices.isEmpty)
        XCTAssertEqual(controller.cachedByteCost, 0)
    }

    func testZeroCostFrameIsNotCached() throws {
        let provider = TestFrameProvider(descriptor: descriptor(), frameByteCost: 0)
        let controller = AnimationController(provider: provider, cacheByteLimit: 3)

        _ = try controller.advance(to: 0)

        XCTAssertTrue(controller.cachedFrameIndices.isEmpty)
    }

    func testProviderReturningWrongFrameIndexIsRejected() {
        let provider = TestFrameProvider(
            descriptor: descriptor(),
            frameByteCost: 1,
            returnedIndexOffset: 1
        )
        let controller = AnimationController(provider: provider, cacheByteLimit: 3)

        XCTAssertThrowsError(try controller.advance(to: 0)) { error in
            XCTAssertEqual(
                error as? AnimationPlaybackError,
                .frameIndexMismatch(requested: 0, returned: 1)
            )
        }
    }

    func testAnimationAssetDerivesDescriptorFromProvider() {
        let provider = TestFrameProvider(descriptor: descriptor(frameCount: 5), frameByteCost: 1)

        let asset = AnimationAsset(provider: provider)

        XCTAssertEqual(asset.descriptor, provider.descriptor)
    }

    private func descriptor(frameCount: Int = 3) -> AnimationDescriptor {
        AnimationDescriptor(
            canvasPixelSize: CGSize(width: 1, height: 1),
            frameDurations: Array(repeating: 0.10, count: frameCount),
            loopCount: nil
        )
    }
}

private final class TestFrameProvider: AnimationFrameProvider, @unchecked Sendable {
    let descriptor: AnimationDescriptor
    private let frameByteCost: Int
    private let returnedIndexOffset: Int
    private let image: CGImage

    init(
        descriptor: AnimationDescriptor,
        frameByteCost: Int,
        returnedIndexOffset: Int = 0
    ) {
        self.descriptor = descriptor
        self.frameByteCost = frameByteCost
        self.returnedIndexOffset = returnedIndexOffset
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        image = context.makeImage()!
    }

    func frame(at index: Int) throws -> AnimationFrame {
        AnimationFrame(
            index: index + returnedIndexOffset,
            image: image,
            decodedByteCost: frameByteCost
        )
    }
}
