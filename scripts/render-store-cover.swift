import AppKit

// Compose a localized product-page cover around an existing, unmodified app capture.
guard CommandLine.arguments.count == 4,
      let screenshot = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Usage: swift render-store-cover.swift SCREENSHOT OUTPUT_DIR {en-US|zh-Hans}")
}
let locale = CommandLine.arguments[3]
precondition(locale == "en-US" || locale == "zh-Hans")
let chinese = locale == "zh-Hans"
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let width = 2560, height = 1600
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
let canvas = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(starting: NSColor(srgbRed: 0.045, green: 0.09, blue: 0.17, alpha: 1),
           ending: NSColor(srgbRed: 0.10, green: 0.25, blue: 0.37, alpha: 1))!
    .draw(in: canvas, angle: 70)

func title(_ string: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let line = NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
    ])
    let bounds = line.size()
    line.draw(at: NSPoint(x: (CGFloat(width) - bounds.width) / 2, y: y))
}

title(chinese ? "LightView · 原生 Mac 图片查看器" : "LightView · Native Mac Image Viewer",
      y: 1450, size: 66, weight: .bold, color: .white)
title(chinese ? "免费 · 轻量 · 高性能 · 无广告 · 开源" : "Free · Lightweight · High performance · Ad-free · Open source",
      y: 1350, size: 52, weight: .medium, color: NSColor(srgbRed: 0.74, green: 0.89, blue: 1, alpha: 1))
let imageWidth: CGFloat = 1984
let imageHeight = imageWidth * screenshot.size.height / screenshot.size.width
let frame = NSRect(x: (CGFloat(width) - imageWidth) / 2, y: 48, width: imageWidth, height: imageHeight)
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: frame, xRadius: 24, yRadius: 24).addClip()
screenshot.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.93])!
try data.write(to: output.appendingPathComponent("01-LightView-\(locale).jpg"))
