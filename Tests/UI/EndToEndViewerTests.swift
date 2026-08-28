import Foundation
import XCTest

final class EndToEndViewerTests: XCTestCase {
    @MainActor
    func testFolderNavigationTransformsAndSeparateWindowState() throws {
        let folder = try makeTwoImageFolder()
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-LightViewUITestOpenPath", folder.path,
        ]
        app.launch()

        XCTAssertTrue(app.groups["viewer.canvas"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.title.contains("01.png"))
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil { app.windows.firstMatch.title.contains("02.png") })

        for key in ["1", "f", "h", "v"] { app.typeKey(key, modifierFlags: []) }
        app.typeKey(.rightArrow, modifierFlags: .shift)
        XCTAssertTrue(app.groups["viewer.canvas"].exists)

        app.typeKey("n", modifierFlags: .command)
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(app.buttons["welcome.openButton"].exists)
        XCTAssertTrue(app.windows.element(boundBy: 0).title.contains("02.png") || app.windows.element(boundBy: 1).title.contains("02.png"))
    }

    @MainActor
    func testHelpReopensWelcomeAndAnimationCanPause() {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Animation/disposal.gif")
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-LightViewUITestOpenPath", fixture.path]
        app.launch()

        XCTAssertTrue(app.groups["viewer.canvas"].waitForExistence(timeout: 5))
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.groups["viewer.canvas"].exists)
        app.menuBars.menuBarItems["Help"].click()
        app.menuItems["LightView Guide"].click()
        XCTAssertTrue(app.buttons["welcome.openButton"].waitForExistence(timeout: 3))
    }

    private func makeTwoImageFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LightView-E2E-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+AvwNkwAAAABJRU5ErkJggg==")!
        try png.write(to: folder.appendingPathComponent("01.png"), options: .atomic)
        try png.write(to: folder.appendingPathComponent("02.png"), options: .atomic)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 3, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }
}
