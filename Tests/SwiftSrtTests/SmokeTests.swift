import XCTest
@testable import SwiftSrt

final class SmokeTests: XCTestCase {
    func testModuleLoads() throws {
        XCTAssertEqual(ControlTypes.shutdown.rawValue, 5)
    }
}
