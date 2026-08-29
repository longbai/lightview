import Foundation
import XCTest

final class AccessibilityTests: XCTestCase {
    @MainActor
    func testEnglishAndSimplifiedChineseActionControlsHaveLabels() {
        for language in ["en", "zh-Hans"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-ApplePersistenceIgnoreState", "YES",
                "-AppleLanguages", "(\(language))",
                "-LightViewUITestEmptyWindow", "YES",
                "-LightViewUITestShowPreferences", "YES",
            ]
            app.launch()

            assertLabeled(app.buttons["welcome.openButton"])
            assertLabeled(app.popUpButtons["preferences.appearance"])
            assertLabeled(app.popUpButtons["preferences.background"])
            assertLabeled(app.checkBoxes["preferences.navigationWraps"])
            app.terminate()
        }
    }

    @MainActor
    func testExportControlsHaveAccessibilityLabels() throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("LightView-Accessibility.png")
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+AvwNkwAAAABJRU5ErkJggg==")!
            .write(to: fixture, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-LightViewUITestOpenPath", fixture.path]
        app.launch()
        XCTAssertTrue(app.groups["viewer.canvas"].waitForExistence(timeout: 5))
        app.typeKey("e", modifierFlags: .command)

        for identifier in ["export.sourceScope", "export.preset", "export.composition", "export.transition", "export.animationPolicy", "export.background"] {
            assertLabeled(app.popUpButtons[identifier])
        }
        for identifier in ["export.chooseBackground", "export.start", "export.cancel"] {
            assertLabeled(app.buttons[identifier])
        }
    }

    @MainActor
    func testViewerToolbarControlsHaveAccessibilityLabels() {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Static/alpha.png")
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-LightViewUITestOpenPath", fixture.path,
        ]
        app.launch()

        for identifier in [
            "previous", "next", "zoomOut", "zoomIn", "fit", "actualSize",
            "rotateLeft", "rotateRight", "flipHorizontal", "information", "toggleFullScreen",
        ] {
            assertLabeled(app.buttons["viewer.toolbar.\(identifier)"])
        }
    }

    @MainActor
    private func assertLabeled(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertFalse(element.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, file: file, line: line)
        XCTAssertTrue(element.isEnabled, file: file, line: line)
    }
}
