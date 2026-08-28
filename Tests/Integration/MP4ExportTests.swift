import AVFoundation
import XCTest
@testable import LightViewCore

final class MP4ExportTests: XCTestCase {
    func testExportsTwoSecondSilentH264MovieAt480p() async throws {
        guard #available(macOS 12.0, *) else { throw XCTSkip("Modern AVAsset inspection requires macOS 12") }
        let images = [try solidImage(red: 255, blue: 0), try solidImage(red: 0, blue: 255)]
        let plan = MovieExportPlan(
            outputSize: CGSize(width: 640, height: 480),
            frameRate: 30,
            sources: [.still(identifier: "red"), .still(identifier: "blue")],
            staticDuration: CMTime(seconds: 1, preferredTimescale: 600),
            transition: .none,
            animationDurationPolicy: .oneLoop
        )
        let composer = ExportFrameComposer(
            outputSize: plan.outputSize,
            composition: .fit,
            transition: plan.transition,
            background: .solid(.black),
            sourceImage: { index, _ in images[index] }
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = LockedExportResult()
        let finished = expectation(description: "movie export finished")

        _ = MovieExportCoordinator(composer: composer).start(
            plan: plan,
            destination: destination,
            progress: { _ in },
            completion: {
                result.value = $0
                finished.fulfill()
            }
        )
        await fulfillment(of: [finished], timeout: 15)
        try result.value?.get()

        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertGreaterThan(attributes[.size] as? Int ?? 0, 0)
        let asset = AVURLAsset(url: destination)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertTrue(audioTracks.isEmpty)
        let size = try await videoTracks[0].load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 640, height: 480))
        let descriptions = try await videoTracks[0].load(.formatDescriptions)
        XCTAssertEqual(
            descriptions.first.map(CMFormatDescriptionGetMediaSubType),
            kCMVideoCodecType_H264
        )
        let duration = try await asset.load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(duration), 2, accuracy: 1.0 / 30.0)
    }

    func testCancellationRemovesOperationTemporaryOutput() async throws {
        let image = try solidImage(red: 255, blue: 0)
        let plan = MovieExportPlan(
            outputSize: CGSize(width: 640, height: 480),
            frameRate: 30,
            sources: [.still(identifier: "red")],
            staticDuration: CMTime(seconds: 10, preferredTimescale: 600),
            transition: .none,
            animationDurationPolicy: .oneLoop
        )
        let composer = ExportFrameComposer(
            outputSize: plan.outputSize,
            composition: .fit,
            transition: .none,
            background: .solid(.black),
            sourceImage: { _, _ in image }
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let finished = expectation(description: "cancelled export finished")
        let result = LockedExportResult()
        let cancellationBox = LockedCancellation()
        cancellationBox.value = MovieExportCoordinator(composer: composer).start(
            plan: plan,
            destination: destination,
            progress: { progress in
                if progress > 0.1 { cancellationBox.value?.cancel() }
            },
            completion: {
                result.value = $0
                finished.fulfill()
            }
        )

        await fulfillment(of: [finished], timeout: 15)
        XCTAssertEqual(result.error, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: MovieExportCoordinator.temporaryURL(for: destination).path))
    }

    func testWriterFailurePreservesExistingDestination() async throws {
        let image = try solidImage(red: 255, blue: 0)
        let plan = MovieExportPlan(
            outputSize: CGSize(width: 640, height: 480),
            frameRate: 30,
            sources: [.still(identifier: "red")],
            staticDuration: CMTime(seconds: 1, preferredTimescale: 600),
            transition: .none,
            animationDurationPolicy: .oneLoop
        )
        let composer = ExportFrameComposer(
            outputSize: plan.outputSize,
            composition: .fit,
            transition: .none,
            background: .solid(.black),
            sourceImage: { _, _ in image }
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let original = Data("original destination".utf8)
        try original.write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }
        let finished = expectation(description: "failed export finished")
        let result = LockedExportResult()
        let coordinator = MovieExportCoordinator(
            composer: composer,
            writerFactory: { _, _, _ in FailingMovieWriter() }
        )

        _ = coordinator.start(
            plan: plan,
            destination: destination,
            progress: { _ in },
            completion: {
                result.value = $0
                finished.fulfill()
            }
        )

        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(result.error, .writerFailed("injected failure"))
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: MovieExportCoordinator.temporaryURL(for: destination).path))
    }

    private func solidImage(red: UInt8, blue: UInt8) throws -> CGImage {
        let bytes: [UInt8] = [red, 0, blue, 255]
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { throw MovieExportError.invalidPlan("Could not create export fixture") }
        return image
    }
}

private final class LockedExportResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<Void, MovieExportError>?

    var value: Result<Void, MovieExportError>? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    var error: MovieExportError? {
        guard case .failure(let error) = value else { return nil }
        return error
    }
}

private final class LockedCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ExportCancellation?

    var value: ExportCancellation? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private final class FailingMovieWriter: MovieWriting, @unchecked Sendable {
    func write(
        nextFrame: @escaping @Sendable () throws -> MovieFrame?,
        didAppend: @escaping @Sendable () -> Void,
        completion: @escaping @Sendable (Result<Void, MovieExportError>) -> Void
    ) {
        completion(.failure(.writerFailed("injected failure")))
    }

    func cancel() {}
}
