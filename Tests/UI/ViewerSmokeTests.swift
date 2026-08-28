import XCTest

final class ViewerSmokeTests: XCTestCase {
    @MainActor
    func testEmptyWindowShowsNativeWelcomeGuide() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-LightViewUITestEmptyWindow", "YES"]
        app.launch()

        XCTAssertTrue(app.otherElements["welcome.view"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["welcome.openButton"].exists)
    }

    @MainActor
    func testLaunchArgumentOpensImageInNativeCanvas() throws {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightView-UI-Fixture.png")
        let onePixelPNG = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+AvwNkwAAAABJRU5ErkJggg=="
        )!
        try onePixelPNG.write(to: fixtureURL, options: .atomic)

        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-LightViewUITestOpenPath", fixtureURL.path,
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["viewer.canvas"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.windows.firstMatch.title.contains(fixtureURL.lastPathComponent))
    }

    @MainActor
    func testLaunchArgumentOpensAnimatedImageAndEnablesPlaybackMenu() {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Animation/disposal.gif")
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-LightViewUITestOpenPath", fixtureURL.path,
        ]

        app.launch()

        XCTAssertTrue(app.otherElements["viewer.canvas"].waitForExistence(timeout: 3))
        app.menuBars.menuBarItems["Animation"].click()
        XCTAssertTrue(app.menuItems["Pause Animation"].isEnabled)
    }
}
