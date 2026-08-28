import CoreGraphics
import Foundation
import XCTest
@testable import LightViewCore

final class ViewingSessionTests: XCTestCase {
    @MainActor
    func testLateResultCannotReplaceNewerImage() async throws {
        let loader = ControlledImageLoader()
        let session = ViewingSession(loader: loader)
        let firstURL = URL(fileURLWithPath: "/tmp/first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/second.png")

        session.open(firstURL)
        let firstGeneration = session.generation
        session.open(secondURL)
        let secondGeneration = session.generation

        loader.complete(generation: secondGeneration, with: .success(try makeSessionAsset(cost: 8)))
        await Task.yield()
        XCTAssertEqual(session.currentURL, secondURL)
        XCTAssertNotNil(session.currentAsset)

        loader.complete(generation: firstGeneration, with: .success(try makeSessionAsset(cost: 8)))
        await Task.yield()
        XCTAssertEqual(session.currentURL, secondURL)
        XCTAssertEqual(session.generation, secondGeneration)
    }

    @MainActor
    func testNavigationWrapsOnlyWhenEnabled() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightViewSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("1.png")
        let secondURL = directory.appendingPathComponent("2.png")
        try Data().write(to: firstURL)
        try Data().write(to: secondURL)

        let loader = ControlledImageLoader()
        let session = ViewingSession(loader: loader)
        session.catalog = try FolderCatalog(directoryURL: directory)
        session.open(secondURL)
        let requestCountAtEnd = loader.requestCount

        session.navigationWraps = false
        session.navigate(.next)
        XCTAssertEqual(loader.requestCount, requestCountAtEnd)

        session.navigationWraps = true
        session.navigate(.next)
        XCTAssertEqual(loader.lastRequest?.url, firstURL)
    }
}

private final class ControlledImageLoader: ImageLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [DecodeRequest] = []
    private var completions: [UInt64: @Sendable (Result<RasterAsset, ImageLoadError>) -> Void] = [:]

    var requestCount: Int { lock.withLock { requests.count } }
    var lastRequest: DecodeRequest? { lock.withLock { requests.last } }

    func load(
        _ request: DecodeRequest,
        completion: @escaping @Sendable (Result<RasterAsset, ImageLoadError>) -> Void
    ) -> DecodeCancellation {
        lock.withLock {
            requests.append(request)
            completions[request.generation] = completion
        }
        return DecodeCancellation()
    }

    func complete(generation: UInt64, with result: Result<RasterAsset, ImageLoadError>) {
        let completion = lock.withLock { completions.removeValue(forKey: generation) }
        completion?(result)
    }
}

private func makeSessionAsset(cost: Int) throws -> RasterAsset {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let image = context.makeImage() else {
        throw ImageLoadError.decodeFailed("Unable to make session test image")
    }
    let size = CGSize(width: 1, height: 1)
    return RasterAsset(
        image: image,
        originalPixelSize: size,
        decodedPixelSize: size,
        orientation: .up,
        metadata: ImageMetadata(pixelSize: size),
        decodedByteCost: cost
    )
}
