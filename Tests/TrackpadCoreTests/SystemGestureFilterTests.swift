import XCTest
@testable import TrackpadCore
final class SystemGestureFilterTests: XCTestCase {
    func testAllGesturePacketsAreSubscribed() {
        for type: UInt32 in [29, 30, 31] {
            XCTAssertTrue(SystemGestureFilter.isGesture(type))
            XCTAssertNotEqual(SystemGestureFilter.eventMask & (1 << type), 0)
        }
        for type: UInt32 in [1, 2, 5, 10, 11, 22, 23, 24, 25, 32] {
            XCTAssertFalse(SystemGestureFilter.isGesture(type))
            XCTAssertEqual(SystemGestureFilter.eventMask & (1 << type), 0)
        }
    }
}
