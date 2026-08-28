import CoreGraphics
import Foundation
import ImageIO

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func makeImage(width: Int, height: Int, alpha: Bool) throws -> CGImage {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            pixels[offset] = UInt8((x * 255) / max(width - 1, 1))
            pixels[offset + 1] = UInt8((y * 255) / max(height - 1, 1))
            pixels[offset + 2] = 128
            pixels[offset + 3] = alpha ? UInt8((x * 255) / max(width - 1, 1)) : 255
        }
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let image = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: bytesPerRow,
              space: colorSpace,
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
          ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return image
}

func write(_ image: CGImage, to url: URL, type: String, properties: [CFString: Any]) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}

let oriented = try makeImage(width: 4_000, height: 2_000, alpha: false)
try write(
    oriented,
    to: outputDirectory.appendingPathComponent("oriented-6.jpg"),
    type: "public.jpeg",
    properties: [kCGImagePropertyOrientation: 6, kCGImageDestinationLossyCompressionQuality: 0.72]
)

let alpha = try makeImage(width: 32, height: 16, alpha: true)
try write(
    alpha,
    to: outputDirectory.appendingPathComponent("alpha.png"),
    type: "public.png",
    properties: [:]
)
