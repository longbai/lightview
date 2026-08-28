import Foundation
import XCTest
@testable import LightViewCore

final class BootstrapTests: XCTestCase {
    func testProductIdentityExposesSupportedIntelBaseline() {
        XCTAssertEqual(ProductIdentity.name, "LightView")
        let minimumSystem = ProductIdentity.minimumIntelSystem
        XCTAssertEqual(minimumSystem.majorVersion, 10)
        XCTAssertEqual(minimumSystem.minorVersion, 15)
        XCTAssertEqual(minimumSystem.patchVersion, 0)
    }
}
