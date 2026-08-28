import CoreGraphics
import Foundation
import ImageIO

public struct ImageIODecoder: ImageDecoding {
    public init() {}

    public func inspect(url: URL) throws -> ImageInspection {
        let normalizedURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: normalizedURL.path) else {
            throw ImageLoadError.missing(normalizedURL)
        }
        guard let source = makeSource(url: normalizedURL) else {
            throw ImageLoadError.corrupt(normalizedURL)
        }
        return try inspect(source: source, url: normalizedURL)
    }

    public func decode(_ request: DecodeRequest) throws -> RasterAsset {
        try decode(request, cancellation: DecodeCancellation())
    }

    public func decode(
        _ request: DecodeRequest,
        cancellation: DecodeCancellation
    ) throws -> RasterAsset {
        try cancellation.throwIfCancelled()
        let url = request.url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImageLoadError.missing(url)
        }
        guard let source = makeSource(url: url) else {
            throw ImageLoadError.corrupt(url)
        }
        let inspection = try inspect(source: source, url: url)
        try cancellation.throwIfCancelled()

        let requestedMaximum = max(request.targetPixelSize.width, request.targetPixelSize.height)
        let sourceMaximum = max(inspection.rawPixelSize.width, inspection.rawPixelSize.height)
        let maximumPixelSize: CGFloat
        if request.requiresFullResolution || !requestedMaximum.isFinite || requestedMaximum <= 0 {
            maximumPixelSize = sourceMaximum
        } else {
            maximumPixelSize = min(ceil(requestedMaximum), sourceMaximum)
        }
        guard maximumPixelSize.isFinite, maximumPixelSize > 0, maximumPixelSize <= CGFloat(Int.max) else {
            throw ImageLoadError.decodeFailed("Invalid target pixel size")
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maximumPixelSize),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageLoadError.decodeFailed("ImageIO could not decode \(url.lastPathComponent)")
        }
        try cancellation.throwIfCancelled()

        let byteCost = try Self.decodedByteCost(
            width: image.bytesPerRow,
            height: image.height,
            bytesPerPixel: 1
        )
        return RasterAsset(
            image: image,
            originalPixelSize: inspection.orientedPixelSize,
            decodedPixelSize: CGSize(width: image.width, height: image.height),
            orientation: .up,
            metadata: inspection.metadata,
            decodedByteCost: byteCost
        )
    }

    public static func decodedByteCost(
        width: Int,
        height: Int,
        bytesPerPixel: Int
    ) throws -> Int {
        guard width > 0, height > 0, bytesPerPixel > 0 else {
            throw ImageLoadError.decodeFailed("Invalid decoded dimensions")
        }
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: bytesPerPixel)
        guard !pixelOverflow, !byteOverflow else {
            throw ImageLoadError.decodeFailed("Decoded image byte count overflow")
        }
        return bytes
    }

    private func makeSource(url: URL) -> CGImageSource? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        return CGImageSourceCreateWithURL(url as CFURL, options)
    }

    private func inspect(source: CGImageSource, url: URL) throws -> ImageInspection {
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ) as? [CFString: Any],
              let width = integer(properties[kCGImagePropertyPixelWidth]),
              let height = integer(properties[kCGImagePropertyPixelHeight]),
              width > 0,
              height > 0 else {
            throw ImageLoadError.corrupt(url)
        }

        let orientationValue = UInt32(integer(properties[kCGImagePropertyOrientation]) ?? 1)
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
        let rawSize = CGSize(width: width, height: height)
        let orientedSize = orientation.swapsAxes
            ? CGSize(width: height, height: width)
            : rawSize
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
        let metadata = ImageMetadata(
            pixelSize: orientedSize,
            dpi: dpi(from: properties),
            bitDepth: integer(properties[kCGImagePropertyDepth]),
            colorModel: properties[kCGImagePropertyColorModel] as? String,
            colorProfileDescription: properties[kCGImagePropertyProfileName] as? String,
            fileByteCount: resourceValues?.fileSize.map(Int64.init),
            properties: ["sourceOrientation": String(orientation.rawValue)]
        )
        return ImageInspection(
            format: detectFormat(url: url),
            rawPixelSize: rawSize,
            orientedPixelSize: orientedSize,
            orientation: orientation,
            frameCount: CGImageSourceGetCount(source),
            metadata: metadata
        )
    }

    private func detectFormat(url: URL) -> ImageFormat {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: FileSignatureDetector.maximumHeaderByteCount)
        return FileSignatureDetector.detect(data) ?? .unknown
    }

    private func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private func dpi(from properties: [CFString: Any]) -> CGSize? {
        guard let width = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}

private extension CGImagePropertyOrientation {
    var swapsAxes: Bool {
        self == .left || self == .leftMirrored || self == .right || self == .rightMirrored
    }
}
