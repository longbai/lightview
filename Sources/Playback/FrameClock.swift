import Foundation

public struct FramePresentation: Sendable, Equatable {
    public let frameIndex: Int
    public let completedLoopCount: Int
    public let isComplete: Bool

    public init(frameIndex: Int, completedLoopCount: Int, isComplete: Bool) {
        self.frameIndex = frameIndex
        self.completedLoopCount = completedLoopCount
        self.isComplete = isComplete
    }
}

public struct FrameClock: Sendable {
    public let descriptor: AnimationDescriptor
    public private(set) var isPlaying = false
    public private(set) var speed: Double = 1

    private var positionAtAnchor: TimeInterval = 0
    private var anchorTimestamp: TimeInterval?
    private var lastAcceptedTimestamp: TimeInterval?
    private var lastPresentation = FramePresentation(
        frameIndex: 0,
        completedLoopCount: 0,
        isComplete: false
    )

    public init(descriptor: AnimationDescriptor) {
        self.descriptor = descriptor
    }

    public mutating func play(at timestamp: TimeInterval) {
        guard !lastPresentation.isComplete, !isPlaying, accept(timestamp) else { return }
        anchorTimestamp = timestamp
        isPlaying = true
    }

    public mutating func pause(at timestamp: TimeInterval) {
        guard isPlaying, accept(timestamp) else { return }
        reanchor(at: timestamp)
        isPlaying = false
    }

    public mutating func setSpeed(_ requestedSpeed: Double, at timestamp: TimeInterval) {
        guard accept(timestamp) else { return }
        let normalizedSpeed = requestedSpeed.isFinite ? min(8, max(0.10, requestedSpeed)) : 1
        if isPlaying { reanchor(at: timestamp) }
        speed = normalizedSpeed
    }

    public mutating func seek(toFrame requestedIndex: Int, at timestamp: TimeInterval) {
        guard accept(timestamp) else { return }
        let frameCount = descriptor.frameCount
        let index = ((requestedIndex % frameCount) + frameCount) % frameCount
        let currentPosition = timelinePosition(at: timestamp)
        let currentLoop = min(
            completedLoopCount(for: currentPosition, epsilon: 0),
            max(0, (descriptor.loopCount ?? .max) - 1)
        )
        let frameStart = index == 0 ? 0 : descriptor.cumulativeFrameEndTimes[index - 1]
        positionAtAnchor = TimeInterval(currentLoop) * descriptor.cycleDuration + frameStart
        anchorTimestamp = isPlaying ? timestamp : nil
        lastPresentation = presentation(for: positionAtAnchor)
    }

    @discardableResult
    public mutating func advance(to timestamp: TimeInterval) -> FramePresentation {
        guard accept(timestamp) else { return lastPresentation }
        let position = timelinePosition(at: timestamp)
        let result = presentation(for: position)
        lastPresentation = result
        if result.isComplete {
            positionAtAnchor = descriptor.cycleDuration * TimeInterval(descriptor.loopCount ?? 1)
            anchorTimestamp = nil
            isPlaying = false
        }
        return result
    }

    private func timelinePosition(at timestamp: TimeInterval) -> TimeInterval {
        guard isPlaying, let anchorTimestamp else { return positionAtAnchor }
        let elapsed = max(0, timestamp - anchorTimestamp)
        let scaledElapsed = elapsed * speed
        guard scaledElapsed.isFinite else { return .greatestFiniteMagnitude }
        let position = positionAtAnchor + scaledElapsed
        return position.isFinite ? position : .greatestFiniteMagnitude
    }

    private mutating func reanchor(at timestamp: TimeInterval) {
        positionAtAnchor = timelinePosition(at: timestamp)
        anchorTimestamp = timestamp
        lastPresentation = presentation(for: positionAtAnchor)
    }

    private func presentation(for rawPosition: TimeInterval) -> FramePresentation {
        let cycleDuration = descriptor.cycleDuration
        let epsilon = max(1e-9, cycleDuration * 1e-12)
        let position = max(0, rawPosition)
        if let loopCount = descriptor.loopCount {
            let totalDuration = cycleDuration * TimeInterval(loopCount)
            if position + epsilon >= totalDuration {
                return FramePresentation(
                    frameIndex: descriptor.frameCount - 1,
                    completedLoopCount: loopCount,
                    isComplete: true
                )
            }
        }
        let completedLoops = completedLoopCount(for: position, epsilon: epsilon)
        var cyclePosition = max(0, position.truncatingRemainder(dividingBy: cycleDuration))
        if cyclePosition + epsilon >= cycleDuration {
            cyclePosition = 0
        }
        let frameIndex = descriptor.cumulativeFrameEndTimes.firstIndex {
            cyclePosition + epsilon < $0
        } ?? descriptor.frameCount - 1
        return FramePresentation(
            frameIndex: frameIndex,
            completedLoopCount: completedLoops,
            isComplete: false
        )
    }

    private func completedLoopCount(for position: TimeInterval, epsilon: TimeInterval) -> Int {
        let quotient = floor((max(0, position) + epsilon) / descriptor.cycleDuration)
        guard quotient.isFinite, quotient < TimeInterval(Int.max) else { return .max }
        return max(0, Int(quotient))
    }

    private mutating func accept(_ timestamp: TimeInterval) -> Bool {
        guard timestamp.isFinite else { return false }
        if let lastAcceptedTimestamp, timestamp < lastAcceptedTimestamp { return false }
        lastAcceptedTimestamp = timestamp
        return true
    }
}
