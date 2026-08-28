import Foundation
import XCTest
@testable import LightViewCore

final class FileSignatureDetectorTests: XCTestCase {
    func testDetectsMagicInsteadOfExtension() {
        XCTAssertEqual(
            FileSignatureDetector.detect(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
            .png
        )
        XCTAssertEqual(FileSignatureDetector.detect(Data("RIFF1234WEBPVP8 ".utf8)), .webP)
        XCTAssertEqual(FileSignatureDetector.detect(Data("<svg viewBox='0 0 1 1'>".utf8)), .svg)
    }

    func testSvgDetectionAllowsBomAndLeadingASCIIWhitespace() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(" \n\t<svg xmlns='http://www.w3.org/2000/svg'>".utf8)
        XCTAssertEqual(FileSignatureDetector.detect(data), .svg)
    }

    func testRejectsShortOrUnknownHeaders() {
        XCTAssertNil(FileSignatureDetector.detect(Data()))
        XCTAssertNil(FileSignatureDetector.detect(Data([0x00, 0x01, 0x02])))
    }
}
