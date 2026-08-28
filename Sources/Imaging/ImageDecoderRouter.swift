import Foundation

public struct ImageDecoderRouter: ImageDecoding, Sendable {
    private let imageIO: any ImageDecoding
    private let svg: any ImageDecoding

    public init(
        imageIO: any ImageDecoding = ImageIODecoder(),
        svg: any ImageDecoding = SVGDecoder()
    ) {
        self.imageIO = imageIO
        self.svg = svg
    }

    public func inspect(url: URL) throws -> ImageInspection {
        try decoder(for: url).inspect(url: url)
    }

    public func decode(
        _ request: DecodeRequest,
        cancellation: DecodeCancellation
    ) throws -> RasterAsset {
        try decoder(for: request.url).decode(request, cancellation: cancellation)
    }

    private func decoder(for url: URL) throws -> any ImageDecoding {
        let normalizedURL = url.standardizedFileURL
        guard let handle = try? FileHandle(forReadingFrom: normalizedURL) else {
            if FileManager.default.fileExists(atPath: normalizedURL.path) {
                throw ImageLoadError.accessDenied(normalizedURL)
            }
            throw ImageLoadError.missing(normalizedURL)
        }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: FileSignatureDetector.maximumHeaderByteCount)
        return FileSignatureDetector.detect(header) == .svg ? svg : imageIO
    }
}
