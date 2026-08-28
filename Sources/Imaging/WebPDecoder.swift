import CoreGraphics
import Darwin
import Foundation
import ImageIO

public struct WebPDecoder: ImageDecoding, Sendable {
    public let maxSourceBytes: Int
    public let maxDecodedBytes: Int
    public let maxPixelDimension: Int
    private let outputAllocator: @Sendable (Int) -> UnsafeMutableRawPointer?

    public init(
        maxSourceBytes: Int = 256 * 1_024 * 1_024,
        maxDecodedBytes: Int = 512 * 1_024 * 1_024,
        maxPixelDimension: Int = 100_000
    ) {
        self.maxSourceBytes = max(1, maxSourceBytes)
        self.maxDecodedBytes = max(1, maxDecodedBytes)
        self.maxPixelDimension = max(1, maxPixelDimension)
        self.outputAllocator = { malloc($0) }
    }

    init(
        maxSourceBytes: Int = 256 * 1_024 * 1_024,
        maxDecodedBytes: Int = 512 * 1_024 * 1_024,
        maxPixelDimension: Int = 100_000,
        outputAllocator: @escaping @Sendable (Int) -> UnsafeMutableRawPointer?
    ) {
        self.maxSourceBytes = max(1, maxSourceBytes)
        self.maxDecodedBytes = max(1, maxDecodedBytes)
        self.maxPixelDimension = max(1, maxPixelDimension)
        self.outputAllocator = outputAllocator
    }

    public func inspect(url: URL) throws -> ImageInspection {
        let source = try readSource(url: url)
        let features = try inspect(data: source.data, url: source.url)
        let size = CGSize(width: features.width, height: features.height)
        let profile = colorSpace(from: source.data)
        return ImageInspection(
            format: .webP,
            rawPixelSize: size,
            orientedPixelSize: size,
            orientation: .up,
            frameCount: 1,
            metadata: ImageMetadata(
                pixelSize: size,
                bitDepth: 8,
                colorModel: features.hasAlpha ? "RGBA" : "RGB",
                colorProfileDescription: profile?.name as String? ?? "sRGB",
                fileByteCount: Int64(source.data.count)
            )
        )
    }

    public func decode(
        _ request: DecodeRequest,
        cancellation: DecodeCancellation
    ) throws -> RasterAsset {
        try cancellation.throwIfCancelled()
        let source = try readSource(url: request.url)
        let features = try inspect(data: source.data, url: source.url)
        try cancellation.throwIfCancelled()
        let dimensions = try outputDimensions(
            sourceWidth: features.width,
            sourceHeight: features.height,
            target: request.targetPixelSize,
            fullResolution: request.requiresFullResolution
        )
        let rowBytes = try checkedMultiply(dimensions.width, 4)
        let byteCost = try checkedMultiply(rowBytes, dimensions.height)
        guard byteCost <= maxDecodedBytes else {
            throw ImageLoadError.decodedImageTooLarge(required: byteCost, limit: maxDecodedBytes)
        }

        guard let storage = outputAllocator(byteCost) else {
            throw ImageLoadError.allocationFailed(required: byteCost)
        }
        var storageTransferred = false
        defer {
            if !storageTransferred { free(storage) }
        }
        let status = source.data.withUnsafeBytes { bytes in
            LVWebPDecodePremultipliedRGBA(
                bytes.bindMemory(to: UInt8.self).baseAddress,
                source.data.count,
                Int32(dimensions.width),
                Int32(dimensions.height),
                storage.assumingMemoryBound(to: UInt8.self),
                byteCost,
                Int32(rowBytes)
            )
        }
        guard status == LVWebPStatusOK else {
            throw ImageLoadError.decodeFailed("libwebp decode failed with status \(status)")
        }
        try cancellation.throwIfCancelled()

        guard let provider = CGDataProvider(
            dataInfo: storage,
            data: storage,
            size: byteCost,
            releaseData: { info, _, _ in free(info) }
        ) else {
            throw ImageLoadError.decodeFailed("Could not create the WebP data provider")
        }
        storageTransferred = true
        let profile = colorSpace(from: source.data)
        let colorSpace = profile ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let image = CGImage(
            width: dimensions.width,
            height: dimensions.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: rowBytes,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw ImageLoadError.decodeFailed("Could not create the WebP image")
        }
        let sourceSize = CGSize(width: features.width, height: features.height)
        let metadata = ImageMetadata(
            pixelSize: sourceSize,
            bitDepth: 8,
            colorModel: features.hasAlpha ? "RGBA" : "RGB",
            colorProfileDescription: profile?.name as String? ?? "sRGB",
            fileByteCount: Int64(source.data.count)
        )
        return RasterAsset(
            image: image,
            originalPixelSize: sourceSize,
            decodedPixelSize: CGSize(width: dimensions.width, height: dimensions.height),
            orientation: .up,
            metadata: metadata,
            decodedByteCost: byteCost,
            format: .webP
        )
    }

    private func readSource(url: URL) throws -> WebPSource {
        let normalizedURL = url.standardizedFileURL
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
        return WebPSource(url: normalizedURL, data: data)
    }

    private func inspect(data: Data, url: URL) throws -> WebPFeatures {
        var width: Int32 = 0
        var height: Int32 = 0
        var hasAlpha: Int32 = 0
        let status = data.withUnsafeBytes { bytes in
            LVWebPGetInfo(
                bytes.bindMemory(to: UInt8.self).baseAddress,
                data.count,
                &width,
                &height,
                &hasAlpha
            )
        }
        guard status == LVWebPStatusOK, width > 0, height > 0 else {
            throw ImageLoadError.corrupt(url)
        }
        guard width <= maxPixelDimension, height <= maxPixelDimension else {
            throw ImageLoadError.invalidDimensions(
                width: Int(width),
                height: Int(height),
                limit: maxPixelDimension
            )
        }
        return WebPFeatures(width: Int(width), height: Int(height), hasAlpha: hasAlpha != 0)
    }

    private func outputDimensions(
        sourceWidth: Int,
        sourceHeight: Int,
        target: CGSize,
        fullResolution: Bool
    ) throws -> (width: Int, height: Int) {
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw ImageLoadError.decodeFailed("Invalid WebP dimensions")
        }
        if fullResolution { return (sourceWidth, sourceHeight) }
        guard target.width.isFinite, target.height.isFinite, target.width > 0, target.height > 0 else {
            throw ImageLoadError.decodeFailed("Invalid WebP target pixel size")
        }
        let scale = min(
            1,
            min(target.width / CGFloat(sourceWidth), target.height / CGFloat(sourceHeight))
        )
        return (
            max(1, Int((CGFloat(sourceWidth) * scale).rounded(.down))),
            max(1, Int((CGFloat(sourceHeight) * scale).rounded(.down)))
        )
    }

    private func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow, value > 0 else {
            throw ImageLoadError.decodeFailed("WebP decoded byte count overflow")
        }
        return value
    }

    private func colorSpace(from data: Data) -> CGColorSpace? {
        var pointer: UnsafeMutablePointer<UInt8>?
        var length = 0
        let status = data.withUnsafeBytes { bytes in
            LVWebPCopyICC(
                bytes.bindMemory(to: UInt8.self).baseAddress,
                data.count,
                &pointer,
                &length
            )
        }
        guard status == LVWebPStatusOK, let pointer, length > 0 else { return nil }
        let profileData = Data(bytesNoCopy: pointer, count: length, deallocator: .custom { pointer, _ in
            LVWebPFree(pointer)
        })
        return CGColorSpace(iccData: profileData as CFData)
    }
}

private struct WebPSource {
    let url: URL
    let data: Data
}

private struct WebPFeatures {
    let width: Int
    let height: Int
    let hasAlpha: Bool
}
