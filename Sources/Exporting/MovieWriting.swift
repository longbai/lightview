import AVFoundation
import CoreVideo
import Foundation

public struct MovieFrame: @unchecked Sendable {
    public let lease: PixelBufferLease
    public let presentationTime: CMTime

    public init(lease: PixelBufferLease, presentationTime: CMTime) {
        self.lease = lease
        self.presentationTime = presentationTime
    }
}

public protocol MovieWriting: Sendable {
    func write(
        nextFrame: @escaping @Sendable () throws -> MovieFrame?,
        didAppend: @escaping @Sendable () -> Void,
        completion: @escaping @Sendable (Result<Void, MovieExportError>) -> Void
    )
    func cancel()
}

public final class ExportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var cancellationAction: (() -> Void)?

    public init() {}

    public var isCancelled: Bool { lock.withLock { cancelled } }

    public func cancel() {
        let action: (() -> Void)? = lock.withLock {
            guard !cancelled else { return nil }
            cancelled = true
            defer { cancellationAction = nil }
            return cancellationAction
        }
        action?()
    }

    func install(_ action: @escaping () -> Void) {
        let runImmediately = lock.withLock {
            guard !cancelled else { return true }
            cancellationAction = action
            return false
        }
        if runImmediately { action() }
    }
}
