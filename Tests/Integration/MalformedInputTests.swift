import Foundation
import XCTest
@testable import LightViewCore

final class MalformedInputTests: XCTestCase {
    func testTruncatedRasterInputsAreReportedAsCorrupt() throws {
        for (name, bytes) in [
            ("broken.jpg", Data([0xFF, 0xD8, 0xFF])),
            ("broken.png", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
            ("broken.gif", Data("GIF89a".utf8)),
            ("broken.webp", Data("RIFF\0\0\0\0WEBP".utf8)),
        ] {
            let url = try temporaryFile(name: name, data: bytes)
            XCTAssertThrowsError(try ImageDecoderRouter().inspect(url: url), name) { error in
                XCTAssertEqual(error as? ImageLoadError, .corrupt(url))
            }
        }
    }

    func testSignatureWinsOverFalseExtension() throws {
        let fixture = fixtures.appendingPathComponent("Static/alpha.png")
        let url = try temporaryFile(name: "actually-png.jpg", data: Data(contentsOf: fixture))

        XCTAssertEqual(try ImageDecoderRouter().inspect(url: url).format, .png)
    }

    func testImageIODecoderRejectsSourceAndDimensionLimits() {
        let fixture = fixtures.appendingPathComponent("Static/alpha.png")
        XCTAssertThrowsError(try ImageIODecoder(limits: .init(maxRasterSourceBytes: 8)).inspect(url: fixture)) {
            guard case .sourceTooLarge = $0 as? ImageLoadError else { return XCTFail("Unexpected error: \($0)") }
        }
        XCTAssertThrowsError(try ImageIODecoder(limits: .init(maxPixelDimension: 1)).inspect(url: fixture)) {
            guard case .invalidDimensions = $0 as? ImageLoadError else { return XCTFail("Unexpected error: \($0)") }
        }
    }

    func testSVGEntitiesAndExternalResourcesAreRejected() throws {
        let entity = try temporaryFile(
            name: "entity.svg",
            data: Data("""
            <!DOCTYPE svg [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
            <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><text>&xxe;</text></svg>
            """.utf8)
        )
        XCTAssertThrowsError(try SVGDecoder().inspect(url: entity)) {
            XCTAssertEqual($0 as? ImageLoadError, .unsafeExternalResource(entity))
        }
        let external = fixtures.appendingPathComponent("SVG/external-resource.svg")
        XCTAssertThrowsError(try SVGDecoder().inspect(url: external)) {
            XCTAssertEqual($0 as? ImageLoadError, .unsafeExternalResource(external))
        }
    }

    func testSafetyLimitsRejectOverflowAndExcessiveAnimationMetadata() {
        let limits = DecodeSafetyLimits(maxPixelDimension: 100, maxFrameCount: 2, maxAnimationDuration: 1)
        XCTAssertThrowsError(try limits.validateDimensions(width: Int.max, height: 2)) {
            guard case .invalidDimensions = $0 as? ImageLoadError else { return XCTFail("Unexpected error: \($0)") }
        }
        XCTAssertThrowsError(try limits.validateFrameCount(3)) {
            XCTAssertEqual($0 as? ImageLoadError, .frameCountExceeded(actual: 3, limit: 2))
        }
        XCTAssertThrowsError(try limits.validateAnimationDuration(1.1)) {
            XCTAssertEqual($0 as? ImageLoadError, .animationDurationExceeded(actual: 1.1, limit: 1))
        }
    }

    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    private func temporaryFile(name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LightViewMalformed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return url
    }
}
