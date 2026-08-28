import CoreGraphics
import Foundation
import ImageIO

public enum ImageFormat: String, CaseIterable, Sendable {
    case jpeg
    case png
    case gif
    case tiff
    case bmp
    case ico
    case jpeg2000
    case heif
    case webP
    case svg
    case avif
    case unknown
}

public struct ImageMetadata: Sendable, Equatable {
    public let pixelSize: CGSize
    public let dpi: CGSize?
    public let bitDepth: Int?
    public let colorModel: String?
    public let colorProfileDescription: String?
    public let fileByteCount: Int64?
    public let properties: [String: String]

    public init(
        pixelSize: CGSize,
        dpi: CGSize? = nil,
        bitDepth: Int? = nil,
        colorModel: String? = nil,
        colorProfileDescription: String? = nil,
        fileByteCount: Int64? = nil,
        properties: [String: String] = [:]
    ) {
        self.pixelSize = pixelSize
        self.dpi = dpi
        self.bitDepth = bitDepth
        self.colorModel = colorModel
        self.colorProfileDescription = colorProfileDescription
        self.fileByteCount = fileByteCount
        self.properties = properties
    }
}

public struct DecodeRequest: Sendable, Equatable {
    public let url: URL
    public let targetPixelSize: CGSize
    public let requiresFullResolution: Bool
    public let generation: UInt64

    public init(
        url: URL,
        targetPixelSize: CGSize,
        requiresFullResolution: Bool,
        generation: UInt64
    ) {
        self.url = url
        self.targetPixelSize = targetPixelSize
        self.requiresFullResolution = requiresFullResolution
        self.generation = generation
    }
}

public struct RasterAsset: @unchecked Sendable {
    public let image: CGImage
    public let originalPixelSize: CGSize
    public let decodedPixelSize: CGSize
    public let orientation: CGImagePropertyOrientation
    public let metadata: ImageMetadata
    public let decodedByteCost: Int
    public let format: ImageFormat
    public let frameCount: Int

    public init(
        image: CGImage,
        originalPixelSize: CGSize,
        decodedPixelSize: CGSize,
        orientation: CGImagePropertyOrientation,
        metadata: ImageMetadata,
        decodedByteCost: Int,
        format: ImageFormat = .unknown,
        frameCount: Int = 1
    ) {
        self.image = image
        self.originalPixelSize = originalPixelSize
        self.decodedPixelSize = decodedPixelSize
        self.orientation = orientation
        self.metadata = metadata
        self.decodedByteCost = decodedByteCost
        self.format = format
        self.frameCount = max(1, frameCount)
    }
}

public struct AnimationDescriptor: Sendable, Equatable {
    public let canvasPixelSize: CGSize
    public let frameDurations: [TimeInterval]
    public let cumulativeFrameEndTimes: [TimeInterval]
    public let loopCount: Int?

    public var frameCount: Int { frameDurations.count }
    public var cycleDuration: TimeInterval { cumulativeFrameEndTimes.last ?? 0.10 }

    public init(
        canvasPixelSize: CGSize,
        frameDurations: [TimeInterval],
        loopCount: Int?
    ) {
        let width = canvasPixelSize.width.isFinite && canvasPixelSize.width > 0 ? canvasPixelSize.width : 1
        let height = canvasPixelSize.height.isFinite && canvasPixelSize.height > 0 ? canvasPixelSize.height : 1
        self.canvasPixelSize = CGSize(width: width, height: height)
        let sourceDurations = frameDurations.isEmpty ? [0.10] : frameDurations
        self.frameDurations = sourceDurations.map { duration in
            guard duration.isFinite, duration > 0 else { return 0.10 }
            return min(60, max(0.01, duration))
        }
        var total: TimeInterval = 0
        cumulativeFrameEndTimes = self.frameDurations.map { duration in
            total += duration
            return total
        }
        self.loopCount = loopCount.map { max(1, $0) }
    }
}

public struct AnimationFrame: @unchecked Sendable {
    public let index: Int
    public let image: CGImage
    public let decodedByteCost: Int

    public init(index: Int, image: CGImage, decodedByteCost: Int) {
        self.index = index
        self.image = image
        self.decodedByteCost = max(0, decodedByteCost)
    }
}

public protocol AnimationFrameProvider: Sendable {
    var descriptor: AnimationDescriptor { get }
    func frame(at index: Int) throws -> AnimationFrame
    func frame(at index: Int, cancellation: DecodeCancellation) throws -> AnimationFrame
}

public extension AnimationFrameProvider {
    func frame(at index: Int, cancellation: DecodeCancellation) throws -> AnimationFrame {
        try cancellation.throwIfCancelled()
        return try frame(at: index)
    }
}

public struct AnimationAsset: Sendable {
    public let descriptor: AnimationDescriptor
    public let provider: any AnimationFrameProvider
    public let format: ImageFormat
    public let metadata: ImageMetadata

    public init(
        provider: any AnimationFrameProvider,
        format: ImageFormat = .unknown,
        metadata: ImageMetadata? = nil
    ) {
        descriptor = provider.descriptor
        self.provider = provider
        self.format = format
        self.metadata = metadata ?? ImageMetadata(pixelSize: provider.descriptor.canvasPixelSize)
    }

    public var canvasPixelSize: CGSize { descriptor.canvasPixelSize }
    public var frameCount: Int { descriptor.frameCount }
    public var loopCount: Int? { descriptor.loopCount }
    public var frameDurations: [TimeInterval] { descriptor.frameDurations }
}

public struct VectorAsset: Sendable, Equatable {
    public let intrinsicPixelSize: CGSize?
    public let sourceByteCount: Int

    public init(intrinsicPixelSize: CGSize?, sourceByteCount: Int) {
        self.intrinsicPixelSize = intrinsicPixelSize
        self.sourceByteCount = sourceByteCount
    }
}

public enum DisplayAsset: Sendable {
    case raster(RasterAsset)
    case animation(AnimationAsset)
    case vector(VectorAsset)
}

public extension DisplayAsset {
    var format: ImageFormat {
        switch self {
        case .raster(let asset): asset.format
        case .animation(let asset): asset.format
        case .vector: .svg
        }
    }

    var frameCount: Int {
        switch self {
        case .raster(let asset): asset.frameCount
        case .animation(let asset): asset.frameCount
        case .vector: 1
        }
    }

    var metadata: ImageMetadata {
        switch self {
        case .raster(let asset): asset.metadata
        case .animation(let asset): asset.metadata
        case .vector(let asset):
            ImageMetadata(
                pixelSize: asset.intrinsicPixelSize ?? .zero,
                fileByteCount: Int64(asset.sourceByteCount)
            )
        }
    }

    var raster: RasterAsset? {
        guard case let .raster(asset) = self else { return nil }
        return asset
    }
}

public enum ImageLoadError: Error, Sendable, Equatable {
    case missing(URL)
    case accessDenied(URL)
    case unsupported(ImageFormat)
    case corrupt(URL)
    case cancelled
    case unsafeExternalResource(URL)
    case sourceTooLarge(actual: Int, limit: Int)
    case decodedImageTooLarge(required: Int, limit: Int)
    case allocationFailed(required: Int)
    case decodeFailed(String)
}
