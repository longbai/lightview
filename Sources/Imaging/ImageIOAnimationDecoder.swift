import CoreGraphics
import Foundation
import ImageIO

public struct ImageIOAnimationDecoder: Sendable {
    public let maxDecodedBytes: Int
    public let maxSourceBytes: Int
    public let maxFrameCount: Int
    private let frameDecodeObserver: (@Sendable (Int) -> Void)?

    public init(
        maxDecodedBytes: Int = 512 * 1_024 * 1_024,
        maxSourceBytes: Int = 256 * 1_024 * 1_024,
        maxFrameCount: Int = 10_000
    ) {
        self.maxDecodedBytes = max(1, maxDecodedBytes)
        self.maxSourceBytes = max(1, maxSourceBytes)
        self.maxFrameCount = max(2, maxFrameCount)
        frameDecodeObserver = nil
    }

    init(
        maxDecodedBytes: Int,
        maxSourceBytes: Int = 256 * 1_024 * 1_024,
        maxFrameCount: Int = 10_000,
        frameDecodeObserver: @escaping @Sendable (Int) -> Void
    ) {
        self.maxDecodedBytes = max(1, maxDecodedBytes)
        self.maxSourceBytes = max(1, maxSourceBytes)
        self.maxFrameCount = max(2, maxFrameCount)
        self.frameDecodeObserver = frameDecodeObserver
    }

    public func decode(url: URL) throws -> DisplayAsset {
        try decode(url: url, cancellation: DecodeCancellation())
    }

    public func decode(url: URL, cancellation: DecodeCancellation) throws -> DisplayAsset {
        let normalizedURL = url.standardizedFileURL
        try cancellation.throwIfCancelled()
        guard FileManager.default.fileExists(atPath: normalizedURL.path) else {
            throw ImageLoadError.missing(normalizedURL)
        }
        let fileSize = (try? normalizedURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let fileSize, fileSize > maxSourceBytes {
            throw ImageLoadError.sourceTooLarge(actual: fileSize, limit: maxSourceBytes)
        }
        let data = try Data(contentsOf: normalizedURL, options: [.mappedIfSafe])
        guard data.count <= maxSourceBytes else {
            throw ImageLoadError.sourceTooLarge(actual: data.count, limit: maxSourceBytes)
        }
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw ImageLoadError.corrupt(normalizedURL)
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else {
            throw ImageLoadError.decodeFailed("Image does not contain multiple animation frames")
        }
        guard frameCount <= maxFrameCount else {
            throw ImageLoadError.decodeFailed("Animation has too many frames")
        }
        let format = FileSignatureDetector.detect(data.prefix(FileSignatureDetector.maximumHeaderByteCount))
        guard format == .gif || format == .png || format == .webP else {
            throw ImageLoadError.unsupported(format ?? .unknown)
        }

        let descriptor = try makeDescriptor(
            source: source,
            format: format!,
            frameCount: frameCount,
            cancellation: cancellation
        )
        let provider = ImageIOAnimationFrameProvider(
            data: data,
            source: source,
            descriptor: descriptor,
            maxDecodedBytes: maxDecodedBytes,
            frameDecodeObserver: frameDecodeObserver
        )
        return .animation(AnimationAsset(
            provider: provider,
            format: format!,
            metadata: ImageMetadata(
                pixelSize: descriptor.canvasPixelSize,
                fileByteCount: Int64(data.count)
            )
        ))
    }

    private func makeDescriptor(
        source: CGImageSource,
        format: ImageFormat,
        frameCount: Int,
        cancellation: DecodeCancellation
    ) throws -> AnimationDescriptor {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        let global = CGImageSourceCopyProperties(source, sourceOptions) as? [CFString: Any] ?? [:]
        let first = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any] ?? [:]
        guard let width = integer(global[kCGImagePropertyPixelWidth])
                ?? integer(first[kCGImagePropertyPixelWidth]),
              let height = integer(global[kCGImagePropertyPixelHeight])
                ?? integer(first[kCGImagePropertyPixelHeight]),
              width > 0,
              height > 0 else {
            throw ImageLoadError.decodeFailed("Animation canvas dimensions are missing")
        }
        let rowBytes = try checkedMultiply(width, 4)
        let required = try checkedMultiply(rowBytes, height)
        guard required <= maxDecodedBytes else {
            throw ImageLoadError.decodedImageTooLarge(required: required, limit: maxDecodedBytes)
        }

        var durations: [TimeInterval] = []
        durations.reserveCapacity(frameCount)
        for index in 0..<frameCount {
            try cancellation.throwIfCancelled()
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, sourceOptions)
                as? [CFString: Any] ?? [:]
            durations.append(duration(from: properties, format: format))
        }
        return AnimationDescriptor(
            canvasPixelSize: CGSize(width: width, height: height),
            frameDurations: durations,
            loopCount: loopCount(from: global, format: format)
        )
    }

    private func duration(from properties: [CFString: Any], format: ImageFormat) -> TimeInterval {
        let dictionary: [CFString: Any]
        let unclampedKey: CFString
        let clampedKey: CFString
        switch format {
        case .gif:
            dictionary = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
            unclampedKey = kCGImagePropertyGIFUnclampedDelayTime
            clampedKey = kCGImagePropertyGIFDelayTime
        case .png:
            dictionary = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any] ?? [:]
            unclampedKey = kCGImagePropertyAPNGUnclampedDelayTime
            clampedKey = kCGImagePropertyAPNGDelayTime
        case .webP:
            guard #available(macOS 11.0, *) else { return 0.10 }
            dictionary = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] ?? [:]
            unclampedKey = kCGImagePropertyWebPUnclampedDelayTime
            clampedKey = kCGImagePropertyWebPDelayTime
        default:
            return 0.10
        }
        let value = number(dictionary[unclampedKey]) ?? number(dictionary[clampedKey])
        guard let value, value.isFinite, value > 0 else { return 0.10 }
        return value < 0.011 ? 0.10 : value
    }

    private func loopCount(from properties: [CFString: Any], format: ImageFormat) -> Int? {
        let rawValue: Int?
        switch format {
        case .gif:
            let dictionary = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
            rawValue = integer(dictionary[kCGImagePropertyGIFLoopCount])
        case .png:
            let dictionary = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any] ?? [:]
            rawValue = integer(dictionary[kCGImagePropertyAPNGLoopCount])
        case .webP:
            if #available(macOS 11.0, *) {
                let dictionary = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] ?? [:]
                rawValue = integer(dictionary[kCGImagePropertyWebPLoopCount])
            } else {
                rawValue = nil
            }
        default:
            rawValue = nil
        }
        guard let rawValue, rawValue > 0 else { return nil }
        return rawValue
    }

    private func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow, result > 0 else {
            throw ImageLoadError.decodeFailed("Animation decoded byte count overflow")
        }
        return result
    }
}

private final class ImageIOAnimationFrameProvider: AnimationFrameProvider, @unchecked Sendable {
    let descriptor: AnimationDescriptor
    private let data: Data
    private let source: CGImageSource
    private let maxDecodedBytes: Int
    private let frameDecodeObserver: (@Sendable (Int) -> Void)?
    private let lock = NSLock()

    init(
        data: Data,
        source: CGImageSource,
        descriptor: AnimationDescriptor,
        maxDecodedBytes: Int,
        frameDecodeObserver: (@Sendable (Int) -> Void)?
    ) {
        self.data = data
        self.source = source
        self.descriptor = descriptor
        self.maxDecodedBytes = maxDecodedBytes
        self.frameDecodeObserver = frameDecodeObserver
    }

    func frame(at index: Int) throws -> AnimationFrame {
        try frame(at: index, cancellation: DecodeCancellation())
    }

    func frame(at index: Int, cancellation: DecodeCancellation) throws -> AnimationFrame {
        try cancellation.throwIfCancelled()
        guard descriptor.frameDurations.indices.contains(index) else {
            throw ImageLoadError.decodeFailed("Animation frame index is out of bounds")
        }
        frameDecodeObserver?(index)
        lock.lock()
        defer { lock.unlock() }
        guard let image = CGImageSourceCreateImageAtIndex(
            source,
            index,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        ) else {
            throw ImageLoadError.decodeFailed("ImageIO could not decode animation frame \(index)")
        }
        try cancellation.throwIfCancelled()
        let (required, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !overflow, required > 0 else {
            throw ImageLoadError.decodeFailed("Animation frame byte count overflow")
        }
        guard required <= maxDecodedBytes else {
            throw ImageLoadError.decodedImageTooLarge(required: required, limit: maxDecodedBytes)
        }
        return AnimationFrame(index: index, image: image, decodedByteCost: required)
    }
}
