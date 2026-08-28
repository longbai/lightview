import CoreGraphics
import XCTest
@testable import LightViewCore

final class FrameClockTests: XCTestCase {
    private let durations: [TimeInterval] = [0.10, 0.20, 0.30]

    func testInfiniteTimelineUsesCumulativeBoundariesAndWraps() {
        var clock = FrameClock(descriptor: descriptor())
        clock.play(at: 10)

        XCTAssertEqual(clock.advance(to: 10.00), .init(frameIndex: 0, completedLoopCount: 0, isComplete: false))
        XCTAssertEqual(clock.advance(to: 10.10).frameIndex, 1)
        XCTAssertEqual(clock.advance(to: 10.30).frameIndex, 2)
        XCTAssertEqual(clock.advance(to: 10.59).frameIndex, 2)
        XCTAssertEqual(clock.advance(to: 10.60), .init(frameIndex: 0, completedLoopCount: 1, isComplete: false))
    }

    func testFiniteTimelineStopsOnLastFrameAfterRequestedPlaythroughs() {
        var clock = FrameClock(descriptor: descriptor(loopCount: 2))
        clock.play(at: 0)

        let final = clock.advance(to: 1.20)

        XCTAssertEqual(final, .init(frameIndex: 2, completedLoopCount: 2, isComplete: true))
        XCTAssertFalse(clock.isPlaying)
        XCTAssertEqual(clock.advance(to: 100), final)
    }

    func testSpeedPauseAndResumePreserveTimelinePosition() {
        var clock = FrameClock(descriptor: descriptor())
        clock.setSpeed(2, at: 0)
        clock.play(at: 5)
        XCTAssertEqual(clock.advance(to: 5.15).frameIndex, 2)

        clock.pause(at: 5.15)
        XCTAssertEqual(clock.advance(to: 50).frameIndex, 2)

        clock.play(at: 50)
        XCTAssertEqual(clock.advance(to: 50.15).frameIndex, 0)
        XCTAssertEqual(clock.advance(to: 50.20).completedLoopCount, 1)
    }

    func testChangingSpeedWhilePlayingReanchorsWithoutJumping() {
        var clock = FrameClock(descriptor: descriptor())
        clock.play(at: 0)
        XCTAssertEqual(clock.advance(to: 0.15).frameIndex, 1)

        clock.setSpeed(2, at: 0.15)

        XCTAssertEqual(clock.advance(to: 0.15).frameIndex, 1)
        XCTAssertEqual(clock.advance(to: 0.225).frameIndex, 2)
    }

    func testFiniteTimelineSeekWithinLastLoopStillCompletesAtItsEnd() {
        var clock = FrameClock(descriptor: descriptor(loopCount: 2))
        clock.play(at: 0)
        _ = clock.advance(to: 0.70)

        clock.seek(toFrame: 2, at: 0.70)

        XCTAssertEqual(clock.advance(to: 0.70).frameIndex, 2)
        XCTAssertEqual(
            clock.advance(to: 1.0),
            .init(frameIndex: 2, completedLoopCount: 2, isComplete: true)
        )
    }

    func testLateAdvanceCatchesUpWithoutMovingTheTimelineAnchor() {
        var clock = FrameClock(descriptor: descriptor())
        clock.play(at: 0)

        XCTAssertEqual(clock.advance(to: 0.55).frameIndex, 2)
        XCTAssertEqual(clock.advance(to: 0.65).frameIndex, 0)
        XCTAssertEqual(clock.advance(to: 0.70).frameIndex, 1)
    }

    func testRegressingAndNonFiniteTimestampsCannotRewindOrCorruptClock() {
        var clock = FrameClock(descriptor: descriptor())
        clock.play(at: .nan)
        XCTAssertFalse(clock.isPlaying)

        clock.play(at: 0)
        let forward = clock.advance(to: 0.30)
        XCTAssertEqual(forward.frameIndex, 2)
        XCTAssertEqual(clock.advance(to: 0.05), forward)

        clock.pause(at: .nan)
        XCTAssertTrue(clock.isPlaying)
        clock.setSpeed(2, at: .infinity)
        XCTAssertEqual(clock.speed, 1)
        clock.seek(toFrame: 0, at: -.infinity)
        XCTAssertEqual(clock.advance(to: 0.05), forward)
    }

    func testExtremeFiniteTimestampSaturatesWithoutTrapping() {
        var clock = FrameClock(descriptor: descriptor())
        clock.play(at: 0)

        let result = clock.advance(to: .greatestFiniteMagnitude)

        XCTAssertEqual(result.completedLoopCount, .max)
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(clock.advance(to: .greatestFiniteMagnitude), result)
    }

    func testDescriptorNormalizesInvalidAndTinyDurations() {
        let descriptor = AnimationDescriptor(
            canvasPixelSize: CGSize(width: 20, height: 10),
            frameDurations: [0, -2, .infinity, .nan, 0.001],
            loopCount: 0
        )

        XCTAssertEqual(descriptor.frameDurations, [0.10, 0.10, 0.10, 0.10, 0.01])
        XCTAssertEqual(descriptor.loopCount, 1)
        XCTAssertEqual(descriptor.cycleDuration, 0.41, accuracy: 0.000_001)
    }

    private func descriptor(loopCount: Int? = nil) -> AnimationDescriptor {
        AnimationDescriptor(
            canvasPixelSize: CGSize(width: 30, height: 20),
            frameDurations: durations,
            loopCount: loopCount
        )
    }
}
