import Foundation

public struct ImageDecoderRouter: ImageDecoding, Sendable {
    private let imageIO: any ImageDecoding
    private let svg: any ImageDecoding
    private let webPFallback: any ImageDecoding

    public init(
        imageIO: any ImageDecoding = ImageIODecoder(),
        svg: any ImageDecoding = SVGDecoder(),
        webPFallback: any ImageDecoding = WebPDecoder()
    ) {
        self.imageIO = imageIO
        self.svg = svg
        self.webPFallback = webPFallback
    }

    public func inspect(url: URL) throws -> ImageInspection {
        switch try format(for: url) {
        case .svg:
            return try svg.inspect(url: url)
        case .webP:
            do { return try imageIO.inspect(url: url) }
            catch { return try webPFallback.inspect(url: url) }
        default:
            return try imageIO.inspect(url: url)
        }
    }

    public func decode(
        _ request: DecodeRequest,
        cancellation: DecodeCancellation
    ) throws -> RasterAsset {
        switch try format(for: request.url) {
        case .svg:
            return try svg.decode(request, cancellation: cancellation)
        case .webP:
            do { return try imageIO.decode(request, cancellation: cancellation) }
            catch {
                try cancellation.throwIfCancelled()
                return try webPFallback.decode(request, cancellation: cancellation)
            }
        default:
            return try imageIO.decode(request, cancellation: cancellation)
        }
    }

    private func format(for url: URL) throws -> ImageFormat? {
        let normalizedURL = url.standardizedFileURL
        guard let handle = try? FileHandle(forReadingFrom: normalizedURL) else {
            if FileManager.default.fileExists(atPath: normalizedURL.path) {
                throw ImageLoadError.accessDenied(normalizedURL)
            }
            throw ImageLoadError.missing(normalizedURL)
        }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: FileSignatureDetector.maximumHeaderByteCount)
        return FileSignatureDetector.detect(header)
    }
}
