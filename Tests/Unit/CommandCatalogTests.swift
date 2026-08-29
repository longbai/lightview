import XCTest
@testable import LightViewCore

final class CommandCatalogTests: XCTestCase {
    func testCommandIdentifiersAreUnique() {
        let definitions = CommandCatalog.all
        XCTAssertEqual(Set(definitions.map(\.identifier)).count, definitions.count)
    }

    func testPrincipalShortcutTableMatchesDocumentedDefaults() {
        let shortcuts = Dictionary(uniqueKeysWithValues: CommandCatalog.all.map {
            ($0.identifier, $0.shortcutDescription)
        })

        XCTAssertEqual(shortcuts[.open], "⌘O")
        XCTAssertEqual(shortcuts[.newWindow], "⌘N")
        XCTAssertEqual(shortcuts[.previous], "←")
        XCTAssertEqual(shortcuts[.next], "→")
        XCTAssertEqual(shortcuts[.fit], "F")
        XCTAssertEqual(shortcuts[.fill], "⇧F")
        XCTAssertEqual(shortcuts[.actualSize], "1")
        XCTAssertEqual(shortcuts[.togglePlayback], "Space")
        XCTAssertEqual(shortcuts[.toggleSlideshow], "Return")
        XCTAssertEqual(shortcuts[.startReverseSlideshow], "⇧Return")
        XCTAssertEqual(shortcuts[.toggleEXIFOverlay], "E")
        XCTAssertEqual(shortcuts[.exportMP4], "⌘E")
    }

    func testViewerToolbarContainsUniqueSupportedCommandsInDisplayOrder() {
        XCTAssertEqual(ViewerToolbarCatalog.groups, [
            [.previous, .next],
            [.zoomOut, .zoomIn, .fit, .actualSize],
            [.rotateLeft, .rotateRight, .flipHorizontal],
            [.information, .toggleFullScreen],
        ])
        XCTAssertEqual(Set(ViewerToolbarCatalog.all).count, ViewerToolbarCatalog.all.count)
        XCTAssertTrue(ViewerToolbarCatalog.all.allSatisfy { command in
            CommandCatalog.all.contains(where: { $0.identifier == command })
        })
    }
}
