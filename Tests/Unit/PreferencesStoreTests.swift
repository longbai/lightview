import Foundation
import XCTest
@testable import LightViewCore

final class PreferencesStoreTests: XCTestCase {
    func testInvalidZoomStepRestoresDefault() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        store.zoomStep = 0

        XCTAssertEqual(store.zoomStep, PreferencesStore.defaultZoomStep)
    }

    func testPreloadRawValuesDecodeOnlyKnownLevels() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        defaults.set(PreloadLevel.two.rawValue, forKey: PreferencesStore.Key.preloadLevel.rawValue)
        XCTAssertEqual(store.preloadLevel, .two)

        defaults.set(99, forKey: PreferencesStore.Key.preloadLevel.rawValue)
        XCTAssertEqual(store.preloadLevel, .one)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "LightViewPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
