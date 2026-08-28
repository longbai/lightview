import Foundation

public enum FileSignatureDetector {
    public static let maximumHeaderByteCount = 512

    public static func detect(_ data: Data) -> ImageFormat? {
        let header = Array(data.prefix(maximumHeaderByteCount))

        if header.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if header.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if header.starts(with: Array("GIF87a".utf8)) || header.starts(with: Array("GIF89a".utf8)) { return .gif }
        if header.starts(with: [0x49, 0x49, 0x2A, 0x00]) || header.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        if header.starts(with: Array("BM".utf8)) { return .bmp }
        if header.starts(with: [0x00, 0x00, 0x01, 0x00]) { return .ico }
        if isJPEG2000(header) { return .jpeg2000 }
        if isWebP(header) { return .webP }
        if let isoFormat = isoBaseMediaFormat(header) { return isoFormat }
        if isSVG(header) { return .svg }
        return nil
    }

    private static func isWebP(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 12
            && Array(bytes[0..<4]) == Array("RIFF".utf8)
            && Array(bytes[8..<12]) == Array("WEBP".utf8)
    }

    private static func isJPEG2000(_ bytes: [UInt8]) -> Bool {
        bytes.starts(with: [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A, 0x87, 0x0A])
            || bytes.starts(with: [0xFF, 0x4F, 0xFF, 0x51])
    }

    private static func isoBaseMediaFormat(_ bytes: [UInt8]) -> ImageFormat? {
        guard bytes.count >= 12, Array(bytes[4..<8]) == Array("ftyp".utf8) else { return nil }

        let avifBrands = Set(["avif", "avis"])
        let heifBrands = Set(["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"])
        var brands: [String] = []
        var offset = 8
        while offset + 4 <= bytes.count {
            brands.append(String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self))
            offset += 4
        }

        if brands.contains(where: avifBrands.contains) { return .avif }
        if brands.contains(where: heifBrands.contains) { return .heif }
        return nil
    }

    private static func isSVG(_ bytes: [UInt8]) -> Bool {
        var textBytes = bytes
        if textBytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            textBytes.removeFirst(3)
        }

        guard let text = String(bytes: textBytes, encoding: .utf8) else { return false }
        var remainder = text.drop(while: { $0.isASCIIWhitespace })

        if remainder.hasPrefix("<?xml"), let end = remainder.range(of: "?>") {
            remainder = remainder[end.upperBound...].drop(while: { $0.isASCIIWhitespace })
        }
        while remainder.hasPrefix("<!--"), let end = remainder.range(of: "-->") {
            remainder = remainder[end.upperBound...].drop(while: { $0.isASCIIWhitespace })
        }

        return remainder.lowercased().hasPrefix("<svg")
    }
}

private extension Character {
    var isASCIIWhitespace: Bool {
        self == " " || self == "\t" || self == "\n" || self == "\r" || self == "\u{000C}"
    }
}
