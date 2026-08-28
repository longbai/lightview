import Foundation

public struct NativeFormatPolicy: Sendable {
    public static let minimumAVIFMajorVersion = 13

    public init() {}

    public func canAttemptAVIF(on version: OperatingSystemVersion) -> Bool {
        version.majorVersion >= Self.minimumAVIFMajorVersion
    }

    public func requireAVIFSupport(on version: OperatingSystemVersion) throws {
        guard canAttemptAVIF(on: version) else {
            throw ImageLoadError.unsupportedSystem(
                format: .avif,
                minimumMajorVersion: Self.minimumAVIFMajorVersion
            )
        }

        // The injected version makes routing deterministic in tests. This runtime
        // gate ensures production never enters AVIF-specific native APIs on an
        // older AppKit/ImageIO implementation.
        guard #available(macOS 13.0, *) else {
            throw ImageLoadError.unsupportedSystem(
                format: .avif,
                minimumMajorVersion: Self.minimumAVIFMajorVersion
            )
        }
    }
}
