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

public struct AnimationAsset: Sendable, Equatable {
    public let canvasPixelSize: CGSize
    public let frameCount: Int
    public let loopCount: Int?
    public let frameDurations: [TimeInterval]

    public init(
        canvasPixelSize: CGSize,
        frameCount: Int,
        loopCount: Int?,
        frameDurations: [TimeInterval]
    ) {
        self.canvasPixelSize = canvasPixelSize
        self.frameCount = frameCount
        self.loopCount = loopCount
        self.frameDurations = frameDurations
    }
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

public enum ImageLoadError: Error, Sendable, Equatable {
    case missing(URL)
    case accessDenied(URL)
    case unsupported(ImageFormat)
    case corrupt(URL)
    case cancelled
    case unsafeExternalResource(URL)
    case sourceTooLarge(actual: Int, limit: Int)
    case decodeFailed(String)
}
