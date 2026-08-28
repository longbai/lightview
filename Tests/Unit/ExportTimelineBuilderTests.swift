import AVFoundation
import XCTest
@testable import LightViewCore

final class ExportTimelineBuilderTests: XCTestCase {
    func testTwoSecondStillAtThirtyFPSCreatesSixtyLightweightInstructions() throws {
        let plan = MovieExportPlan(
            outputSize: CGSize(width: 640, height: 480),
            frameRate: 30,
            sources: [.still(identifier: "one")],
            staticDuration: seconds(2),
            transition: .none,
            animationDurationPolicy: .oneLoop
        )

        let timeline = try ExportTimelineBuilder().build(plan)

        XCTAssertEqual(timeline.count, 60)
        XCTAssertEqual(timeline.first?.presentationTime, .zero)
        XCTAssertEqual(timeline.last?.presentationTime, seconds(59.0 / 30.0))
        XCTAssertEqual(timeline.last?.primarySourceIndex, 0)
        XCTAssertNil(timeline.last?.secondarySourceIndex)
    }

    func testQuarterSecondFadeOverlapsTwoOneSecondStillsDeterministically() throws {
        let plan = MovieExportPlan(
            outputSize: CGSize(width: 640, height: 480),
            frameRate: 30,
            sources: [.still(identifier: "red"), .still(identifier: "blue")],
            staticDuration: seconds(1),
            transition: .fade(duration: seconds(0.25)),
            animationDurationPolicy: .oneLoop
        )

        let timeline = try ExportTimelineBuilder().build(plan)
        let overlap = timeline.filter { $0.secondarySourceIndex != nil }

        XCTAssertEqual(timeline.count, 53)
        XCTAssertEqual(overlap.count, 7)
        XCTAssertEqual(overlap.first?.primarySourceIndex, 0)
        XCTAssertEqual(overlap.first?.secondarySourceIndex, 1)
        XCTAssertEqual(overlap.first?.transitionProgress ?? -1, 1.0 / 15.0, accuracy: 0.000_001)
        XCTAssertEqual(overlap.last?.transitionProgress ?? -1, 13.0 / 15.0, accuracy: 0.000_001)
        XCTAssertEqual(timeline.last?.primarySourceIndex, 1)
    }

    func testAnimationPoliciesTerminateAtExactPresentationDurations() throws {
        let animation = ExportSource.animation(
            identifier: "animation",
            frameDurations: [seconds(0.1), seconds(0.2)],
            sourceLoopCount: 3
        )

        XCTAssertEqual(try duration(for: animation, policy: .oneLoop), 0.3, accuracy: 0.000_001)
        XCTAssertEqual(try duration(for: animation, policy: .sourceLoopCount), 0.9, accuracy: 0.000_001)
        XCTAssertEqual(try duration(for: animation, policy: .maximum(seconds(1.25))), 1.25, accuracy: 0.000_001)
    }

    func testRejectsInvalidDimensionsFrameRateAndDurations() {
        let source = ExportSource.still(identifier: "one")
        XCTAssertThrowsError(try ExportTimelineBuilder().build(MovieExportPlan(
            outputSize: .zero,
            frameRate: 30,
            sources: [source],
            staticDuration: seconds(1),
            transition: .none,
            animationDurationPolicy: .oneLoop
        )))
        XCTAssertThrowsError(try ExportTimelineBuilder().build(MovieExportPlan(
            outputSize: CGSize(width: 640, height: 480),
            frameRate: 0,
            sources: [source],
            staticDuration: seconds(1),
            transition: .none,
            animationDurationPolicy: .oneLoop
        )))
        XCTAssertThrowsError(try ExportTimelineBuilder().build(MovieExportPlan(
            outputSize: CGSize(width: 640, height: 480),
            frameRate: 30,
            sources: [source],
            staticDuration: .zero,
            transition: .none,
            animationDurationPolicy: .oneLoop
        )))
    }

    private func duration(for source: ExportSource, policy: AnimationDurationPolicy) throws -> Double {
        let timeline = try ExportTimelineBuilder().build(MovieExportPlan(
            outputSize: CGSize(width: 640, height: 480),
            frameRate: 20,
            sources: [source],
            staticDuration: seconds(1),
            transition: .none,
            animationDurationPolicy: policy
        ))
        return CMTimeGetSeconds(timeline.duration)
    }

    private func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: 600)
    }
}
