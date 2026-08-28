import Foundation
import XCTest
@testable import LightViewCore

final class SandboxAccessTests: XCTestCase {
    func testFinderProvidedFileDoesNotRequireFolderBookmark() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("image.png")
        try Data().write(to: image)
        let recorder = SandboxRecorder()
        let provider = recorder.makeProvider()

        let lease = try provider.accessImage(at: image)

        XCTAssertEqual(lease.url, image.standardizedFileURL)
        XCTAssertEqual(recorder.createdBookmarks, 0)
    }

    func testAdjacentAccessRequiresAuthorizationUntilFolderIsPersisted() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("image.png")
        try Data().write(to: image)
        let recorder = SandboxRecorder()
        let provider = recorder.makeProvider()

        XCTAssertThrowsError(try provider.accessContainingFolder(of: image)) { error in
            XCTAssertEqual(error as? FolderAccessError, .authorizationRequired(directory.standardizedFileURL))
        }

        let authorizedLease = try provider.authorizeFolder(at: directory)
        authorizedLease.end()
        let restoredLease = try provider.accessContainingFolder(of: image)
        XCTAssertEqual(restoredLease.url, directory.standardizedFileURL)
        XCTAssertEqual(recorder.createdBookmarks, 1)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightViewSandboxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

private final class SandboxRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private var bookmarkURLs: [Data: URL] = [:]
    private(set) var createdBookmarks = 0

    func makeProvider() -> SandboxFolderAccessProvider {
        let operations = SecurityScopedBookmarkOperations(
            create: { [self] url in
                lock.withLock {
                    createdBookmarks += 1
                    let data = Data(url.path.utf8)
                    bookmarkURLs[data] = url
                    return data
                }
            },
            resolve: { [self] data in
                try lock.withLock {
                    guard let url = bookmarkURLs[data] else { throw SandboxTestError.invalidBookmark }
                    return BookmarkResolution(url: url, isStale: false)
                }
            },
            start: { _ in true },
            stop: { _ in }
        )
        let store = SecurityScopedBookmarkStore(
            load: { [self] in lock.withLock { storage } },
            save: { [self] value in lock.withLock { storage = value } },
            operations: operations
        )
        return SandboxFolderAccessProvider(bookmarkStore: store)
    }
}

private enum SandboxTestError: Error {
    case invalidBookmark
}
