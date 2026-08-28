import Foundation

public final class MovieExportCoordinator: @unchecked Sendable {
    public typealias WriterFactory = @Sendable (URL, CGSize, Int32) throws -> any MovieWriting

    private let composer: ExportFrameComposer
    private let timelineBuilder: ExportTimelineBuilder
    private let callbackQueue: DispatchQueue
    private let writerFactory: WriterFactory

    public init(
        composer: ExportFrameComposer,
        timelineBuilder: ExportTimelineBuilder = ExportTimelineBuilder(),
        callbackQueue: DispatchQueue = .main,
        writerFactory: @escaping WriterFactory = { try MP4Writer(
            destination: $0,
            outputSize: $1,
            frameRate: $2
        ) }
    ) {
        self.composer = composer
        self.timelineBuilder = timelineBuilder
        self.callbackQueue = callbackQueue
        self.writerFactory = writerFactory
    }

    @discardableResult
    public func start(
        plan: MovieExportPlan,
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<Void, MovieExportError>) -> Void
    ) -> ExportCancellation {
        let cancellation = ExportCancellation()
        let temporaryURL = Self.temporaryURL(for: destination)
        do {
            let timeline = try timelineBuilder.build(plan)
            let pool = try PixelBufferPool(
                width: Int(plan.outputSize.width.rounded()),
                height: Int(plan.outputSize.height.rounded()),
                maximumBufferCount: 3
            )
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }
            let writer = try writerFactory(temporaryURL, plan.outputSize, plan.frameRate)
            cancellation.install { writer.cancel() }
            let cursor = ExportFrameCursor(timeline: timeline, pool: pool, composer: composer)
            writer.write(
                nextFrame: {
                    guard !cancellation.isCancelled else { throw MovieExportError.cancelled }
                    return try cursor.next()
                },
                didAppend: {
                    progress(cursor.progress)
                },
                completion: { [callbackQueue] result in
                    let finalResult = Self.finalize(
                        result: result,
                        temporaryURL: temporaryURL,
                        destination: destination
                    )
                    callbackQueue.async { completion(finalResult) }
                }
            )
        } catch let error as MovieExportError {
            try? FileManager.default.removeItem(at: temporaryURL)
            callbackQueue.async { completion(.failure(error)) }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            callbackQueue.async { completion(.failure(.writerFailed(error.localizedDescription))) }
        }
        return cancellation
    }

    public static func temporaryURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).lightview-export.tmp"
        )
    }

    private static func finalize(
        result: Result<Void, MovieExportError>,
        temporaryURL: URL,
        destination: URL
    ) -> Result<Void, MovieExportError> {
        switch result {
        case .failure(let error):
            try? FileManager.default.removeItem(at: temporaryURL)
            return .failure(error)
        case .success:
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporaryURL)
                } else {
                    try FileManager.default.moveItem(at: temporaryURL, to: destination)
                }
                return .success(())
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                return .failure(.writerFailed(error.localizedDescription))
            }
        }
    }
}

private final class ExportFrameCursor: @unchecked Sendable {
    private let lock = NSLock()
    private let timeline: ExportTimeline
    private let pool: PixelBufferPool
    private let composer: ExportFrameComposer
    private var index = 0

    init(timeline: ExportTimeline, pool: PixelBufferPool, composer: ExportFrameComposer) {
        self.timeline = timeline
        self.pool = pool
        self.composer = composer
    }

    var progress: Double {
        lock.withLock { timeline.isEmpty ? 1 : Double(index) / Double(timeline.count) }
    }

    func next() throws -> MovieFrame? {
        try lock.withLock {
            guard index < timeline.count else { return nil }
            guard let lease = pool.acquire() else {
                throw MovieExportError.writerFailed("Export pixel buffer pool is exhausted")
            }
            do {
                let instruction = timeline[index]
                try composer.compose(instruction, into: lease.buffer)
                index += 1
                return MovieFrame(lease: lease, presentationTime: instruction.presentationTime)
            } catch {
                lease.release()
                throw error
            }
        }
    }
}
