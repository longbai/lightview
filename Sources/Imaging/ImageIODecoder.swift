import CoreGraphics
import Foundation
import ImageIO

public struct ImageIODecoder: ImageDecoding {
    public let limits: DecodeSafetyLimits

    public init(limits: DecodeSafetyLimits = DecodeSafetyLimits()) {
        self.limits = limits
    }

    public func inspect(url: URL) throws -> ImageInspection {
        let normalizedURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: normalizedURL.path) else {
            throw ImageLoadError.missing(normalizedURL)
        }
        try validateSourceSize(url: normalizedURL)
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
        try validateSourceSize(url: url)
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

        let estimatedByteCost = try Self.estimatedDecodedByteCost(
            rawPixelSize: inspection.rawPixelSize,
            maximumPixelSize: maximumPixelSize
        )
        try limits.validateDecodedByteCount(estimatedByteCost)
        try cancellation.throwIfCancelled()

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
        try limits.validateDecodedByteCount(byteCost)
        return RasterAsset(
            image: image,
            originalPixelSize: inspection.orientedPixelSize,
            decodedPixelSize: CGSize(width: image.width, height: image.height),
            orientation: .up,
            metadata: inspection.metadata,
            decodedByteCost: byteCost,
            format: inspection.format,
            frameCount: inspection.frameCount
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

    static func estimatedDecodedByteCost(
        rawPixelSize: CGSize,
        maximumPixelSize: CGFloat
    ) throws -> Int {
        let sourceMaximum = max(rawPixelSize.width, rawPixelSize.height)
        guard sourceMaximum.isFinite, sourceMaximum > 0,
              maximumPixelSize.isFinite, maximumPixelSize > 0 else {
            throw ImageLoadError.decodeFailed("Invalid decoded dimensions")
        }
        let decodeScale = min(1, maximumPixelSize / sourceMaximum)
        let width = max(1, Int(ceil(rawPixelSize.width * decodeScale)))
        let height = max(1, Int(ceil(rawPixelSize.height * decodeScale)))
        return try decodedByteCost(width: width, height: height, bytesPerPixel: 4)
    }

    private func makeSource(url: URL) -> CGImageSource? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        return CGImageSourceCreateWithURL(url as CFURL, options)
    }

    private func validateSourceSize(url: URL) throws {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return }
        guard fileSize <= limits.maxRasterSourceBytes else {
            throw ImageLoadError.sourceTooLarge(actual: fileSize, limit: limits.maxRasterSourceBytes)
        }
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

        try limits.validateDimensions(width: width, height: height)
        let frameCount = CGImageSourceGetCount(source)
        try limits.validateFrameCount(frameCount)
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
            properties: ["sourceOrientation": String(orientation.rawValue)],
            exif: Self.exifMetadata(from: properties)
        )
        return ImageInspection(
            format: detectFormat(url: url),
            rawPixelSize: rawSize,
            orientedPixelSize: orientedSize,
            orientation: orientation,
            frameCount: frameCount,
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

    static func exifMetadata(from properties: [CFString: Any]) -> ImageEXIFMetadata? {
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]

        func string(_ dictionary: [CFString: Any], _ key: CFString) -> String? {
            guard let value = dictionary[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        func double(_ dictionary: [CFString: Any], _ key: CFString) -> Double? {
            (dictionary[key] as? NSNumber)?.doubleValue
        }
        func integer(_ dictionary: [CFString: Any], _ key: CFString) -> Int? {
            (dictionary[key] as? NSNumber)?.intValue
        }
        func coordinate(_ dictionary: [CFString: Any], value: CFString, reference: CFString) -> Double? {
            guard let raw = double(dictionary, value), raw.isFinite else { return nil }
            let ref = string(dictionary, reference)?.uppercased()
            return ref == "S" || ref == "W" ? -abs(raw) : abs(raw)
        }

        let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.intValue
        let result = ImageEXIFMetadata(
            capturedAt: string(exif, kCGImagePropertyExifDateTimeOriginal)
                ?? string(exif, kCGImagePropertyExifDateTimeDigitized)
                ?? string(tiff, kCGImagePropertyTIFFDateTime),
            cameraMake: string(tiff, kCGImagePropertyTIFFMake),
            cameraModel: string(tiff, kCGImagePropertyTIFFModel),
            lensModel: string(exif, kCGImagePropertyExifLensModel),
            focalLengthMM: double(exif, kCGImagePropertyExifFocalLength),
            focalLength35MM: integer(exif, kCGImagePropertyExifFocalLenIn35mmFilm),
            aperture: double(exif, kCGImagePropertyExifFNumber),
            exposureTimeSeconds: double(exif, kCGImagePropertyExifExposureTime),
            iso: iso,
            exposureBiasEV: double(exif, kCGImagePropertyExifExposureBiasValue),
            meteringMode: integer(exif, kCGImagePropertyExifMeteringMode),
            whiteBalance: integer(exif, kCGImagePropertyExifWhiteBalance),
            flash: integer(exif, kCGImagePropertyExifFlash),
            software: string(tiff, kCGImagePropertyTIFFSoftware),
            latitude: coordinate(gps, value: kCGImagePropertyGPSLatitude, reference: kCGImagePropertyGPSLatitudeRef),
            longitude: coordinate(gps, value: kCGImagePropertyGPSLongitude, reference: kCGImagePropertyGPSLongitudeRef)
        )
        return result.hasMeaningfulValues ? result : nil
    }
}

private extension CGImagePropertyOrientation {
    var swapsAxes: Bool {
        self == .left || self == .leftMirrored || self == .right || self == .rightMirrored
    }
}
