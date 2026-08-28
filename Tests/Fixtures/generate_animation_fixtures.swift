import CoreGraphics
import Foundation
import ImageIO

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

typealias Pixel = (UInt8, UInt8, UInt8, UInt8)

func image(width: Int, height: Int, pixels: [Pixel]) throws -> CGImage {
    precondition(pixels.count == width * height)
    var bytes: [UInt8] = []
    bytes.reserveCapacity(pixels.count * 4)
    for pixel in pixels {
        bytes.append(contentsOf: [pixel.0, pixel.1, pixel.2, pixel.3])
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let result = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: width * 4,
              space: colorSpace,
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
          ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return result
}

func solid(width: Int, height: Int, pixel: Pixel) throws -> CGImage {
    try image(width: width, height: height, pixels: Array(repeating: pixel, count: width * height))
}

func writePNG(_ image: CGImage, named name: String) throws {
    let url = outputDirectory.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let red = try solid(width: 4, height: 2, pixel: (255, 0, 0, 255))
let green = try solid(width: 4, height: 2, pixel: (0, 255, 0, 255))
let blue = try solid(width: 4, height: 2, pixel: (0, 0, 255, 255))
let transparent: Pixel = (0, 0, 0, 0)
let gifMiddle = try image(
    width: 4,
    height: 2,
    pixels: Array(repeating: [transparent, transparent, (0, 0, 255, 255), (0, 0, 255, 255)], count: 2).flatMap { $0 }
)
let gifFinal = try image(
    width: 4,
    height: 2,
    pixels: Array(repeating: [(0, 255, 0, 255), (0, 255, 0, 255), transparent, transparent], count: 2).flatMap { $0 }
)

func writeGIF() throws {
    let url = outputDirectory.appendingPathComponent("disposal.gif")
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        "com.compuserve.gif" as CFString,
        3,
        nil
    ) else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationSetProperties(destination, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 2]
    ] as CFDictionary)
    for (frame, delay) in zip([red, gifMiddle, gifFinal], [0.10, 0.20, 0.30]) {
        CGImageDestinationAddImage(destination, frame, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: delay]
        ] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }

    var encoded = try Data(contentsOf: url)
    var controlExtensionCount = 0
    for index in 0..<(encoded.count - 3) where
        encoded[index] == 0x21 && encoded[index + 1] == 0xF9 && encoded[index + 2] == 0x04 {
        controlExtensionCount += 1
        if controlExtensionCount == 1 {
            encoded[index + 3] = 0x05
        } else if controlExtensionCount == 2 {
            encoded[index + 3] = 0x09
        }
    }
    try encoded.write(to: url, options: .atomic)
}

func writeAPNG() throws {
    let url = outputDirectory.appendingPathComponent("sample.apng")
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        "public.png" as CFString,
        3,
        nil
    ) else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationSetProperties(destination, [
        kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]
    ] as CFDictionary)
    for (frame, delay) in zip([red, green, blue], [0.10, 0.20, 0.30]) {
        CGImageDestinationAddImage(destination, frame, [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGUnclampedDelayTime: delay]
        ] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

try writeGIF()
try writeAPNG()
try writePNG(blue, named: "webp-base.png")
try writePNG(try solid(width: 2, height: 2, pixel: (255, 0, 0, 128)), named: "webp-over.png")
try writePNG(try solid(width: 2, height: 2, pixel: (0, 255, 0, 255)), named: "webp-source.png")
