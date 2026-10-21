import XCTest
import CoreGraphics
@testable import TrackpadCore
final class OverlaySnapTests: XCTestCase {
    func testBottomCenterAndHysteresis() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let first = OverlaySnap.align(CGRect(x: 455, y: 30, width: 540, height: 360), on: screen)
        XCTAssertEqual(first.frame.origin, CGPoint(x: 450, y: 24))
        XCTAssertEqual(first.verticalGuide, 720)
        XCTAssertEqual(first.horizontalGuide, 24)
        let next = OverlaySnap.align(CGRect(x: 475, y: 30, width: 540, height: 360), on: screen, previous: first)
        XCTAssertEqual(next.frame.minX, 450)
        let outside = OverlaySnap.align(CGRect(x: 490, y: 80, width: 540, height: 360), on: screen, previous: next)
        XCTAssertFalse(outside.hasGuides)
    }
}
