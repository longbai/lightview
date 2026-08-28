import Foundation

public enum AnimationPlaybackError: Error, Sendable, Equatable {
    case frameIndexMismatch(requested: Int, returned: Int)
}

public final class AnimationController {
    public let provider: any AnimationFrameProvider
    public let cacheByteLimit: Int

    public private(set) var currentFrameIndex = 0
    public private(set) var isComplete = false
    public var isPlaying: Bool { clock.isPlaying }
    public var speed: Double { clock.speed }
    public var cachedFrameIndices: Set<Int> { Set(cache.keys) }
    public var cachedByteCost: Int { totalByteCost }

    private var clock: FrameClock
    private var cache: [Int: AnimationFrame] = [:]
    private var priorFrameIndex: Int?
    private let cacheMutationObserver: ((Int, Int) -> Void)?
    private let cancellation: DecodeCancellation

    public init(
        provider: any AnimationFrameProvider,
        cacheByteLimit: Int,
        cancellation: DecodeCancellation = DecodeCancellation()
    ) {
        self.provider = provider
        self.cacheByteLimit = max(0, cacheByteLimit)
        self.cancellation = cancellation
        cacheMutationObserver = nil
        clock = FrameClock(descriptor: provider.descriptor)
    }

    init(
        provider: any AnimationFrameProvider,
        cacheByteLimit: Int,
        cancellation: DecodeCancellation = DecodeCancellation(),
        cacheMutationObserver: @escaping (Int, Int) -> Void
    ) {
        self.provider = provider
        self.cacheByteLimit = max(0, cacheByteLimit)
        self.cancellation = cancellation
        self.cacheMutationObserver = cacheMutationObserver
        clock = FrameClock(descriptor: provider.descriptor)
    }

    public func play(at timestamp: TimeInterval) {
        clock.play(at: timestamp)
    }

    public func pause(at timestamp: TimeInterval) {
        clock.pause(at: timestamp)
        apply(clock.advance(to: timestamp))
    }

    public func togglePlayback(at timestamp: TimeInterval) {
        if isPlaying { pause(at: timestamp) } else { play(at: timestamp) }
    }

    public func setSpeed(_ speed: Double, at timestamp: TimeInterval) {
        clock.setSpeed(speed, at: timestamp)
        apply(clock.advance(to: timestamp))
    }

    public func stepForward(at timestamp: TimeInterval) {
        pause(at: timestamp)
        clock.seek(toFrame: currentFrameIndex + 1, at: timestamp)
        apply(clock.advance(to: timestamp))
    }

    public func stepBackward(at timestamp: TimeInterval) {
        pause(at: timestamp)
        clock.seek(toFrame: currentFrameIndex - 1, at: timestamp)
        apply(clock.advance(to: timestamp))
    }

    @discardableResult
    public func advance(to timestamp: TimeInterval) throws -> AnimationFrame {
        apply(clock.advance(to: timestamp))
        let nextIndex = isComplete ? nil : (currentFrameIndex + 1) % provider.descriptor.frameCount
        retainWindow(current: currentFrameIndex, next: nextIndex, prior: priorFrameIndex)
        let current = try cachedOrLoad(index: currentFrameIndex, preserving: [])
        if let nextIndex {
            _ = try? cachedOrLoad(index: nextIndex, preserving: [currentFrameIndex])
        }
        return current
    }

    private func apply(_ presentation: FramePresentation) {
        if presentation.frameIndex != currentFrameIndex {
            priorFrameIndex = currentFrameIndex
        }
        currentFrameIndex = presentation.frameIndex
        isComplete = presentation.isComplete
    }

    private func cachedOrLoad(index: Int, preserving protectedIndices: Set<Int>) throws -> AnimationFrame {
        if let cached = cache[index] { return cached }
        try cancellation.throwIfCancelled()
        let frame = try provider.frame(at: index, cancellation: cancellation)
        guard frame.index == index else {
            throw AnimationPlaybackError.frameIndexMismatch(requested: index, returned: frame.index)
        }
        storeIfPossible(frame, preserving: protectedIndices)
        return frame
    }

    private func storeIfPossible(_ frame: AnimationFrame, preserving protectedIndices: Set<Int>) {
        let required = frame.decodedByteCost
        guard required > 0, cacheByteLimit > 0, required <= cacheByteLimit else { return }

        var evictionOrder: [Int] = []
        if let priorFrameIndex,
           priorFrameIndex != frame.index,
           !protectedIndices.contains(priorFrameIndex),
           cache[priorFrameIndex] != nil {
            evictionOrder.append(priorFrameIndex)
        }
        let prioritized = Set(evictionOrder)
        evictionOrder.append(contentsOf: cache.keys.sorted().filter {
            $0 != frame.index && !protectedIndices.contains($0) && !prioritized.contains($0)
        })

        for index in evictionOrder where totalByteCost > cacheByteLimit - required {
            removeCachedFrame(at: index)
        }
        guard totalByteCost <= cacheByteLimit - required else { return }
        cache[frame.index] = frame
        reportCacheMutation()
    }

    private func retainWindow(current: Int, next: Int?, prior: Int?) {
        var allowed = Set([current])
        if let next { allowed.insert(next) }
        if let prior { allowed.insert(prior) }
        for index in Array(cache.keys) where !allowed.contains(index) {
            removeCachedFrame(at: index)
        }

        if totalByteCost > cacheByteLimit, let prior, prior != current {
            removeCachedFrame(at: prior)
        }
        if totalByteCost > cacheByteLimit, let next, next != current {
            removeCachedFrame(at: next)
        }
        if totalByteCost > cacheByteLimit {
            for index in Array(cache.keys) where index != current {
                removeCachedFrame(at: index)
                if totalByteCost <= cacheByteLimit { break }
            }
        }
    }

    private func removeCachedFrame(at index: Int) {
        guard cache.removeValue(forKey: index) != nil else { return }
        reportCacheMutation()
    }

    private func reportCacheMutation() {
        cacheMutationObserver?(cache.count, totalByteCost)
    }

    private var totalByteCost: Int {
        cache.values.reduce(0) { partial, frame in
            let (sum, overflow) = partial.addingReportingOverflow(frame.decodedByteCost)
            return overflow ? .max : sum
        }
    }
}
