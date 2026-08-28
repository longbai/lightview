import Foundation
import XCTest
@testable import LightViewCore

final class FolderCatalogTests: XCTestCase {
    func testEnumeratesSupportedVisibleFilesInNaturalOrder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data().write(to: directory.appendingPathComponent("img10.png"))
        try Data().write(to: directory.appendingPathComponent("img2.png"))
        try Data().write(to: directory.appendingPathComponent(".hidden.png"))
        try Data().write(to: directory.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("nested"),
            withIntermediateDirectories: false
        )
        try Data().write(to: directory.appendingPathComponent("nested/inside.jpg"))

        let catalog = try FolderCatalog(directoryURL: directory)

        XCTAssertEqual(catalog.entries.map(\.name), ["img2.png", "img10.png"])
    }

    func testNeighborHonorsBoundariesAndWrapping() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("1.jpg")
        let second = directory.appendingPathComponent("2.jpg")
        try Data().write(to: first)
        try Data().write(to: second)
        let catalog = try FolderCatalog(directoryURL: directory)

        XCTAssertNil(catalog.neighbor(from: first, direction: .previous, wraps: false))
        XCTAssertEqual(catalog.neighbor(from: first, direction: .previous, wraps: true)?.url, second)
        XCTAssertNil(catalog.neighbor(from: second, direction: .next, wraps: false))
        XCTAssertEqual(catalog.neighbor(from: second, direction: .next, wraps: true)?.url, first)
        XCTAssertNil(catalog.neighbor(from: directory.appendingPathComponent("removed.jpg"), direction: .next, wraps: true))
    }

    func testEmptyDirectoryHasNoEntriesOrNeighbors() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = try FolderCatalog(directoryURL: directory)

        XCTAssertTrue(catalog.entries.isEmpty)
        XCTAssertNil(catalog.neighbor(from: directory.appendingPathComponent("none.png"), direction: .next, wraps: true))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightViewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
