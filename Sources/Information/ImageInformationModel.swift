import Foundation

public enum ImageInformationField: String, CaseIterable, Sendable {
    case name = "Name"
    case path = "Path"
    case bytes = "File Size"
    case pixelSize = "Pixel Size"
    case format = "Format"
    case frameCount = "Frames"
    case dpi = "Resolution"
    case bitDepth = "Bit Depth"
    case colorModel = "Color Model"
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

public struct EXIFInformationRow: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct ImageInformationModel: Equatable, Sendable {
    public let rows: [ImageInformationRow]
    public let exifRows: [EXIFInformationRow]

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
            .init(field: .format, value: ViewerTitleFormatter.formatName(format, url: url)),
            .init(field: .frameCount, value: String(max(1, frameCount))),
        ]
        if let byteCount = metadata.fileByteCount {
            values.insert(.init(field: .bytes, value: Self.formatBytes(byteCount)), at: 2)
        }
        if let profile = metadata.colorProfileDescription, !profile.isEmpty {
            values.append(.init(field: .colorProfile, value: profile))
        }
        if let dpi = metadata.dpi {
            values.append(.init(field: .dpi, value: "\(Int(dpi.width.rounded())) × \(Int(dpi.height.rounded())) DPI"))
        }
        if let bitDepth = metadata.bitDepth {
            values.append(.init(field: .bitDepth, value: "\(bitDepth)-bit"))
        }
        if let colorModel = metadata.colorModel, !colorModel.isEmpty {
            values.append(.init(field: .colorModel, value: colorModel))
        }
        if let creationDate {
            values.append(.init(field: .creationDate, value: Self.formatDate(creationDate)))
        }
        if let modificationDate {
            values.append(.init(field: .modificationDate, value: Self.formatDate(modificationDate)))
        }
        rows = values
        exifRows = EXIFInformationFormatter.rows(for: metadata.exif)
    }

    public func value(for field: ImageInformationField) -> String? {
        rows.first(where: { $0.field == field })?.value
    }

    private static func formatPixels(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
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

public enum EXIFInformationFormatter {
    public static func rows(for exif: ImageEXIFMetadata?) -> [EXIFInformationRow] {
        guard let exif else { return [] }
        var rows: [EXIFInformationRow] = []
        func append(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { rows.append(.init(label: label, value: value)) }
        }
        append("Captured", exif.capturedAt)
        let camera = [exif.cameraMake, exif.cameraModel].compactMap { $0 }.joined(separator: " ")
        append("Camera", camera)
        append("Lens", exif.lensModel)
        if let focal = exif.focalLengthMM {
            let equivalent = exif.focalLength35MM.map { value in " (\(value) mm equivalent)" } ?? ""
            append("Focal Length", "\(number(focal)) mm\(equivalent)")
        } else if let equivalent = exif.focalLength35MM {
            append("Focal Length", "\(equivalent) mm equivalent")
        }
        if let aperture = exif.aperture { append("Aperture", "f/\(number(aperture))") }
        if let exposure = exif.exposureTimeSeconds, exposure > 0 {
            let value = exposure < 1
                ? "1/\(Int((1 / exposure).rounded())) s"
                : "\(number(exposure)) s"
            append("Exposure", value)
        }
        if let iso = exif.iso { append("ISO", String(iso)) }
        if let bias = exif.exposureBiasEV { append("Exposure Bias", "\(signedNumber(bias)) EV") }
        if let metering = exif.meteringMode { append("Metering", meteringName(metering)) }
        if let balance = exif.whiteBalance { append("White Balance", balance == 1 ? "Manual" : "Auto") }
        if let flash = exif.flash { append("Flash", flash & 1 == 1 ? "Fired" : "Did not fire") }
        append("Software", exif.software)
        if let latitude = exif.latitude, let longitude = exif.longitude {
            append("GPS", String(format: "%.6f, %.6f", latitude, longitude))
        }
        return rows
    }

    private static func number(_ value: Double) -> String {
        String(format: value.rounded() == value ? "%.0f" : "%.1f", value)
    }

    private static func signedNumber(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    private static func meteringName(_ value: Int) -> String {
        switch value {
        case 1: "Average"
        case 2: "Center-weighted"
        case 3: "Spot"
        case 4: "Multi-spot"
        case 5: "Pattern"
        case 6: "Partial"
        default: "Mode \(value)"
        }
    }
}

public enum ViewerTitleFormatter {
    public static func title(
        url: URL,
        format: ImageFormat,
        metadata: ImageMetadata,
        frameCount: Int,
        index: Int?,
        totalCount: Int?,
        presentationScale: CGFloat,
        rotationDegrees: Int
    ) -> String {
        var components: [String] = []
        if let index, let totalCount, totalCount > 0, index >= 0, index < totalCount {
            components.append("\(index + 1)/\(totalCount)")
        }
        components.append(url.lastPathComponent)
        let scale = presentationScale.isFinite && presentationScale > 0 ? presentationScale : 1
        components.append(String(format: scale < 0.1 ? "%.1f%%" : "%.0f%%", scale * 100))
        let original = metadata.pixelSize
        if let displayed = ViewportGeometry.displayedSize(
            imageSize: original,
            scale: scale,
            rotationDegrees: rotationDegrees
        ) {
            components.append("\(pixels(displayed)) → \(pixels(original))")
        } else {
            components.append(pixels(original))
        }
        if let bytes = metadata.fileByteCount { components.append(formatBytes(bytes)) }
        components.append(formatName(format, url: url))
        if frameCount > 1 { components.append("\(frameCount) frames") }
        components.append("LightView")
        return components.joined(separator: " · ")
    }

    public static func formatName(_ format: ImageFormat, url: URL) -> String {
        if format == .heif {
            return url.pathExtension.caseInsensitiveCompare("heic") == .orderedSame ? "HEIC" : "HEIF"
        }
        return switch format {
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

    private static func pixels(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))×\(Int(size.height.rounded()))"
    }

    private static func formatBytes(_ count: Int64) -> String {
        guard count >= 1_024 else { return "\(count) bytes" }
        if count % 1_048_576 == 0 { return "\(count / 1_048_576) MB" }
        if count % 1_024 == 0 { return "\(count / 1_024) KB" }
        if count >= 1_048_576 { return String(format: "%.1f MB", Double(count) / 1_048_576) }
        return String(format: "%.1f KB", Double(count) / 1_024)
    }
}
