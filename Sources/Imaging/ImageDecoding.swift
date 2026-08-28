import CoreGraphics
import Foundation
import ImageIO

public struct ImageInspection: Sendable, Equatable {
    public let format: ImageFormat
    public let rawPixelSize: CGSize
    public let orientedPixelSize: CGSize
    public let orientation: CGImagePropertyOrientation
    public let frameCount: Int
    public let metadata: ImageMetadata

    public init(
        format: ImageFormat,
        rawPixelSize: CGSize,
        orientedPixelSize: CGSize,
        orientation: CGImagePropertyOrientation,
        frameCount: Int,
        metadata: ImageMetadata
    ) {
        self.format = format
        self.rawPixelSize = rawPixelSize
        self.orientedPixelSize = orientedPixelSize
        self.orientation = orientation
        self.frameCount = frameCount
        self.metadata = metadata
    }
}

public final class DecodeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    public func cancel() {
        lock.withLock { cancelled = true }
    }

    public func throwIfCancelled() throws {
        if isCancelled { throw ImageLoadError.cancelled }
    }
}

public protocol ImageDecoding: Sendable {
    func inspect(url: URL) throws -> ImageInspection
    func decode(_ request: DecodeRequest, cancellation: DecodeCancellation) throws -> RasterAsset
}
