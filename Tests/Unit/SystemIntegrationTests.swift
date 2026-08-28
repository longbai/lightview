import CoreGraphics
import Foundation
import XCTest
@testable import LightViewCore

final class SystemIntegrationTests: XCTestCase {
    func testRevealAndOpenWithStandardizeOnlyTheCurrentURL() {
        let workspace = WorkspaceSpy()
        let integration = SystemIntegration(workspace: workspace)
        let source = URL(fileURLWithPath: "/tmp/gallery/../current.png")
        let application = URL(fileURLWithPath: "/Applications/Preview.app")

        integration.revealInFinder(source)
        integration.openWith(source, applicationURL: application)

        XCTAssertEqual(workspace.revealedURLs, [source.standardizedFileURL])
        XCTAssertEqual(workspace.openedURLs, [source.standardizedFileURL])
        XCTAssertEqual(workspace.applicationURL, application.standardizedFileURL)
    }

    func testInformationRowsContainStableImageAndFileFields() {
        let url = URL(fileURLWithPath: "/tmp/photo.png")
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let model = ImageInformationModel(
            url: url,
            format: .png,
            frameCount: 3,
            metadata: ImageMetadata(
                pixelSize: CGSize(width: 4_000, height: 2_000),
                colorProfileDescription: "Display P3",
                fileByteCount: 2_048
            ),
            creationDate: nil,
            modificationDate: modified
        )

        XCTAssertEqual(model.value(for: .name), "photo.png")
        XCTAssertEqual(model.value(for: .path), url.path)
        XCTAssertEqual(model.value(for: .bytes), "2 KB")
        XCTAssertEqual(model.value(for: .pixelSize), "4000 × 2000")
        XCTAssertEqual(model.value(for: .format), "PNG")
        XCTAssertEqual(model.value(for: .frameCount), "3")
        XCTAssertEqual(model.value(for: .colorProfile), "Display P3")
        XCTAssertNotNil(model.value(for: .modificationDate))
    }

    func testAppearanceAndBackgroundPreferencesValidateStoredValues() throws {
        let suite = "SystemIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = PreferencesStore(defaults: defaults)

        store.appearance = .dark
        store.viewerBackground = .customColor
        store.customBackgroundColorHex = "#1A2B3CFF"
        store.customBackgroundColorHex = "not-a-color"

        XCTAssertEqual(store.appearance, .dark)
        XCTAssertEqual(store.viewerBackground, .customColor)
        XCTAssertEqual(store.customBackgroundColorHex, "#1A2B3CFF")
        XCTAssertFalse(store.setBackgroundImageURL(URL(fileURLWithPath: "/missing/background.png")))
        XCTAssertNil(store.backgroundImageURL)
    }

    func testBackingScaleDoublesRasterRequestWithoutMovingImageSpaceCenter() {
        var state = DisplayRasterState(
            logicalViewportSize: CGSize(width: 800, height: 600),
            backingScale: 1,
            imageSpaceCenter: CGPoint(x: 1_200, y: 900)
        )

        state.updateBackingScale(2)

        XCTAssertEqual(state.targetPixelSize, CGSize(width: 1_600, height: 1_200))
        XCTAssertEqual(state.imageSpaceCenter, CGPoint(x: 1_200, y: 900))
    }
}

private final class WorkspaceSpy: SystemWorkspaceServing {
    var revealedURLs: [URL] = []
    var openedURLs: [URL] = []
    var applicationURL: URL?

    func reveal(_ urls: [URL]) {
        revealedURLs = urls
    }

    func open(_ urls: [URL], withApplicationAt applicationURL: URL) {
        openedURLs = urls
        self.applicationURL = applicationURL
    }
}
