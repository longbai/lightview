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

public struct ImageEXIFMetadata: Sendable, Equatable {
    public let capturedAt: String?
    public let cameraMake: String?
    public let cameraModel: String?
    public let lensModel: String?
    public let focalLengthMM: Double?
    public let focalLength35MM: Int?
    public let aperture: Double?
    public let exposureTimeSeconds: Double?
    public let iso: Int?
    public let exposureBiasEV: Double?
    public let meteringMode: Int?
    public let whiteBalance: Int?
    public let flash: Int?
    public let software: String?
    public let latitude: Double?
    public let longitude: Double?

    public init(
        capturedAt: String? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        focalLengthMM: Double? = nil,
        focalLength35MM: Int? = nil,
        aperture: Double? = nil,
        exposureTimeSeconds: Double? = nil,
        iso: Int? = nil,
        exposureBiasEV: Double? = nil,
        meteringMode: Int? = nil,
        whiteBalance: Int? = nil,
        flash: Int? = nil,
        software: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.capturedAt = capturedAt
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.focalLengthMM = focalLengthMM
        self.focalLength35MM = focalLength35MM
        self.aperture = aperture
        self.exposureTimeSeconds = exposureTimeSeconds
        self.iso = iso
        self.exposureBiasEV = exposureBiasEV
        self.meteringMode = meteringMode
        self.whiteBalance = whiteBalance
        self.flash = flash
        self.software = software
        self.latitude = latitude
        self.longitude = longitude
    }

    public var hasMeaningfulValues: Bool {
        capturedAt != nil || cameraMake != nil || cameraModel != nil || lensModel != nil
            || focalLengthMM != nil || focalLength35MM != nil || aperture != nil
            || exposureTimeSeconds != nil || iso != nil || exposureBiasEV != nil
            || meteringMode != nil || whiteBalance != nil || flash != nil || software != nil
            || latitude != nil || longitude != nil
    }
}

public struct ImageMetadata: Sendable, Equatable {
    public let pixelSize: CGSize
    public let dpi: CGSize?
    public let bitDepth: Int?
    public let colorModel: String?
    public let colorProfileDescription: String?
    public let fileByteCount: Int64?
    public let properties: [String: String]
    public let exif: ImageEXIFMetadata?

    public init(
        pixelSize: CGSize,
        dpi: CGSize? = nil,
        bitDepth: Int? = nil,
        colorModel: String? = nil,
        colorProfileDescription: String? = nil,
        fileByteCount: Int64? = nil,
        properties: [String: String] = [:],
        exif: ImageEXIFMetadata? = nil
    ) {
        self.pixelSize = pixelSize
        self.dpi = dpi
        self.bitDepth = bitDepth
        self.colorModel = colorModel
        self.colorProfileDescription = colorProfileDescription
        self.fileByteCount = fileByteCount
        self.properties = properties
        self.exif = exif?.hasMeaningfulValues == true ? exif : nil
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
    case unsupportedSystem(format: ImageFormat, minimumMajorVersion: Int)
    case corrupt(URL)
    case cancelled
    case unsafeExternalResource(URL)
    case sourceTooLarge(actual: Int, limit: Int)
    case invalidDimensions(width: Int, height: Int, limit: Int)
    case decodedImageTooLarge(required: Int, limit: Int)
    case frameCountExceeded(actual: Int, limit: Int)
    case animationDurationExceeded(actual: TimeInterval, limit: TimeInterval)
    case allocationFailed(required: Int)
    case decodeFailed(String)
}

public struct DecodeSafetyLimits: Sendable, Equatable {
    public let maxRasterSourceBytes: Int
    public let maxSVGSourceBytes: Int
    public let maxPixelDimension: Int
    public let maxDecodedBytes: Int
    public let maxFrameCount: Int
    public let maxAnimationDuration: TimeInterval

    public init(
        maxRasterSourceBytes: Int = 256 * 1_024 * 1_024,
        maxSVGSourceBytes: Int = 16 * 1_024 * 1_024,
        maxPixelDimension: Int = 100_000,
        maxDecodedBytes: Int = 512 * 1_024 * 1_024,
        maxFrameCount: Int = 10_000,
        maxAnimationDuration: TimeInterval = 24 * 60 * 60
    ) {
        self.maxRasterSourceBytes = max(1, maxRasterSourceBytes)
        self.maxSVGSourceBytes = max(1, maxSVGSourceBytes)
        self.maxPixelDimension = max(1, maxPixelDimension)
        self.maxDecodedBytes = max(1, maxDecodedBytes)
        self.maxFrameCount = max(1, maxFrameCount)
        self.maxAnimationDuration = max(0.01, maxAnimationDuration)
    }

    public func validateDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0,
              width <= maxPixelDimension, height <= maxPixelDimension else {
            throw ImageLoadError.invalidDimensions(
                width: width,
                height: height,
                limit: maxPixelDimension
            )
        }
    }

    public func validateDecodedByteCount(_ byteCount: Int) throws {
        guard byteCount > 0, byteCount <= maxDecodedBytes else {
            throw ImageLoadError.decodedImageTooLarge(required: byteCount, limit: maxDecodedBytes)
        }
    }

    public func validateFrameCount(_ count: Int) throws {
        guard count > 0, count <= maxFrameCount else {
            throw ImageLoadError.frameCountExceeded(actual: count, limit: maxFrameCount)
        }
    }

    public func validateAnimationDuration(_ duration: TimeInterval) throws {
        guard duration.isFinite, duration > 0, duration <= maxAnimationDuration else {
            throw ImageLoadError.animationDurationExceeded(actual: duration, limit: maxAnimationDuration)
        }
    }
}

public extension ImageLoadError {
    var userFacingDescription: String {
        switch self {
        case .unsupportedSystem(.avif, let minimumMajorVersion):
            "AVIF requires macOS \(minimumMajorVersion) or later"
        default:
            String(describing: self)
        }
    }
}
