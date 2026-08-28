import Foundation
import XCTest
@testable import LightViewCore

final class SecurityScopedBookmarkStoreTests: XCTestCase {
    func testUsesLongestAuthorizedParentAndBalancesAccessExactlyOnce() throws {
        let recorder = BookmarkRecorder()
        recorder.storage = [
            "/Pictures": Data("pictures".utf8),
            "/Pictures/Trips": Data("trips".utf8),
        ]
        recorder.resolutions = [
            Data("pictures".utf8): BookmarkResolution(url: URL(fileURLWithPath: "/Pictures"), isStale: false),
            Data("trips".utf8): BookmarkResolution(url: URL(fileURLWithPath: "/Pictures/Trips"), isStale: false),
        ]
        let store = recorder.makeStore()

        let lease = try XCTUnwrap(store.access(to: URL(fileURLWithPath: "/Pictures/Trips/2026/photo.png")))
        XCTAssertEqual(lease.url.path, "/Pictures/Trips")
        XCTAssertEqual(recorder.started.map(\.path), ["/Pictures/Trips"])

        lease.end()
        lease.end()
        XCTAssertEqual(recorder.stopped.map(\.path), ["/Pictures/Trips"])
    }

    func testRefreshesStaleBookmarkUsingResolvedURL() throws {
        let recorder = BookmarkRecorder()
        let old = Data("old".utf8)
        let refreshed = Data("refreshed".utf8)
        recorder.storage = ["/Pictures": old]
        recorder.resolutions[old] = BookmarkResolution(
            url: URL(fileURLWithPath: "/Pictures"),
            isStale: true
        )
        recorder.created["/Pictures"] = refreshed
        let store = recorder.makeStore()

        _ = try XCTUnwrap(store.access(to: URL(fileURLWithPath: "/Pictures/photo.png")))

        XCTAssertEqual(recorder.storage["/Pictures"], refreshed)
        XCTAssertEqual(recorder.createdURLs.map(\.path), ["/Pictures"])
    }

    func testRemovesInvalidBookmark() {
        let recorder = BookmarkRecorder()
        recorder.storage = ["/Unavailable": Data("invalid".utf8)]
        let store = recorder.makeStore()

        XCTAssertNil(store.access(to: URL(fileURLWithPath: "/Unavailable/photo.png")))
        XCTAssertTrue(recorder.storage.isEmpty)
    }

    func testPersistReplacesBookmarkForSameStandardizedFolder() throws {
        let recorder = BookmarkRecorder()
        recorder.storage = ["/Pictures": Data("old".utf8)]
        recorder.created["/Pictures"] = Data("new".utf8)
        let store = recorder.makeStore()

        try store.persistAccess(to: URL(fileURLWithPath: "/Pictures/../Pictures"))

        XCTAssertEqual(recorder.storage, ["/Pictures": Data("new".utf8)])
    }
}

private final class BookmarkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    var storage: [String: Data] = [:]
    var resolutions: [Data: BookmarkResolution] = [:]
    var created: [String: Data] = [:]
    var createdURLs: [URL] = []
    var started: [URL] = []
    var stopped: [URL] = []

    func makeStore() -> SecurityScopedBookmarkStore {
        SecurityScopedBookmarkStore(
            load: { [self] in lock.withLock { storage } },
            save: { [self] value in lock.withLock { storage = value } },
            operations: SecurityScopedBookmarkOperations(
                create: { [self] url in
                    try lock.withLock {
                        createdURLs.append(url)
                        guard let data = created[url.path] else { throw TestError.missingBookmark }
                        return data
                    }
                },
                resolve: { [self] data in
                    try lock.withLock {
                        guard let resolution = resolutions[data] else { throw TestError.missingResolution }
                        return resolution
                    }
                },
                start: { [self] url in lock.withLock { started.append(url); return true } },
                stop: { [self] url in lock.withLock { stopped.append(url) } }
            )
        )
    }
}

private enum TestError: Error {
    case missingBookmark
    case missingResolution
}
