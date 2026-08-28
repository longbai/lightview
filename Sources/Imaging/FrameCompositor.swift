import CoreGraphics
import Foundation

public enum AnimationBlendMode: Sendable, Equatable {
    case source
    case over
}

public enum AnimationDisposalMode: Sendable, Equatable {
    case none
    case background
}

public struct AnimationFrameFragment: Sendable, Equatable {
    public let xOffset: Int
    public let yOffset: Int
    public let width: Int
    public let height: Int
    public let rowBytes: Int
    public let premultipliedRGBA: Data
    public let blendMode: AnimationBlendMode
    public let disposalMode: AnimationDisposalMode

    public init(
        xOffset: Int,
        yOffset: Int,
        width: Int,
        height: Int,
        rowBytes: Int,
        premultipliedRGBA: Data,
        blendMode: AnimationBlendMode,
        disposalMode: AnimationDisposalMode
    ) {
        self.xOffset = xOffset
        self.yOffset = yOffset
        self.width = width
        self.height = height
        self.rowBytes = rowBytes
        self.premultipliedRGBA = premultipliedRGBA
        self.blendMode = blendMode
        self.disposalMode = disposalMode
    }
}

public final class FrameCompositor {
    public let canvasWidth: Int
    public let canvasHeight: Int
    public let decodedByteCost: Int

    private var canvas: [UInt8]
    private var priorFragment: AnimationFrameFragment?

    public init(canvasWidth: Int, canvasHeight: Int, maxDecodedBytes: Int) throws {
        guard canvasWidth > 0, canvasHeight > 0 else {
            throw ImageLoadError.decodeFailed("Invalid animation canvas dimensions")
        }
        let rowBytes = try Self.checkedMultiply(canvasWidth, 4)
        let byteCost = try Self.checkedMultiply(rowBytes, canvasHeight)
        let limit = max(0, maxDecodedBytes)
        guard byteCost <= limit else {
            throw ImageLoadError.decodedImageTooLarge(required: byteCost, limit: limit)
        }
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        decodedByteCost = byteCost
        canvas = [UInt8](repeating: 0, count: byteCost)
    }

    public func render(_ fragment: AnimationFrameFragment) throws -> CGImage {
        try apply(fragment)
        return try snapshot()
    }

    public func apply(_ fragment: AnimationFrameFragment) throws {
        try validate(fragment)
        if let priorFragment, priorFragment.disposalMode == .background {
            clear(priorFragment)
        }
        composite(fragment)
        priorFragment = fragment
    }

    public func snapshot() throws -> CGImage { try makeImage() }

    private func validate(_ fragment: AnimationFrameFragment) throws {
        guard fragment.xOffset >= 0,
              fragment.yOffset >= 0,
              fragment.width > 0,
              fragment.height > 0,
              fragment.xOffset <= canvasWidth - fragment.width,
              fragment.yOffset <= canvasHeight - fragment.height else {
            throw ImageLoadError.decodeFailed("Animation frame lies outside its canvas")
        }
        let minimumRowBytes = try Self.checkedMultiply(fragment.width, 4)
        guard fragment.rowBytes >= minimumRowBytes else {
            throw ImageLoadError.decodeFailed("Invalid animation frame stride")
        }
        let required = try Self.checkedMultiply(fragment.rowBytes, fragment.height)
        guard fragment.premultipliedRGBA.count >= required else {
            throw ImageLoadError.decodeFailed("Animation frame pixel data is truncated")
        }
    }

    private func clear(_ fragment: AnimationFrameFragment) {
        let canvasRowBytes = canvasWidth * 4
        let clearByteCount = fragment.width * 4
        for row in 0..<fragment.height {
            let start = (fragment.yOffset + row) * canvasRowBytes + fragment.xOffset * 4
            canvas.replaceSubrange(start..<(start + clearByteCount), with: repeatElement(0, count: clearByteCount))
        }
    }

    private func composite(_ fragment: AnimationFrameFragment) {
        let canvasRowBytes = canvasWidth * 4
        fragment.premultipliedRGBA.withUnsafeBytes { sourceBytes in
            guard let source = sourceBytes.bindMemory(to: UInt8.self).baseAddress else { return }
            for row in 0..<fragment.height {
                for column in 0..<fragment.width {
                    let sourceOffset = row * fragment.rowBytes + column * 4
                    let destinationOffset = (fragment.yOffset + row) * canvasRowBytes
                        + (fragment.xOffset + column) * 4
                    switch fragment.blendMode {
                    case .source:
                        canvas[destinationOffset] = source[sourceOffset]
                        canvas[destinationOffset + 1] = source[sourceOffset + 1]
                        canvas[destinationOffset + 2] = source[sourceOffset + 2]
                        canvas[destinationOffset + 3] = source[sourceOffset + 3]
                    case .over:
                        let inverseAlpha = 255 - Int(source[sourceOffset + 3])
                        for component in 0..<4 {
                            let destination = Int(canvas[destinationOffset + component])
                            let blended = Int(source[sourceOffset + component])
                                + (destination * inverseAlpha + 127) / 255
                            canvas[destinationOffset + component] = UInt8(min(255, blended))
                        }
                    }
                }
            }
        }
    }

    private func makeImage() throws -> CGImage {
        let data = Data(canvas)
        guard let provider = CGDataProvider(data: data as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                  width: canvasWidth,
                  height: canvasHeight,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: canvasWidth * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw ImageLoadError.decodeFailed("Could not create composited animation frame")
        }
        return image
    }

    private static func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow, result > 0 else {
            throw ImageLoadError.decodeFailed("Animation decoded byte count overflow")
        }
        return result
    }
}
