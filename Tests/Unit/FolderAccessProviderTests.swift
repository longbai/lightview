import Foundation
import XCTest
@testable import LightViewCore

final class FolderAccessProviderTests: XCTestCase {
    func testLeaseReleasesExactlyOnceAfterEndAndDeinitialization() {
        let counter = ReleaseCounter()
        var lease: AccessLease? = AccessLease(url: URL(fileURLWithPath: "/tmp")) {
            counter.increment()
        }

        lease?.end()
        lease?.end()
        lease = nil

        XCTAssertEqual(counter.value, 1)
    }

    func testDirectProviderAcceptsReadableFileAndContainingDirectory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("image.png")
        try Data().write(to: imageURL)
        let provider = DirectFolderAccessProvider()

        let imageLease = try provider.accessImage(at: imageURL)
        let folderLease = try provider.accessContainingFolder(of: imageURL)

        XCTAssertEqual(imageLease.url, imageURL.standardizedFileURL)
        XCTAssertEqual(folderLease.url, directory.standardizedFileURL)
    }

    func testDirectProviderRejectsMissingFile() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightViewMissing-\(UUID().uuidString).png")
        let provider = DirectFolderAccessProvider()

        XCTAssertThrowsError(try provider.accessImage(at: missingURL)) { error in
            XCTAssertEqual(error as? ImageLoadError, .missing(missingURL.standardizedFileURL))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightViewAccessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

private final class ReleaseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() {
        lock.withLock { storage += 1 }
    }
}
