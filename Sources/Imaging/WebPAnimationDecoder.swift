import CoreGraphics
import Foundation

public struct WebPAnimationDecoder: Sendable {
    public let maxDecodedBytes: Int
    public let maxSourceBytes: Int
    public let maxFrameCount: Int
    public let maxAnimationDuration: TimeInterval
    private let frameDecodeObserver: (@Sendable (Int) -> Void)?
    private let indexChunkObserver: (@Sendable () -> Void)?

    public init(
        maxDecodedBytes: Int = 512 * 1_024 * 1_024,
        maxSourceBytes: Int = 256 * 1_024 * 1_024,
        maxFrameCount: Int = 10_000,
        maxAnimationDuration: TimeInterval = 24 * 60 * 60
    ) {
        self.maxDecodedBytes = max(1, maxDecodedBytes)
        self.maxSourceBytes = max(1, maxSourceBytes)
        self.maxFrameCount = min(Int(Int32.max), max(2, maxFrameCount))
        self.maxAnimationDuration = max(0.01, maxAnimationDuration)
        frameDecodeObserver = nil
        indexChunkObserver = nil
    }

    init(
        maxDecodedBytes: Int,
        maxSourceBytes: Int = 256 * 1_024 * 1_024,
        maxFrameCount: Int = 10_000,
        maxAnimationDuration: TimeInterval = 24 * 60 * 60,
        frameDecodeObserver: @escaping @Sendable (Int) -> Void,
        indexChunkObserver: (@Sendable () -> Void)? = nil
    ) {
        self.maxDecodedBytes = max(1, maxDecodedBytes)
        self.maxSourceBytes = max(1, maxSourceBytes)
        self.maxFrameCount = min(Int(Int32.max), max(2, maxFrameCount))
        self.maxAnimationDuration = max(0.01, maxAnimationDuration)
        self.frameDecodeObserver = frameDecodeObserver
        self.indexChunkObserver = indexChunkObserver
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

        let index = try WebPAnimationIndex(
            data: data,
            url: normalizedURL,
            maxFrameCount: maxFrameCount,
            cancellation: cancellation,
            chunkObserver: indexChunkObserver
        )
        let canvasWidth = index.canvasWidth
        let canvasHeight = index.canvasHeight
        let rowBytes = try checkedMultiply(canvasWidth, 4)
        let required = try checkedMultiply(rowBytes, canvasHeight)
        guard required <= maxDecodedBytes else {
            throw ImageLoadError.decodedImageTooLarge(required: required, limit: maxDecodedBytes)
        }

        let durations = index.frames.map { TimeInterval($0.durationMilliseconds) / 1_000 }
        let totalDuration = durations.reduce(0, +)
        guard totalDuration <= maxAnimationDuration else {
            throw ImageLoadError.animationDurationExceeded(
                actual: totalDuration,
                limit: maxAnimationDuration
            )
        }
        let descriptor = AnimationDescriptor(
            canvasPixelSize: CGSize(width: canvasWidth, height: canvasHeight),
            frameDurations: durations,
            loopCount: index.loopCount == 0 ? nil : index.loopCount
        )
        let provider = WebPAnimationFrameProvider(
            data: data,
            records: index.frames,
            descriptor: descriptor,
            maxDecodedBytes: maxDecodedBytes,
            frameDecodeObserver: frameDecodeObserver
        )
        return .animation(AnimationAsset(
            provider: provider,
            format: .webP,
            metadata: ImageMetadata(
                pixelSize: descriptor.canvasPixelSize,
                bitDepth: 8,
                colorModel: "RGBA",
                fileByteCount: Int64(data.count)
            )
        ))
    }

    private func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow, result > 0 else {
            throw ImageLoadError.decodeFailed("Animated WebP byte count overflow")
        }
        return result
    }
}

private final class WebPAnimationFrameProvider: AnimationFrameProvider, @unchecked Sendable {
    let descriptor: AnimationDescriptor
    private let data: Data
    private let records: [WebPAnimationFrameRecord]
    private let maxDecodedBytes: Int
    private let frameDecodeObserver: (@Sendable (Int) -> Void)?
    private let lock = NSLock()
    private var compositor: FrameCompositor?
    private var lastCompositedIndex: Int?

    init(
        data: Data,
        records: [WebPAnimationFrameRecord],
        descriptor: AnimationDescriptor,
        maxDecodedBytes: Int,
        frameDecodeObserver: (@Sendable (Int) -> Void)?
    ) {
        self.data = data
        self.records = records
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
            throw ImageLoadError.decodeFailed("Animated WebP frame index is out of bounds")
        }
        lock.lock()
        defer { lock.unlock() }

        let canContinue = lastCompositedIndex.map { index > $0 } ?? (index == 0)
        if compositor == nil || !canContinue {
            compositor = try FrameCompositor(
                canvasWidth: Int(descriptor.canvasPixelSize.width),
                canvasHeight: Int(descriptor.canvasPixelSize.height),
                maxDecodedBytes: maxDecodedBytes
            )
            lastCompositedIndex = nil
        }
        guard let compositor else {
            throw ImageLoadError.decodeFailed("Animated WebP compositor is unavailable")
        }
        let startIndex = (lastCompositedIndex ?? -1) + 1
        for fragmentIndex in startIndex...index {
            try cancellation.throwIfCancelled()
            frameDecodeObserver?(fragmentIndex)
            try compositor.apply(decodeFragment(at: fragmentIndex))
            lastCompositedIndex = fragmentIndex
        }
        let result = try compositor.snapshot()
        return AnimationFrame(
            index: index,
            image: result,
            decodedByteCost: compositor.decodedByteCost
        )
    }

    private func decodeFragment(at index: Int) throws -> AnimationFrameFragment {
        let record = records[index]
        let width = record.width
        let height = record.height
        let (rowBytes, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        let (byteCount, byteOverflow) = rowBytes.multipliedReportingOverflow(by: height)
        guard !rowOverflow, !byteOverflow, byteCount > 0, byteCount <= maxDecodedBytes else {
            throw ImageLoadError.decodedImageTooLarge(required: byteCount, limit: maxDecodedBytes)
        }
        var pixels = Data(count: byteCount)
        let decodeStatus = pixels.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { sourceBytes in
                let source = sourceBytes.bindMemory(to: UInt8.self)
                return LVWebPDecodePremultipliedRGBA(
                    source.baseAddress?.advanced(by: record.fragmentRange.lowerBound),
                    record.fragmentRange.count,
                    Int32(width),
                    Int32(height),
                    outputBytes.bindMemory(to: UInt8.self).baseAddress,
                    byteCount,
                    Int32(rowBytes)
                )
            }
        }
        guard decodeStatus == LVWebPStatusOK else {
            throw ImageLoadError.decodeFailed("Could not decode animated WebP frame \(index)")
        }
        return AnimationFrameFragment(
            xOffset: record.xOffset,
            yOffset: record.yOffset,
            width: width,
            height: height,
            rowBytes: rowBytes,
            premultipliedRGBA: pixels,
            blendMode: record.blendsOver ? .over : .source,
            disposalMode: record.disposesToBackground ? .background : .none
        )
    }
}

private struct WebPAnimationFrameRecord: Sendable {
    let xOffset: Int
    let yOffset: Int
    let width: Int
    let height: Int
    let durationMilliseconds: Int
    let disposesToBackground: Bool
    let blendsOver: Bool
    let fragmentRange: Range<Int>
}

private struct WebPAnimationIndex {
    let canvasWidth: Int
    let canvasHeight: Int
    let loopCount: Int
    let frames: [WebPAnimationFrameRecord]

    init(
        data: Data,
        url: URL,
        maxFrameCount: Int,
        cancellation: DecodeCancellation,
        chunkObserver: (@Sendable () -> Void)?
    ) throws {
        guard data.count >= 12,
              Self.uint32(data, at: 0) == 0x4646_4952,
              Self.uint32(data, at: 8) == 0x5042_4557 else {
            throw ImageLoadError.corrupt(url)
        }
        guard let rawRIFFSize = Self.uint32(data, at: 4) else {
            throw ImageLoadError.corrupt(url)
        }
        let (riffEnd, riffEndOverflow) = Int(rawRIFFSize).addingReportingOverflow(8)
        guard !riffEndOverflow, riffEnd >= 12, riffEnd <= data.count else {
            throw ImageLoadError.corrupt(url)
        }

        var width: Int?
        var height: Int?
        var parsedLoopCount: Int?
        var parsedFrames: [WebPAnimationFrameRecord] = []
        var cursor = 12
        while cursor < riffEnd {
            chunkObserver?()
            try cancellation.throwIfCancelled()
            guard cursor <= riffEnd - 8 else {
                throw ImageLoadError.corrupt(url)
            }
            guard let payloadSize = Self.uint32(data, at: cursor + 4).map(Int.init) else {
                throw ImageLoadError.corrupt(url)
            }
            let payloadStart = cursor + 8
            guard payloadSize <= riffEnd - payloadStart else {
                throw ImageLoadError.corrupt(url)
            }
            let payloadEnd = payloadStart + payloadSize

            let chunkType = Self.uint32(data, at: cursor)
            if chunkType == 0x5838_5056 {
                guard cursor == 12, width == nil, height == nil, parsedLoopCount == nil,
                      parsedFrames.isEmpty, payloadSize >= 10, data[payloadStart] & 0x02 != 0,
                      let widthMinusOne = Self.uint24(data, at: payloadStart + 4),
                      let heightMinusOne = Self.uint24(data, at: payloadStart + 7) else {
                    throw ImageLoadError.corrupt(url)
                }
                width = widthMinusOne + 1
                height = heightMinusOne + 1
            } else if chunkType == 0x4D49_4E41 {
                guard width != nil, height != nil, parsedLoopCount == nil, parsedFrames.isEmpty,
                      payloadSize >= 6, let rawLoop = Self.uint16(data, at: payloadStart + 4) else {
                    throw ImageLoadError.corrupt(url)
                }
                parsedLoopCount = rawLoop
            } else if chunkType == 0x464D_4E41 {
                guard parsedLoopCount != nil, payloadSize > 16 else {
                    throw ImageLoadError.corrupt(url)
                }
                guard parsedFrames.count < maxFrameCount else {
                    throw ImageLoadError.frameCountExceeded(
                        actual: parsedFrames.count + 1,
                        limit: maxFrameCount
                    )
                }
                guard let rawX = Self.uint24(data, at: payloadStart),
                      let rawY = Self.uint24(data, at: payloadStart + 3),
                      let rawWidth = Self.uint24(data, at: payloadStart + 6),
                      let rawHeight = Self.uint24(data, at: payloadStart + 9),
                      let duration = Self.uint24(data, at: payloadStart + 12) else {
                    throw ImageLoadError.corrupt(url)
                }
                let flags = data[payloadStart + 15]
                let frameWidth = rawWidth + 1
                let frameHeight = rawHeight + 1
                let fragmentRange = try Self.validatedFragmentRange(
                    data: data,
                    start: payloadStart + 16,
                    end: payloadEnd,
                    declaredWidth: frameWidth,
                    declaredHeight: frameHeight,
                    url: url,
                    cancellation: cancellation,
                    chunkObserver: chunkObserver
                )
                parsedFrames.append(WebPAnimationFrameRecord(
                    xOffset: rawX * 2,
                    yOffset: rawY * 2,
                    width: frameWidth,
                    height: frameHeight,
                    durationMilliseconds: duration,
                    disposesToBackground: flags & 0x01 != 0,
                    blendsOver: flags & 0x02 == 0,
                    fragmentRange: fragmentRange
                ))
            } else if chunkType == 0x2038_5056 || chunkType == 0x4C38_5056
                || chunkType == 0x4850_4C41 {
                throw ImageLoadError.corrupt(url)
            }

            let paddedSize = payloadSize + (payloadSize & 1)
            guard paddedSize <= riffEnd - payloadStart else {
                throw ImageLoadError.corrupt(url)
            }
            cursor = payloadStart + paddedSize
        }

        guard cursor == riffEnd, let width, let height, let parsedLoopCount, parsedFrames.count > 1,
              parsedFrames.allSatisfy({ frame in
                  frame.xOffset >= 0 && frame.yOffset >= 0 && frame.width > 0 && frame.height > 0
                      && frame.xOffset <= width - frame.width
                      && frame.yOffset <= height - frame.height
              }) else {
            throw ImageLoadError.corrupt(url)
        }
        canvasWidth = width
        canvasHeight = height
        loopCount = parsedLoopCount
        frames = parsedFrames
    }

    private static func validatedFragmentRange(
        data: Data,
        start: Int,
        end: Int,
        declaredWidth: Int,
        declaredHeight: Int,
        url: URL,
        cancellation: DecodeCancellation,
        chunkObserver: (@Sendable () -> Void)?
    ) throws -> Range<Int> {
        guard start < end else { throw ImageLoadError.corrupt(url) }
        var cursor = start
        var alphaStart: Int?
        var imageRange: Range<Int>?

        while cursor < end {
            chunkObserver?()
            try cancellation.throwIfCancelled()
            guard cursor <= end - 8,
                  let rawSize = uint32(data, at: cursor + 4) else {
                throw ImageLoadError.corrupt(url)
            }
            let payloadSize = Int(rawSize)
            let payloadStart = cursor + 8
            guard payloadSize <= end - payloadStart else {
                throw ImageLoadError.corrupt(url)
            }
            let payloadEnd = payloadStart + payloadSize
            let paddedSize = payloadSize + (payloadSize & 1)
            guard paddedSize <= end - payloadStart else {
                throw ImageLoadError.corrupt(url)
            }
            let nextChunk = payloadStart + paddedSize

            switch uint32(data, at: cursor) {
            case 0x4850_4C41: // ALPH
                guard alphaStart == nil, imageRange == nil else {
                    throw ImageLoadError.corrupt(url)
                }
                alphaStart = cursor
            case 0x2038_5056, 0x4C38_5056: // VP8 / VP8L
                guard imageRange == nil else { throw ImageLoadError.corrupt(url) }
                imageRange = (alphaStart ?? cursor)..<payloadEnd
            default:
                break
            }
            cursor = nextChunk
        }

        guard cursor == end, let imageRange else {
            throw ImageLoadError.corrupt(url)
        }
        var actualWidth: Int32 = 0
        var actualHeight: Int32 = 0
        var hasAlpha: Int32 = 0
        let status = data.withUnsafeBytes { bytes in
            LVWebPGetInfo(
                bytes.bindMemory(to: UInt8.self).baseAddress?.advanced(by: imageRange.lowerBound),
                imageRange.count,
                &actualWidth,
                &actualHeight,
                &hasAlpha
            )
        }
        guard status == LVWebPStatusOK,
              Int(actualWidth) == declaredWidth,
              Int(actualHeight) == declaredHeight,
              alphaStart == nil || hasAlpha != 0 else {
            throw ImageLoadError.corrupt(url)
        }
        return imageRange
    }

    private static func uint16(_ data: Data, at offset: Int) -> Int? {
        guard offset >= 0, offset <= data.count - 2 else { return nil }
        return Int(data[offset]) | Int(data[offset + 1]) << 8
    }

    private static func uint24(_ data: Data, at offset: Int) -> Int? {
        guard offset >= 0, offset <= data.count - 3 else { return nil }
        return Int(data[offset]) | Int(data[offset + 1]) << 8 | Int(data[offset + 2]) << 16
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
