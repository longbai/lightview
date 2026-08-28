import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

public final class ExportFrameComposer: @unchecked Sendable {
    public typealias SourceImage = (Int, CMTime) throws -> CGImage

    private let outputSize: CGSize
    private let composition: ExportCompositionMode
    private let transition: TransitionKind
    private let background: ExportBackground
    private let sourceImage: SourceImage
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    public init(
        outputSize: CGSize,
        composition: ExportCompositionMode,
        transition: TransitionKind,
        background: ExportBackground,
        sourceImage: @escaping SourceImage
    ) {
        self.outputSize = outputSize
        self.composition = composition
        self.transition = transition
        self.background = background
        self.sourceImage = sourceImage
    }

    public func compose(_ instruction: FrameInstruction, into pixelBuffer: CVPixelBuffer) throws {
        let width = Int(outputSize.width.rounded())
        let height = Int(outputSize.height.rounded())
        guard width > 0, height > 0,
              CVPixelBufferGetWidth(pixelBuffer) == width,
              CVPixelBufferGetHeight(pixelBuffer) == height,
              CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            throw MovieExportError.invalidPlan("Pixel buffer does not match the export canvas")
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                    CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else {
            throw MovieExportError.writerFailed("Could not create export bitmap context")
        }

        context.interpolationQuality = .high
        drawBackground(in: context)
        let primary = try sourceImage(instruction.primarySourceIndex, instruction.primaryLocalTime)
        guard let secondaryIndex = instruction.secondarySourceIndex,
              let secondaryTime = instruction.secondaryLocalTime else {
            draw(primary, in: context, offsetX: 0, alpha: 1)
            return
        }
        let secondary = try sourceImage(secondaryIndex, secondaryTime)
        switch transition {
        case .fade:
            draw(primary, in: context, offsetX: 0, alpha: 1)
            draw(secondary, in: context, offsetX: 0, alpha: CGFloat(instruction.transitionProgress))
        case .slide:
            let progress = CGFloat(instruction.transitionProgress)
            draw(primary, in: context, offsetX: -progress * outputSize.width, alpha: 1)
            draw(secondary, in: context, offsetX: (1 - progress) * outputSize.width, alpha: 1)
        case .none:
            draw(primary, in: context, offsetX: 0, alpha: 1)
        }
    }

    private func drawBackground(in context: CGContext) {
        let fallback: ExportColor
        switch background {
        case .solid(let color): fallback = color
        case .image(_, let color): fallback = color
        }
        context.setBlendMode(.copy)
        context.setFillColor(CGColor(
            colorSpace: colorSpace,
            components: [fallback.red, fallback.green, fallback.blue, fallback.alpha]
        )!)
        context.fill(CGRect(origin: .zero, size: outputSize))
        context.setBlendMode(.normal)
        if case .image(let image, _) = background {
            context.draw(image, in: aspectRect(for: image, mode: .fill))
        }
    }

    private func draw(_ image: CGImage, in context: CGContext, offsetX: CGFloat, alpha: CGFloat) {
        context.saveGState()
        context.setAlpha(alpha)
        var rect = aspectRect(for: image, mode: composition)
        rect.origin.x += offsetX
        context.draw(image, in: rect)
        context.restoreGState()
    }

    private func aspectRect(for image: CGImage, mode: ExportCompositionMode) -> CGRect {
        let imageSize = CGSize(width: image.width, height: image.height)
        let widthScale = outputSize.width / imageSize.width
        let heightScale = outputSize.height / imageSize.height
        let scale = mode == .fit ? min(widthScale, heightScale) : max(widthScale, heightScale)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (outputSize.width - size.width) / 2,
            y: (outputSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
