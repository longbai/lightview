import AVFoundation
import Foundation

public struct ExportTimelineBuilder: Sendable {
    private static let timescale: CMTimeScale = 600

    public init() {}

    public func build(_ plan: MovieExportPlan) throws -> ExportTimeline {
        try validate(plan)
        let sourceDurations = try plan.sources.map {
            try duration(for: $0, plan: plan)
        }
        let transitionDuration = plan.transition.duration
        if transitionDuration > .zero {
            for index in sourceDurations.indices.dropLast() {
                guard transitionDuration < sourceDurations[index],
                      transitionDuration < sourceDurations[index + 1] else {
                    throw MovieExportError.invalidPlan("Transition must be shorter than adjacent sources")
                }
            }
        }

        var starts = [CMTime]()
        var cursor = CMTime.zero
        for (index, duration) in sourceDurations.enumerated() {
            starts.append(cursor)
            cursor = cursor + duration
            if index < sourceDurations.count - 1 { cursor = cursor - transitionDuration }
        }
        let totalDuration = cursor
        let frameDuration = CMTime(value: 1, timescale: plan.frameRate)
        let totalSeconds = CMTimeGetSeconds(totalDuration)
        let frameCount = Int(ceil(totalSeconds * Double(plan.frameRate)))
        var instructions = [FrameInstruction]()
        instructions.reserveCapacity(frameCount)

        for frameIndex in 0..<frameCount {
            let time = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            guard time < totalDuration else { break }
            let sourceIndex = outgoingTransitionSourceIndex(
                at: time,
                starts: starts,
                durations: sourceDurations,
                transitionDuration: transitionDuration
            ) ?? currentSourceIndex(at: time, starts: starts)
            let sourceEnd = starts[sourceIndex] + sourceDurations[sourceIndex]
            let nextIndex = sourceIndex + 1
            if (nextIndex < plan.sources.count),
               (transitionDuration > .zero),
               (time >= sourceEnd - transitionDuration),
               (time < sourceEnd) {
                let transitionStart = sourceEnd - transitionDuration
                let progress = CMTimeGetSeconds(time - transitionStart) / CMTimeGetSeconds(transitionDuration)
                instructions.append(FrameInstruction(
                    presentationTime: time,
                    primarySourceIndex: sourceIndex,
                    secondarySourceIndex: nextIndex,
                    transitionProgress: progress,
                    primaryLocalTime: time - starts[sourceIndex],
                    secondaryLocalTime: max(.zero, time - starts[nextIndex])
                ))
            } else {
                instructions.append(FrameInstruction(
                    presentationTime: time,
                    primarySourceIndex: sourceIndex,
                    primaryLocalTime: time - starts[sourceIndex]
                ))
            }
        }

        return ExportTimeline(instructions: instructions, duration: totalDuration)
    }

    private func validate(_ plan: MovieExportPlan) throws {
        guard plan.outputSize.width.isFinite, plan.outputSize.height.isFinite,
              plan.outputSize.width > 0, plan.outputSize.height > 0 else {
            throw MovieExportError.invalidPlan("Output dimensions must be positive")
        }
        guard plan.frameRate > 0, plan.frameRate <= 120 else {
            throw MovieExportError.invalidPlan("Frame rate must be between 1 and 120")
        }
        guard !plan.sources.isEmpty else {
            throw MovieExportError.invalidPlan("At least one source is required")
        }
        try requirePositive(plan.staticDuration, name: "Static duration")
        if plan.transition.duration != .zero {
            try requirePositive(plan.transition.duration, name: "Transition duration")
        }
        if case .maximum(let duration) = plan.animationDurationPolicy {
            try requirePositive(duration, name: "Maximum animation duration")
        }
    }

    private func duration(for source: ExportSource, plan: MovieExportPlan) throws -> CMTime {
        switch source.content {
        case .still:
            return plan.staticDuration.convertScale(Self.timescale, method: .roundHalfAwayFromZero)
        case .animation(let frameDurations, let sourceLoopCount):
            guard !frameDurations.isEmpty else {
                throw MovieExportError.invalidPlan("Animation has no frames")
            }
            var cycle = CMTime.zero
            for duration in frameDurations {
                try requirePositive(duration, name: "Animation frame duration")
                cycle = cycle + duration
            }
            switch plan.animationDurationPolicy {
            case .oneLoop:
                return cycle
            case .sourceLoopCount:
                let loopCount = max(1, sourceLoopCount ?? 1)
                guard loopCount <= Int(Int32.max) else {
                    throw MovieExportError.invalidPlan("Animation loop count is too large")
                }
                return CMTimeMultiply(cycle, multiplier: Int32(loopCount))
            case .maximum(let maximum):
                return maximum.convertScale(Self.timescale, method: .roundHalfAwayFromZero)
            }
        }
    }

    private func requirePositive(_ time: CMTime, name: String) throws {
        let seconds = CMTimeGetSeconds(time)
        guard time.isNumeric, seconds.isFinite, seconds > 0 else {
            throw MovieExportError.invalidPlan("\(name) must be positive")
        }
    }

    private func currentSourceIndex(
        at time: CMTime,
        starts: [CMTime]
    ) -> Int {
        for index in starts.indices.reversed() where time >= starts[index] {
            return index
        }
        return 0
    }

    private func outgoingTransitionSourceIndex(
        at time: CMTime,
        starts: [CMTime],
        durations: [CMTime],
        transitionDuration: CMTime
    ) -> Int? {
        guard transitionDuration > .zero, starts.count > 1 else { return nil }
        for index in starts.indices.dropLast() {
            let end = starts[index] + durations[index]
            if time >= end - transitionDuration, time < end { return index }
        }
        return nil
    }
}

private func max(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
    lhs >= rhs ? lhs : rhs
}
