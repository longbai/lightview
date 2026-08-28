import Foundation
import XCTest

final class MovieExportSmokeTests: XCTestCase {
    @MainActor
    func testExportPanelExposesAllNativeControls() throws {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightView-Export-Fixture.png")
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

        app.typeKey("e", modifierFlags: .command)

        XCTAssertTrue(app.windows["export.window"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.popUpButtons["export.sourceScope"].exists)
        XCTAssertTrue(app.popUpButtons["export.preset"].exists)
        XCTAssertTrue(app.popUpButtons["export.composition"].exists)
        XCTAssertTrue(app.popUpButtons["export.transition"].exists)
        XCTAssertTrue(app.textFields["export.staticDuration"].exists)
        XCTAssertTrue(app.popUpButtons["export.animationPolicy"].exists)
        XCTAssertTrue(app.textFields["export.maximumDuration"].exists)
        XCTAssertTrue(app.popUpButtons["export.background"].exists)
        XCTAssertTrue(app.buttons["export.chooseBackground"].exists)
        XCTAssertTrue(app.progressIndicators["export.progress"].exists)
        XCTAssertTrue(app.buttons["export.start"].exists)
        XCTAssertTrue(app.buttons["export.cancel"].exists)
    }
}
