import CoreGraphics
import Foundation
import ImageIO

public struct SVGDecoder: ImageDecoding, Sendable {
    public let maxSourceBytes: Int

    public init(maxSourceBytes: Int = 16 * 1_024 * 1_024) {
        self.maxSourceBytes = max(1, maxSourceBytes)
    }

    public func inspect(url: URL) throws -> ImageInspection {
        let parsed = try parse(url: url)
        defer { LVSVGDocumentDestroy(parsed.document) }
        let size = parsed.size
        return ImageInspection(
            format: .svg,
            rawPixelSize: size,
            orientedPixelSize: size,
            orientation: .up,
            frameCount: 1,
            metadata: ImageMetadata(
                pixelSize: size,
                colorModel: "RGBA",
                colorProfileDescription: "sRGB",
                fileByteCount: Int64(parsed.sourceByteCount)
            )
        )
    }

    public func decode(
        _ request: DecodeRequest,
        cancellation: DecodeCancellation
    ) throws -> RasterAsset {
        try cancellation.throwIfCancelled()
        let parsed = try parse(url: request.url)
        defer { LVSVGDocumentDestroy(parsed.document) }
        try cancellation.throwIfCancelled()

        if !request.requiresFullResolution {
            guard request.targetPixelSize.width.isFinite,
                  request.targetPixelSize.height.isFinite,
                  request.targetPixelSize.width > 0,
                  request.targetPixelSize.height > 0 else {
                throw ImageLoadError.decodeFailed("Invalid SVG target pixel size")
            }
        }

        let outputSize = Self.outputSize(
            intrinsic: parsed.size,
            target: request.targetPixelSize,
            fullResolution: request.requiresFullResolution
        )
        let width = Int(outputSize.width.rounded(.up))
        let height = Int(outputSize.height.rounded(.up))
        let byteCost = try ImageIODecoder.decodedByteCost(width: width, height: height, bytesPerPixel: 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw ImageLoadError.decodeFailed("Could not allocate the SVG render target")
        }

        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(
            x: CGFloat(width) / parsed.size.width,
            y: -CGFloat(height) / parsed.size.height
        )
        try render(document: parsed.document, in: context, cancellation: cancellation)
        guard let image = context.makeImage() else {
            throw ImageLoadError.decodeFailed("Could not create the rendered SVG image")
        }
        let metadata = ImageMetadata(
            pixelSize: parsed.size,
            colorModel: "RGBA",
            colorProfileDescription: "sRGB",
            fileByteCount: Int64(parsed.sourceByteCount)
        )
        return RasterAsset(
            image: image,
            originalPixelSize: parsed.size,
            decodedPixelSize: CGSize(width: width, height: height),
            orientation: .up,
            metadata: metadata,
            decodedByteCost: byteCost,
            format: .svg
        )
    }

    private func parse(url: URL) throws -> ParsedDocument {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImageLoadError.missing(url)
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values?.fileSize, fileSize > maxSourceBytes {
            throw ImageLoadError.sourceTooLarge(actual: fileSize, limit: maxSourceBytes)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maxSourceBytes else {
            throw ImageLoadError.sourceTooLarge(actual: data.count, limit: maxSourceBytes)
        }
        guard Self.isSafeSource(data) else {
            throw ImageLoadError.unsafeExternalResource(url)
        }
        let document = data.withUnsafeBytes { bytes in
            LVSVGDocumentCreate(bytes.bindMemory(to: UInt8.self).baseAddress, data.count)
        }
        guard let document else { throw ImageLoadError.corrupt(url) }
        let size = CGSize(
            width: CGFloat(LVSVGDocumentWidth(document)),
            height: CGFloat(LVSVGDocumentHeight(document))
        )
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            LVSVGDocumentDestroy(document)
            throw ImageLoadError.corrupt(url)
        }
        return ParsedDocument(document: document, size: size, sourceByteCount: data.count)
    }

    private static func isSafeSource(_ data: Data) -> Bool {
        guard let source = String(data: data, encoding: .utf8) else { return false }
        let lower = source.lowercased()
        let deniedTokens = ["<script", "<!doctype", "<!entity", "<image", "<foreignobject"]
        if deniedTokens.contains(where: lower.contains) { return false }
        if lower.range(of: #"\bon[a-z]+\s*="#, options: .regularExpression) != nil { return false }
        if lower.range(of: #"(?:href|xlink:href)\s*=\s*[\"']\s*(?!#)"#, options: .regularExpression) != nil {
            return false
        }
        if lower.range(of: #"url\(\s*[\"']?\s*(?!#)"#, options: .regularExpression) != nil { return false }
        return true
    }

    private static func outputSize(intrinsic: CGSize, target: CGSize, fullResolution: Bool) -> CGSize {
        guard !fullResolution else { return intrinsic }
        let targetWidth = max(1, target.width)
        let targetHeight = max(1, target.height)
        let scale = min(targetWidth / intrinsic.width, targetHeight / intrinsic.height)
        return CGSize(
            width: max(1, intrinsic.width * scale),
            height: max(1, intrinsic.height * scale)
        )
    }

    private func render(
        document: OpaquePointer,
        in context: CGContext,
        cancellation: DecodeCancellation
    ) throws {
        var shape = LVSVGDocumentFirstShape(document)
        while let currentShape = shape {
            try cancellation.throwIfCancelled()
            if LVSVGShapeIsVisible(currentShape) != 0 {
                let path = makePath(for: currentShape)
                drawFill(of: currentShape, path: path, in: context)
                drawStroke(of: currentShape, path: path, in: context)
            }
            shape = LVSVGShapeNext(currentShape)
        }
    }

    private func makePath(for shape: OpaquePointer) -> CGPath {
        let result = CGMutablePath()
        var path = LVSVGShapeFirstPath(shape)
        while let currentPath = path {
            let count = Int(LVSVGPathPointCount(currentPath))
            if count > 0, let first = point(in: currentPath, at: 0) {
                result.move(to: first)
                var index = 1
                while index + 2 < count {
                    guard let control1 = point(in: currentPath, at: index),
                          let control2 = point(in: currentPath, at: index + 1),
                          let end = point(in: currentPath, at: index + 2) else { break }
                    result.addCurve(to: end, control1: control1, control2: control2)
                    index += 3
                }
                if LVSVGPathIsClosed(currentPath) != 0 { result.closeSubpath() }
            }
            path = LVSVGPathNext(currentPath)
        }
        return result
    }

    private func point(in path: OpaquePointer, at index: Int) -> CGPoint? {
        var x: Float = 0
        var y: Float = 0
        guard LVSVGPathPoint(path, Int32(index), &x, &y) != 0 else { return nil }
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }

    private func drawFill(of shape: OpaquePointer, path: CGPath, in context: CGContext) {
        let type = Int(LVSVGShapeFillType(shape))
        guard type != Int(LVSVGPaintNone) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path)
        if type == Int(LVSVGPaintColor) {
            context.setFillColor(color(LVSVGShapeFillColor(shape), opacity: LVSVGShapeOpacity(shape)))
            context.drawPath(using: LVSVGShapeFillRule(shape) == 0 ? .fill : .eoFill)
        } else {
            if LVSVGShapeFillRule(shape) == 0 {
                context.clip()
            } else {
                context.clip(using: .evenOdd)
            }
            drawGradient(of: shape, stroke: false, type: type, in: context)
        }
    }

    private func drawStroke(of shape: OpaquePointer, path: CGPath, in context: CGContext) {
        let type = Int(LVSVGShapeStrokeType(shape))
        let width = CGFloat(LVSVGShapeStrokeWidth(shape))
        guard type != Int(LVSVGPaintNone), width > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        configureStroke(of: shape, in: context)
        context.addPath(path)
        if type == Int(LVSVGPaintColor) {
            context.setStrokeColor(color(LVSVGShapeStrokeColor(shape), opacity: LVSVGShapeOpacity(shape)))
            context.strokePath()
        } else {
            context.replacePathWithStrokedPath()
            context.clip()
            drawGradient(of: shape, stroke: true, type: type, in: context)
        }
    }

    private func configureStroke(of shape: OpaquePointer, in context: CGContext) {
        context.setLineWidth(CGFloat(LVSVGShapeStrokeWidth(shape)))
        context.setMiterLimit(CGFloat(LVSVGShapeMiterLimit(shape)))
        context.setLineCap([.butt, .round, .square][safe: Int(LVSVGShapeLineCap(shape))] ?? .butt)
        context.setLineJoin([.miter, .round, .bevel][safe: Int(LVSVGShapeLineJoin(shape))] ?? .miter)
        let count = Int(LVSVGShapeDashCount(shape))
        if count > 0 {
            let values = (0..<count).map { CGFloat(LVSVGShapeDashValue(shape, Int32($0))) }
            context.setLineDash(phase: CGFloat(LVSVGShapeDashOffset(shape)), lengths: values)
        }
    }

    private func drawGradient(
        of shape: OpaquePointer,
        stroke: Bool,
        type: Int,
        in context: CGContext
    ) {
        let strokeFlag: Int32 = stroke ? 1 : 0
        let stopCount = Int(LVSVGShapeGradientStopCount(shape, strokeFlag))
        guard stopCount > 0 else { return }
        let colors = (0..<stopCount).map {
            color(LVSVGShapeGradientStopColor(shape, strokeFlag, Int32($0)), opacity: LVSVGShapeOpacity(shape))
        } as CFArray
        let locations = (0..<stopCount).map {
            CGFloat(LVSVGShapeGradientStopOffset(shape, strokeFlag, Int32($0)))
        }
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: locations) else {
            return
        }
        let values = (0..<6).map { CGFloat(LVSVGShapeGradientTransform(shape, strokeFlag, Int32($0))) }
        let gradientToSVG = CGAffineTransform(
            a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5]
        ).inverted()
        guard gradientToSVG.a.isFinite else { return }
        context.concatenate(gradientToSVG)
        if type == Int(LVSVGPaintLinearGradient) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: 1),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        } else if type == Int(LVSVGPaintRadialGradient) {
            context.drawRadialGradient(
                gradient,
                startCenter: .zero,
                startRadius: 0,
                endCenter: .zero,
                endRadius: 1,
                options: [.drawsAfterEndLocation]
            )
        }
    }

    private func color(_ packed: UInt32, opacity: Float) -> CGColor {
        let red = CGFloat(packed & 0xff) / 255
        let green = CGFloat((packed >> 8) & 0xff) / 255
        let blue = CGFloat((packed >> 16) & 0xff) / 255
        let alpha = CGFloat((packed >> 24) & 0xff) / 255 * CGFloat(opacity)
        return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [red, green, blue, alpha])!
    }
}

private struct ParsedDocument {
    let document: OpaquePointer
    let size: CGSize
    let sourceByteCount: Int
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
