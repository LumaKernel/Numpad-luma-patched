import XCTest
@testable import TrackpadCore

final class ClickFilterTests: XCTestCase {
    func testPhysicalClickAndPressurelessReleasePassDuringTouch() {
        var filter = ClickFilter()
        XCTAssertTrue(filter.down(button: 0, pressure: 1, recentTrackpadTouch: true))
        XCTAssertTrue(filter.drag(button: 0))
        XCTAssertTrue(filter.up(button: 0))
    }
    func testTapClickSuppressesWholePairAndDrag() {
        var filter = ClickFilter()
        XCTAssertFalse(filter.down(button: 0, pressure: 0, recentTrackpadTouch: true))
        XCTAssertFalse(filter.drag(button: 0))
        XCTAssertFalse(filter.up(button: 0))
    }
    func testMouseWithoutTrackpadContactAndUnmatchedReleasePass() {
        var filter = ClickFilter()
        XCTAssertTrue(filter.down(button: 0, pressure: 0, recentTrackpadTouch: false))
        XCTAssertTrue(filter.up(button: 0))
        XCTAssertTrue(filter.up(button: 1))
    }
    func testButtonsMaintainIndependentDecisions() {
        var filter = ClickFilter()
        XCTAssertFalse(filter.down(button: 0, pressure: 0, recentTrackpadTouch: true))
        XCTAssertTrue(filter.down(button: 1, pressure: 1, recentTrackpadTouch: true))
        XCTAssertFalse(filter.up(button: 0))
        XCTAssertTrue(filter.up(button: 1))
    }
}
