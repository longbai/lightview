import Foundation
import XCTest

final class PreferencesAndInfoSmokeTests: XCTestCase {
    @MainActor
    func testPreferencesWindowExposesNativeControls() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-LightViewUITestShowPreferences", "YES",
        ]
        app.launch()

        XCTAssertTrue(app.windows["preferences.window"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.popUpButtons["preferences.appearance"].exists)
        XCTAssertTrue(app.popUpButtons["preferences.background"].exists)
        XCTAssertTrue(app.checkBoxes["preferences.navigationWraps"].exists)
    }

    @MainActor
    func testInformationWindowShowsCurrentFilename() throws {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightView-Info-Fixture.png")
        let onePixelPNG = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+AvwNkwAAAABJRU5ErkJggg=="
        )!
        try onePixelPNG.write(to: fixtureURL, options: .atomic)

        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-LightViewUITestShowInfoPath", fixtureURL.path,
        ]
        app.launch()

        XCTAssertTrue(app.windows["information.window"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts[fixtureURL.lastPathComponent].exists)
        XCTAssertTrue(app.staticTexts["information.avifRequirement"].exists)

        let informationWindow = app.windows["information.window"]
        app.typeKey("i", modifierFlags: .command)
        XCTAssertTrue(informationWindow.waitForNonExistence(timeout: 3))

        app.typeKey("i", modifierFlags: .command)
        XCTAssertTrue(informationWindow.waitForExistence(timeout: 3))
        let informationButton = app.buttons["viewer.toolbar.information"]
        XCTAssertTrue(informationButton.exists)
        informationButton.click()
        XCTAssertTrue(informationWindow.waitForNonExistence(timeout: 3))
    }
}
