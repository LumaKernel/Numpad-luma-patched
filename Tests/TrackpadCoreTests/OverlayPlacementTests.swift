import XCTest
import CoreGraphics
@testable import TrackpadCore

final class OverlayPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let size = CGSize(width: 540, height: 360)

    func testDefaultIsBottomCenter() {
        let frame = OverlayPlacement.place(size: size, on: screen)
        XCTAssertEqual(frame.midX, screen.midX)
        XCTAssertEqual(frame.minY, 24)
        XCTAssertEqual(frame.size, size)
    }
    func testBottomInputIsAvoidedWithoutLeavingScreen() {
        let field = CGRect(x: 400, y: 20, width: 650, height: 120)
        let frame = OverlayPlacement.place(size: size, on: screen, avoiding: field)
        XCTAssertTrue(screen.contains(frame))
        XCTAssertFalse(frame.intersects(field.insetBy(dx: -11, dy: -11)))
    }
    func testUpperInputLeavesDefaultPositionUntouched() {
        let field = CGRect(x: 400, y: 600, width: 650, height: 120)
        XCTAssertEqual(OverlayPlacement.place(size: size, on: screen, avoiding: field),
                       OverlayPlacement.place(size: size, on: screen))
    }
    func testInputNearScreenEdgeCannotPushOverlayOutside() {
        let field = CGRect(x: 0, y: 0, width: 1440, height: 180)
        let frame = OverlayPlacement.place(size: size, on: screen, avoiding: field)
        XCTAssertTrue(screen.contains(frame))
        XCTAssertGreaterThanOrEqual(frame.minY, field.maxY + 12)
    }
    func testFullScreenEditorPrefersUncoveredCaretAndAlwaysFits() {
        let caret = CGRect(x: 700, y: 90, width: 2, height: 24)
        let frame = OverlayPlacement.place(size: size, on: screen, avoiding: screen, caret: caret)
        XCTAssertTrue(screen.contains(frame))
        XCTAssertFalse(frame.intersects(caret.insetBy(dx: -10, dy: -10)))
    }
    func testSmallMonitorScalesOverlayToFit() {
        let small = CGRect(x: 0, y: 0, width: 400, height: 280)
        let frame = OverlayPlacement.place(size: size, on: small, avoiding: small)
        XCTAssertTrue(small.contains(frame))
        XCTAssertEqual(frame.width / frame.height, size.width / size.height, accuracy: 1e-9)
    }
    func testSecondaryMonitorWithNegativeOrigin() {
        let display = CGRect(x: -1920, y: -250, width: 1920, height: 1050)
        let field = CGRect(x: -1300, y: -240, width: 600, height: 100)
        let frame = OverlayPlacement.place(size: size, on: display, avoiding: field)
        XCTAssertTrue(display.contains(frame))
        XCTAssertFalse(frame.intersects(field))
    }
    func testUserPositionIsKeptWhenClearAndClampedWhenOutside() {
        let origin = CGPoint(x: 40, y: 450)
        XCTAssertEqual(OverlayPlacement.place(size: size, preferredOrigin: origin, on: screen).origin, origin)
        let frame = OverlayPlacement.place(size: size, preferredOrigin: CGPoint(x: 5000, y: -5000), on: screen)
        XCTAssertTrue(screen.contains(frame))
        XCTAssertEqual(frame.maxX, screen.maxX - 12)
        XCTAssertEqual(frame.minY, screen.minY + 12)
    }
}
