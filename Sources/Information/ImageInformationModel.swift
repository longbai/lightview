import Foundation

public enum ImageInformationField: String, CaseIterable, Sendable {
    case name = "Name"
    case path = "Path"
    case bytes = "File Size"
    case pixelSize = "Pixel Size"
    case format = "Format"
    case frameCount = "Frames"
    case colorProfile = "Color Profile"
    case creationDate = "Created"
    case modificationDate = "Modified"
}

public struct ImageInformationRow: Equatable, Sendable {
    public let field: ImageInformationField
    public let value: String

    public init(field: ImageInformationField, value: String) {
        self.field = field
        self.value = value
    }
}

public struct ImageInformationModel: Equatable, Sendable {
    public let rows: [ImageInformationRow]

    public init(
        url: URL,
        format: ImageFormat,
        frameCount: Int,
        metadata: ImageMetadata,
        creationDate: Date?,
        modificationDate: Date?
    ) {
        var values: [ImageInformationRow] = [
            .init(field: .name, value: url.lastPathComponent),
            .init(field: .path, value: url.standardizedFileURL.path),
            .init(field: .pixelSize, value: Self.formatPixels(metadata.pixelSize)),
            .init(field: .format, value: Self.formatName(format)),
            .init(field: .frameCount, value: String(max(1, frameCount))),
        ]
        if let byteCount = metadata.fileByteCount {
            values.insert(.init(field: .bytes, value: Self.formatBytes(byteCount)), at: 2)
        }
        if let profile = metadata.colorProfileDescription, !profile.isEmpty {
            values.append(.init(field: .colorProfile, value: profile))
        }
        if let creationDate {
            values.append(.init(field: .creationDate, value: Self.formatDate(creationDate)))
        }
        if let modificationDate {
            values.append(.init(field: .modificationDate, value: Self.formatDate(modificationDate)))
        }
        rows = values
    }

    public func value(for field: ImageInformationField) -> String? {
        rows.first(where: { $0.field == field })?.value
    }

    private static func formatPixels(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }

    private static func formatName(_ format: ImageFormat) -> String {
        switch format {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .gif: "GIF"
        case .tiff: "TIFF"
        case .bmp: "BMP"
        case .ico: "ICO"
        case .jpeg2000: "JPEG 2000"
        case .heif: "HEIF"
        case .webP: "WebP"
        case .svg: "SVG"
        case .avif: "AVIF"
        case .unknown: "Unknown"
        }
    }

    private static func formatBytes(_ count: Int64) -> String {
        guard count >= 1_024 else { return "\(count) bytes" }
        if count % 1_048_576 == 0 { return "\(count / 1_048_576) MB" }
        if count % 1_024 == 0 { return "\(count / 1_024) KB" }
        return String(format: "%.1f KB", Double(count) / 1_024)
    }

    private static func formatDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
