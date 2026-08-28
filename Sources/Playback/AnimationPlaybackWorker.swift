import Foundation

public enum AnimationPlaybackCommand: Sendable, Equatable {
    case play
    case pause
    case toggle
    case stepForward
    case stepBackward
    case setSpeed(Double)
}

public struct AnimationPlaybackSnapshot: @unchecked Sendable {
    public let frame: AnimationFrame
    public let isPlaying: Bool
    public let isComplete: Bool
    public let speed: Double
}

public final class AnimationPlaybackWorker: @unchecked Sendable {
    public typealias Completion = @Sendable (Result<AnimationPlaybackSnapshot, Error>) -> Void

    private struct AdvanceRequest {
        let timestamp: TimeInterval
        let completion: Completion
    }

    private let controller: AnimationController
    private let workQueue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private let cancellation: DecodeCancellation
    private let stateLock = NSLock()
    private var pendingAdvance: AdvanceRequest?
    private var isAdvanceScheduled = false
    private var isCancelled = false

    public init(
        provider: any AnimationFrameProvider,
        cacheByteLimit: Int,
        callbackQueue: DispatchQueue = .main
    ) {
        let cancellation = DecodeCancellation()
        self.cancellation = cancellation
        controller = AnimationController(
            provider: provider,
            cacheByteLimit: cacheByteLimit,
            cancellation: cancellation
        )
        workQueue = DispatchQueue(label: "app.lightview.animation-playback", qos: .userInitiated)
        self.callbackQueue = callbackQueue
    }

    public func advance(to timestamp: TimeInterval, completion: @escaping Completion) {
        let shouldSchedule = stateLock.withLock { () -> Bool in
            guard !isCancelled else { return false }
            pendingAdvance = AdvanceRequest(timestamp: timestamp, completion: completion)
            guard !isAdvanceScheduled else { return false }
            isAdvanceScheduled = true
            return true
        }
        if shouldSchedule { scheduleNextAdvance() }
    }

    public func perform(
        _ command: AnimationPlaybackCommand,
        at timestamp: TimeInterval,
        completion: @escaping Completion
    ) {
        guard stateLock.withLock({ !isCancelled }) else { return }
        workQueue.async { [weak self] in
            guard let self, !self.stateLock.withLock({ self.isCancelled }) else { return }
            do {
                switch command {
                case .play: self.controller.play(at: timestamp)
                case .pause: self.controller.pause(at: timestamp)
                case .toggle: self.controller.togglePlayback(at: timestamp)
                case .stepForward: self.controller.stepForward(at: timestamp)
                case .stepBackward: self.controller.stepBackward(at: timestamp)
                case .setSpeed(let speed): self.controller.setSpeed(speed, at: timestamp)
                }
                self.deliver(.success(try self.makeSnapshot(at: timestamp)), completion: completion)
            } catch {
                self.deliver(.failure(error), completion: completion)
            }
        }
    }

    public func cancel() {
        cancellation.cancel()
        stateLock.withLock {
            isCancelled = true
            pendingAdvance = nil
        }
    }

    private func scheduleNextAdvance() {
        workQueue.async { [weak self] in self?.processOneAdvance() }
    }

    private func processOneAdvance() {
        guard let request = stateLock.withLock({ () -> AdvanceRequest? in
            guard !isCancelled else {
                isAdvanceScheduled = false
                return nil
            }
            let request = pendingAdvance
            pendingAdvance = nil
            return request
        }) else { return }

        do {
            deliver(.success(try makeSnapshot(at: request.timestamp)), completion: request.completion)
        } catch {
            deliver(.failure(error), completion: request.completion)
        }

        let hasNext = stateLock.withLock { () -> Bool in
            guard !isCancelled, pendingAdvance != nil else {
                isAdvanceScheduled = false
                return false
            }
            return true
        }
        if hasNext { scheduleNextAdvance() }
    }

    private func makeSnapshot(at timestamp: TimeInterval) throws -> AnimationPlaybackSnapshot {
        AnimationPlaybackSnapshot(
            frame: try controller.advance(to: timestamp),
            isPlaying: controller.isPlaying,
            isComplete: controller.isComplete,
            speed: controller.speed
        )
    }

    private func deliver(_ result: Result<AnimationPlaybackSnapshot, Error>, completion: @escaping Completion) {
        callbackQueue.async { [weak self] in
            guard let self, !self.stateLock.withLock({ self.isCancelled }) else { return }
            completion(result)
        }
    }
}
