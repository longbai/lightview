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
                dpi: CGSize(width: 300, height: 300),
                bitDepth: 16,
                colorModel: "RGB",
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
        XCTAssertEqual(model.value(for: .dpi), "300 × 300 DPI")
        XCTAssertEqual(model.value(for: .bitDepth), "16-bit")
        XCTAssertEqual(model.value(for: .colorModel), "RGB")
        XCTAssertEqual(model.value(for: .colorProfile), "Display P3")
        XCTAssertNotNil(model.value(for: .modificationDate))
    }

    func testRichViewerTitleCombinesQViewAndToviDetailsAndDistinguishesHEIC() {
        let title = ViewerTitleFormatter.title(
            url: URL(fileURLWithPath: "/tmp/IMG_1234.HEIC"),
            format: .heif,
            metadata: ImageMetadata(
                pixelSize: CGSize(width: 6_000, height: 4_000),
                fileByteCount: 8 * 1_024 * 1_024
            ),
            frameCount: 24,
            index: 2,
            totalCount: 42,
            presentationScale: 0.25,
            rotationDegrees: 90
        )

        XCTAssertEqual(
            title,
            "3/42 · IMG_1234.HEIC · 25% · 1000×1500 → 6000×4000 · 8 MB · HEIC · 24 frames · LightView"
        )
    }

    func testEXIFRowsOnlyContainAvailableMeaningfulFields() {
        let exif = ImageEXIFMetadata(
            capturedAt: "2026:08:29 10:11:12",
            cameraMake: "Apple",
            cameraModel: "iPhone",
            lensModel: "Main Camera",
            focalLengthMM: 6.8,
            focalLength35MM: 24,
            aperture: 1.8,
            exposureTimeSeconds: 1.0 / 125,
            iso: 80,
            latitude: 31.2304,
            longitude: 121.4737
        )
        let model = ImageInformationModel(
            url: URL(fileURLWithPath: "/tmp/photo.heic"),
            format: .heif,
            frameCount: 1,
            metadata: ImageMetadata(pixelSize: CGSize(width: 4_032, height: 3_024), exif: exif),
            creationDate: nil,
            modificationDate: nil
        )

        XCTAssertEqual(model.exifRows.first, EXIFInformationRow(label: "Captured", value: "2026:08:29 10:11:12"))
        XCTAssertTrue(model.exifRows.contains(EXIFInformationRow(label: "Camera", value: "Apple iPhone")))
        XCTAssertTrue(model.exifRows.contains(EXIFInformationRow(label: "Exposure", value: "1/125 s")))
        XCTAssertTrue(model.exifRows.contains(EXIFInformationRow(label: "GPS", value: "31.230400, 121.473700")))

        let empty = ImageInformationModel(
            url: URL(fileURLWithPath: "/tmp/plain.png"),
            format: .png,
            frameCount: 1,
            metadata: ImageMetadata(pixelSize: CGSize(width: 10, height: 10)),
            creationDate: nil,
            modificationDate: nil
        )
        XCTAssertTrue(empty.exifRows.isEmpty)
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
