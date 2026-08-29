import XCTest

final class ViewerSmokeTests: XCTestCase {
    @MainActor
    func testEmptyWindowShowsNativeWelcomeGuide() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-LightViewUITestEmptyWindow", "YES"]
        app.launch()

        XCTAssertTrue(app.buttons["welcome.openButton"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSimplifiedChineseWelcomeLocalization() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_Hans_CN",
            "-LightViewUITestEmptyWindow", "YES",
        ]
        app.launch()

        let openButton = app.buttons["welcome.openButton"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 3))
        XCTAssertEqual(openButton.label, "打开图片或文件夹…")
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

        XCTAssertTrue(app.groups["viewer.canvas"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.windows.firstMatch.title.contains(fixtureURL.lastPathComponent))
        XCTAssertTrue(app.groups["viewer.toolbar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["viewer.toolbar.zoomIn"].isEnabled)
        XCTAssertTrue(app.buttons["viewer.toolbar.fit"].isEnabled)
    }

    @MainActor
    func testBottomToolbarButtonsExecuteViewerCommands() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightView-UI-Toolbar", isDirectory: true)
        try? FileManager.default.removeItem(at: folderURL)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+AvwNkwAAAABJRU5ErkJggg=="
        )!
        try png.write(to: folderURL.appendingPathComponent("01.png"), options: .atomic)
        try png.write(to: folderURL.appendingPathComponent("02.png"), options: .atomic)

        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-LightViewUITestOpenPath", folderURL.path,
        ]
        app.launch()

        let nextButton = app.buttons["viewer.toolbar.next"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 3))
        XCTAssertTrue(nextButton.isEnabled)
        XCTAssertTrue(app.windows.firstMatch.title.contains("01.png"))
        nextButton.click()
        let titleChanged = NSPredicate(format: "title CONTAINS %@", "02.png")
        expectation(for: titleChanged, evaluatedWith: app.windows.firstMatch)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testViewMenuHidesAndRestoresBottomToolbar() {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Static/alpha.png")
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-LightViewUITestOpenPath", fixtureURL.path,
            "-interface.showsViewerToolbar", "YES",
        ]
        app.launch()

        let toolbar = app.groups["viewer.toolbar"]
        XCTAssertTrue(toolbar.waitForExistence(timeout: 3))
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Hide Bottom Toolbar"].click()
        XCTAssertTrue(toolbar.waitForNonExistence(timeout: 3))

        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Show Bottom Toolbar"].click()
        XCTAssertTrue(toolbar.waitForExistence(timeout: 3))
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

        XCTAssertTrue(app.groups["viewer.canvas"].waitForExistence(timeout: 3))
        app.menuBars.menuBarItems["Animation"].click()
        let pauseItem = app.menuItems["Pause Animation"]
        let playItem = app.menuItems["Play Animation"]
        XCTAssertTrue((pauseItem.exists && pauseItem.isEnabled) || (playItem.exists && playItem.isEnabled))
    }

    @MainActor
    func testEXIFOverlayTogglesForHEICAndHidesForImageWithoutEXIF() {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Static/exif.heic")
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-LightViewUITestOpenPath", fixtureURL.path,
        ]
        app.launch()

        XCTAssertTrue(app.groups["viewer.canvas"].waitForExistence(timeout: 3))
        let overlay = app.descendants(matching: .any)["viewer.exifOverlay"]
        XCTAssertFalse(overlay.exists)

        app.typeKey("e", modifierFlags: [])
        XCTAssertTrue(overlay.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Fixture Camera"].exists)

        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        XCTAssertTrue(overlay.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testClosingLastViewerDisablesViewerMenuTargets() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightView-UI-Menu-Lifecycle", isDirectory: true)
        try? FileManager.default.removeItem(at: folderURL)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let onePixelPNG = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+AvwNkwAAAABJRU5ErkJggg=="
        )!
        try onePixelPNG.write(to: folderURL.appendingPathComponent("01.png"), options: .atomic)
        try onePixelPNG.write(to: folderURL.appendingPathComponent("02.png"), options: .atomic)

        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-LightViewUITestOpenPath", folderURL.path,
        ]
        app.launch()

        XCTAssertTrue(app.groups["viewer.canvas"].waitForExistence(timeout: 3))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForNonExistence(timeout: 3))
        app.menuBars.menuBarItems["Slideshow"].click()
        XCTAssertTrue(app.menuItems["Start Slideshow"].exists)
        XCTAssertFalse(app.menuItems["Start Slideshow"].isEnabled)
    }
}
