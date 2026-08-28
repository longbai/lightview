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
        XCTAssertEqual(shortcuts[.exportMP4], "⌘E")
    }
}
