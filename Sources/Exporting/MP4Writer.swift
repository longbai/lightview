import AVFoundation
import Foundation

public final class MP4Writer: MovieWriting, @unchecked Sendable {
    private enum State { case ready, writing, finishing, finished }

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let queue = DispatchQueue(label: "app.lightview.mp4-writer", qos: .userInitiated)
    private let lock = NSLock()
    private var state: State = .ready
    private var completion: (@Sendable (Result<Void, MovieExportError>) -> Void)?

    public init(destination: URL, outputSize: CGSize, frameRate: Int32) throws {
        let width = Int(outputSize.width.rounded())
        let height = Int(outputSize.height.rounded())
        guard width > 0, height > 0, frameRate > 0 else {
            throw MovieExportError.invalidPlan("Invalid writer dimensions or frame rate")
        }
        writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: max(1_000_000, width * height * 4),
            AVVideoExpectedSourceFrameRateKey: frameRate,
            AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
        ]
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw MovieExportError.writerFailed("H.264 writer input is unavailable")
        }
        writer.add(input)
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
    }

    public func write(
        nextFrame: @escaping @Sendable () throws -> MovieFrame?,
        didAppend: @escaping @Sendable () -> Void,
        completion: @escaping @Sendable (Result<Void, MovieExportError>) -> Void
    ) {
        let canStart = lock.withLock {
            guard state == .ready else { return false }
            state = .writing
            self.completion = completion
            return true
        }
        guard canStart else {
            completion(.failure(.writerFailed("Writer was already started")))
            return
        }
        guard writer.startWriting() else {
            return fail(message: writer.error?.localizedDescription ?? "Could not start AVAssetWriter")
        }
        writer.startSession(atSourceTime: .zero)
        input.requestMediaDataWhenReady(on: queue) { [self] in
            while self.input.isReadyForMoreMediaData, self.isWriting {
                do {
                    guard let frame = try nextFrame() else {
                        self.finishWriting()
                        return
                    }
                    let appended = self.adaptor.append(
                        frame.lease.buffer,
                        withPresentationTime: frame.presentationTime
                    )
                    frame.lease.release()
                    guard appended else {
                        self.fail(message: self.writer.error?.localizedDescription ?? "Could not append video frame")
                        return
                    }
                    didAppend()
                } catch let error as MovieExportError {
                    self.fail(error: error)
                    return
                } catch {
                    self.fail(message: error.localizedDescription)
                    return
                }
            }
        }
    }

    public func cancel() {
        let callback: (@Sendable (Result<Void, MovieExportError>) -> Void)? = lock.withLock {
            guard state != .finished else { return nil }
            state = .finished
            defer { completion = nil }
            return completion
        }
        writer.cancelWriting()
        callback?(.failure(.cancelled))
    }

    private var isWriting: Bool { lock.withLock { state == .writing } }

    private func finishWriting() {
        let shouldFinish = lock.withLock {
            guard state == .writing else { return false }
            state = .finishing
            return true
        }
        guard shouldFinish else { return }
        input.markAsFinished()
        writer.finishWriting { [self] in
            if self.writer.status == .completed {
                self.complete(.success(()))
            } else {
                self.complete(.failure(.writerFailed(
                    self.writer.error?.localizedDescription ?? "AVAssetWriter did not complete"
                )))
            }
        }
    }

    private func fail(message: String) {
        fail(error: .writerFailed(message))
    }

    private func fail(error: MovieExportError) {
        writer.cancelWriting()
        complete(.failure(error))
    }

    private func complete(_ result: Result<Void, MovieExportError>) {
        let callback: (@Sendable (Result<Void, MovieExportError>) -> Void)? = lock.withLock {
            guard state != .finished else { return nil }
            state = .finished
            defer { completion = nil }
            return completion
        }
        callback?(result)
    }
}
