import XCTest
@testable import LightViewCore

final class SlideshowControllerTests: XCTestCase {
    func testForwardAndReverseSlideshowsNavigateAndRescheduleOneTimer() throws {
        let scheduler = ManualSlideshowScheduler()
        let recorder = DirectionRecorder()
        let controller = SlideshowController(scheduler: scheduler) {
            recorder.append($0)
            return true
        }

        try controller.start(direction: .next, interval: 2)
        XCTAssertEqual(controller.state, .running)
        XCTAssertEqual(scheduler.activeTimerCount, 1)
        scheduler.fireNext()
        XCTAssertEqual(recorder.values, [.next])
        XCTAssertEqual(scheduler.activeTimerCount, 1)

        try controller.start(direction: .previous, interval: 3)
        XCTAssertEqual(scheduler.activeTimerCount, 1)
        scheduler.fireNext()
        XCTAssertEqual(recorder.values, [.next, .previous])
        XCTAssertEqual(scheduler.scheduledIntervals.suffix(2), [3, 3])
    }

    func testPauseResumeAndRepeatedResumeNeverDuplicateTimers() throws {
        let scheduler = ManualSlideshowScheduler()
        let controller = SlideshowController(scheduler: scheduler) { _ in true }
        try controller.start(direction: .next, interval: 5)

        controller.pause()
        XCTAssertEqual(controller.state, .paused)
        XCTAssertEqual(scheduler.activeTimerCount, 0)

        controller.resume()
        controller.resume()
        XCTAssertEqual(controller.state, .running)
        XCTAssertEqual(scheduler.activeTimerCount, 1)
    }

    func testStopAndManualNavigationCancelPendingTimer() throws {
        let scheduler = ManualSlideshowScheduler()
        let recorder = DirectionRecorder()
        let controller = SlideshowController(scheduler: scheduler) {
            recorder.append($0)
            return true
        }
        try controller.start(direction: .next, interval: 1)

        controller.manualNavigationOccurred()
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertEqual(scheduler.activeTimerCount, 0)
        scheduler.fireNext()
        XCTAssertTrue(recorder.values.isEmpty)

        try controller.start(direction: .next, interval: 1)
        controller.stop()
        XCTAssertEqual(scheduler.activeTimerCount, 0)
    }

    func testIntervalValidationDoesNotReplaceExistingRun() throws {
        let scheduler = ManualSlideshowScheduler()
        let controller = SlideshowController(scheduler: scheduler) { _ in true }
        try controller.start(direction: .next, interval: 5)

        for invalid in [0, 0.5, 3_601, .infinity, .nan] {
            XCTAssertThrowsError(try controller.start(direction: .next, interval: invalid)) { error in
                XCTAssertEqual(error as? SlideshowError, .invalidInterval)
            }
        }
        XCTAssertEqual(controller.state, .running)
        XCTAssertEqual(scheduler.activeTimerCount, 1)
    }

    func testReachingNonWrappingCatalogEndStopsSlideshow() throws {
        let scheduler = ManualSlideshowScheduler()
        let controller = SlideshowController(scheduler: scheduler) { _ in false }

        try controller.start(direction: .next, interval: 1)
        scheduler.fireNext()

        XCTAssertEqual(controller.state, .stopped)
        XCTAssertEqual(scheduler.activeTimerCount, 0)
    }

    func testSynchronousSchedulerCallbackDoesNotDeadlockOrInstallSpentTask() throws {
        let scheduler = SynchronousSlideshowScheduler()
        let recorder = DirectionRecorder()
        let controller = SlideshowController(scheduler: scheduler) {
            recorder.append($0)
            return true
        }

        try controller.start(direction: .next, interval: 1)

        XCTAssertEqual(recorder.values, [.next])
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertEqual(scheduler.cancelCount, 1)
    }

    func testCancelledStaleCallbackCannotNavigateAfterStop() throws {
        let scheduler = ManualSlideshowScheduler()
        let recorder = DirectionRecorder()
        let controller = SlideshowController(scheduler: scheduler) {
            recorder.append($0)
            return true
        }
        try controller.start(direction: .next, interval: 1)

        controller.stop()
        scheduler.fireFirstIncludingCancelled()

        XCTAssertTrue(recorder.values.isEmpty)
        XCTAssertEqual(controller.state, .stopped)
    }

    func testSessionWrappingPreferenceIsUsedByNavigationClosure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightViewSlideshowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("1.png")
        let secondURL = directory.appendingPathComponent("2.png")
        try Data().write(to: firstURL)
        try Data().write(to: secondURL)

        let loader = SlideshowImageLoader()
        let session = ViewingSession(loader: loader)
        session.catalog = try FolderCatalog(directoryURL: directory)
        session.navigationWraps = true
        session.open(secondURL)
        let scheduler = ManualSlideshowScheduler()
        let controller = SlideshowController(scheduler: scheduler) { session.navigate($0) }

        try controller.start(direction: .next, interval: 1)
        scheduler.fireNext()
        XCTAssertEqual(loader.lastURL, firstURL)
    }
}

private final class DirectionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [CatalogDirection] = []

    var values: [CatalogDirection] { lock.withLock { stored } }
    func append(_ direction: CatalogDirection) { lock.withLock { stored.append(direction) } }
}

private final class ManualSlideshowScheduler: SlideshowScheduling, @unchecked Sendable {
    private final class Task: SlideshowScheduledTask, @unchecked Sendable {
        var isCancelled = false
        let action: @Sendable () -> Void

        init(action: @escaping @Sendable () -> Void) { self.action = action }
        func cancel() { isCancelled = true }
    }

    private var tasks: [Task] = []
    private(set) var scheduledIntervals: [TimeInterval] = []
    var activeTimerCount: Int { tasks.filter { !$0.isCancelled }.count }

    func schedule(after interval: TimeInterval, action: @escaping @Sendable () -> Void) -> any SlideshowScheduledTask {
        scheduledIntervals.append(interval)
        let task = Task(action: action)
        tasks.append(task)
        return task
    }

    func fireNext() {
        guard let index = tasks.firstIndex(where: { !$0.isCancelled }) else { return }
        let task = tasks.remove(at: index)
        task.action()
    }

    func fireFirstIncludingCancelled() {
        guard !tasks.isEmpty else { return }
        tasks.removeFirst().action()
    }
}

private final class SynchronousSlideshowScheduler: SlideshowScheduling, @unchecked Sendable {
    private final class Task: SlideshowScheduledTask, @unchecked Sendable {
        let onCancel: @Sendable () -> Void
        init(onCancel: @escaping @Sendable () -> Void) { self.onCancel = onCancel }
        func cancel() { onCancel() }
    }

    private let lock = NSLock()
    private var storedCancelCount = 0
    var cancelCount: Int { lock.withLock { storedCancelCount } }

    func schedule(after interval: TimeInterval, action: @escaping @Sendable () -> Void) -> any SlideshowScheduledTask {
        action()
        return Task { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.storedCancelCount += 1 }
        }
    }
}

private final class SlideshowImageLoader: ImageLoading, @unchecked Sendable {
    private(set) var lastURL: URL?

    func load(
        _ request: DecodeRequest,
        completion: @escaping @Sendable (Result<DisplayAsset, ImageLoadError>) -> Void
    ) -> DecodeCancellation {
        lastURL = request.url
        return DecodeCancellation()
    }
}
