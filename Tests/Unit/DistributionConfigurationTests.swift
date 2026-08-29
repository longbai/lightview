import Foundation
import XCTest

final class DistributionConfigurationTests: XCTestCase {
    func testDirectAndAppStoreEntitlementsAreMinimalAndDistinct() throws {
        let direct = try dictionary(at: root.appendingPathComponent("Config/Direct.entitlements"))
        let appStore = try dictionary(at: root.appendingPathComponent("Config/AppStore.entitlements"))

        XCTAssertNil(direct["com.apple.security.app-sandbox"])
        XCTAssertEqual(appStore["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(appStore["com.apple.security.files.user-selected.read-write"] as? Bool, true)
        XCTAssertEqual(appStore["com.apple.security.files.bookmarks.app-scope"] as? Bool, true)
        for entitlements in [direct, appStore] {
            XCTAssertNil(entitlements["com.apple.security.network.client"])
            XCTAssertNil(entitlements["com.apple.security.network.server"])
        }
    }

    func testEnglishAndSimplifiedChineseContainIdenticalLocalizationKeys() throws {
        let base = try dictionary(at: root.appendingPathComponent("Resources/Base.lproj/Localizable.strings"))
        let chinese = try dictionary(at: root.appendingPathComponent("Resources/zh-Hans.lproj/Localizable.strings"))

        XCTAssertFalse(base.isEmpty)
        XCTAssertEqual(Set(base.keys), Set(chinese.keys))
        XCTAssertTrue(chinese.values.allSatisfy { ($0 as? String)?.isEmpty == false })
    }

    func testBuildConfigurationDeclaresBothDistributionChannels() throws {
        let project = try String(contentsOf: root.appendingPathComponent("LightView.xcodeproj/project.pbxproj"))
        let info = try dictionary(at: root.appendingPathComponent("Resources/Info.plist"))

        XCTAssertTrue(project.contains("Release-AppStore"))
        XCTAssertEqual(info["LightViewDistributionChannel"] as? String, "$(LIGHTVIEW_DISTRIBUTION_CHANNEL)")
    }

    func testApplicationIconIsDeclaredAndBundled() throws {
        let project = try String(contentsOf: root.appendingPathComponent("LightView.xcodeproj/project.pbxproj"))
        let fileManager = FileManager.default

        XCTAssertTrue(project.contains("Assets.xcassets in Resources"))
        XCTAssertTrue(project.contains("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon"))
        XCTAssertTrue(fileManager.fileExists(atPath: root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset/Contents.json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: root.appendingPathComponent("Resources/AppIcon/LightView-master.png").path))
    }

    func testUniversalBuildComparesAssetCatalogsSemantically() throws {
        let script = try String(contentsOf: root.appendingPathComponent("scripts/build-universal.sh"))

        XCTAssertTrue(script.contains("! -name Assets.car"))
        XCTAssertTrue(script.contains("assetutil --info"))
        XCTAssertTrue(script.contains("plutil -remove 0"))
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func dictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(value as? [String: Any])
    }
}
