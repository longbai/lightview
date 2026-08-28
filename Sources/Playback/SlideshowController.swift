import Foundation

public enum SlideshowState: Sendable, Equatable {
    case stopped
    case running
    case paused
}

public enum SlideshowError: Error, Sendable, Equatable {
    case invalidInterval
}

public protocol SlideshowScheduledTask: AnyObject, Sendable {
    func cancel()
}

public protocol SlideshowScheduling: Sendable {
    func schedule(
        after interval: TimeInterval,
        action: @escaping @Sendable () -> Void
    ) -> any SlideshowScheduledTask
}

public final class DispatchSlideshowScheduler: SlideshowScheduling, @unchecked Sendable {
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    public func schedule(
        after interval: TimeInterval,
        action: @escaping @Sendable () -> Void
    ) -> any SlideshowScheduledTask {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval)
        source.setEventHandler(handler: action)
        let task = DispatchSlideshowTask(source: source)
        source.resume()
        return task
    }
}

private final class DispatchSlideshowTask: SlideshowScheduledTask, @unchecked Sendable {
    private let lock = NSLock()
    private var source: DispatchSourceTimer?

    init(source: DispatchSourceTimer) {
        self.source = source
    }

    func cancel() {
        let source = lock.withLock { () -> DispatchSourceTimer? in
            defer { self.source = nil }
            return self.source
        }
        source?.setEventHandler {}
        source?.cancel()
    }

    deinit { cancel() }
}

public final class SlideshowController: @unchecked Sendable {
    public typealias Navigation = @Sendable (CatalogDirection) -> Bool

    private static let validInterval = 1.0...3_600.0
    private let scheduler: any SlideshowScheduling
    private let navigation: Navigation
    private let lock = NSLock()
    private let transitionGate = NSRecursiveLock()
    private var timer: (any SlideshowScheduledTask)?
    private var schedulingGeneration: UInt64?
    private var storedState: SlideshowState = .stopped
    private var direction: CatalogDirection = .next
    private var interval: TimeInterval = 5
    private var generation: UInt64 = 0

    public init(
        scheduler: any SlideshowScheduling = DispatchSlideshowScheduler(),
        navigation: @escaping Navigation
    ) {
        self.scheduler = scheduler
        self.navigation = navigation
    }

    public var state: SlideshowState { lock.withLock { storedState } }
    public var activeDirection: CatalogDirection? {
        lock.withLock { storedState == .stopped ? nil : direction }
    }

    public func start(direction: CatalogDirection, interval: TimeInterval) throws {
        guard interval.isFinite, Self.validInterval.contains(interval) else {
            throw SlideshowError.invalidInterval
        }
        transitionGate.lock()
        let transition = lock.withLock { () -> (task: (any SlideshowScheduledTask)?, generation: UInt64) in
            generation &+= 1
            let oldTask = timer
            timer = nil
            schedulingGeneration = nil
            self.direction = direction
            self.interval = interval
            storedState = .running
            return (oldTask, generation)
        }
        transitionGate.unlock()
        transition.task?.cancel()
        requestSchedule(generation: transition.generation)
    }

    public func pause() {
        transitionGate.lock()
        let oldTask = lock.withLock { () -> (any SlideshowScheduledTask)? in
            guard storedState == .running else { return nil }
            generation &+= 1
            let oldTask = timer
            timer = nil
            schedulingGeneration = nil
            storedState = .paused
            return oldTask
        }
        transitionGate.unlock()
        oldTask?.cancel()
    }

    public func resume() {
        transitionGate.lock()
        let resumedGeneration = lock.withLock { () -> UInt64? in
            guard storedState == .paused else { return nil }
            generation &+= 1
            storedState = .running
            return generation
        }
        transitionGate.unlock()
        if let resumedGeneration { requestSchedule(generation: resumedGeneration) }
    }

    public func stop() {
        transitionGate.lock()
        let oldTask = lock.withLock { () -> (any SlideshowScheduledTask)? in
            generation &+= 1
            let oldTask = timer
            timer = nil
            schedulingGeneration = nil
            storedState = .stopped
            return oldTask
        }
        transitionGate.unlock()
        oldTask?.cancel()
    }

    public func manualNavigationOccurred() {
        stop()
    }

    private func requestSchedule(generation expectedGeneration: UInt64) {
        guard let requestedInterval = lock.withLock({ () -> TimeInterval? in
            guard generation == expectedGeneration, storedState == .running,
                  timer == nil, schedulingGeneration == nil else { return nil }
            schedulingGeneration = expectedGeneration
            return interval
        }) else { return }

        let attempt = SlideshowScheduleAttempt()
        let newTask = scheduler.schedule(after: requestedInterval) { [weak self, attempt] in
            attempt.markFired()
            self?.timerFired(generation: expectedGeneration)
        }

        transitionGate.lock()
        let shouldCancel = lock.withLock { () -> Bool in
            if schedulingGeneration == expectedGeneration { schedulingGeneration = nil }
            guard generation == expectedGeneration, storedState == .running,
                  timer == nil, !attempt.didFire else {
                if generation == expectedGeneration, storedState == .running, attempt.didFire {
                    generation &+= 1
                    storedState = .stopped
                }
                return true
            }
            timer = newTask
            return false
        }
        transitionGate.unlock()
        if shouldCancel { newTask.cancel() }
    }

    private func timerFired(generation expectedGeneration: UInt64) {
        transitionGate.lock()
        guard let transition = lock.withLock({ () -> (CatalogDirection, (any SlideshowScheduledTask)?)? in
            guard generation == expectedGeneration, storedState == .running else { return nil }
            let firedTask = timer
            timer = nil
            return (direction, firedTask)
        }) else {
            transitionGate.unlock()
            return
        }

        let didNavigate = navigation(transition.0)
        let shouldReschedule = lock.withLock { () -> Bool in
            guard generation == expectedGeneration, storedState == .running else { return false }
            if !didNavigate {
                generation &+= 1
                storedState = .stopped
                schedulingGeneration = nil
                return false
            }
            return true
        }
        transitionGate.unlock()

        transition.1?.cancel()
        if shouldReschedule { requestSchedule(generation: expectedGeneration) }
    }
}

private final class SlideshowScheduleAttempt: @unchecked Sendable {
    private let lock = NSLock()
    private var storedDidFire = false

    var didFire: Bool { lock.withLock { storedDidFire } }
    func markFired() { lock.withLock { storedDidFire = true } }
}
