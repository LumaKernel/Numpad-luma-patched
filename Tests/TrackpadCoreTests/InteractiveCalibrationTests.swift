import XCTest
@testable import TrackpadCore

final class InteractiveCalibrationTests: XCTestCase {
    let four = [Touch(id: 1, x: 0.62, y: 0.82), Touch(id: 2, x: 0.46, y: 0.77), Touch(id: 3, x: 0.38, y: 0.56), Touch(id: 4, x: 0.43, y: 0.18)]
    func testVerticalMiddleUsesBothAxes() throws {
        let points = four.map { PadPoint(x: $0.x, y: $0.y) }
        let ordered = FingerOrdering.ordered(points)
        XCTAssertEqual(Set(ordered[1...2].map(\.x)), Set([0.46, 0.38]))
        let transform = try PadTransform.calibrating(points, layout: .left)
        let actual = Array(ordered[1...2]).map(transform.apply)
        XCTAssertEqual(actual[0].x, KeypadLayout.left.center(of: "×").x, accuracy: 1e-8)
        XCTAssertEqual(actual[1].y, KeypadLayout.left.center(of: "−").y, accuracy: 1e-8)
    }
    func testFourStartsImmediatelyAndLocksIDsWhileDragging() {
        var gesture = InteractiveCalibrationGesture()
        let first = gesture.process(four, at: 0, allowFour: true)
        XCTAssertEqual(first.phase, .began)
        let moved = four.reversed().map { Touch(id: $0.id, x: 1 - $0.x, y: 1 - $0.y) }
        let next = gesture.process(moved, at: 2, allowFour: true)
        XCTAssertEqual(next.phase, .changed)
        XCTAssertEqual(next.points, first.points?.map { PadPoint(x: 1 - $0.x, y: 1 - $0.y) })
        _ = gesture.process(Array(moved.prefix(2)), at: 2.1, allowFour: true)
        let end = gesture.process([], at: 2.2, allowFour: true)
        XCTAssertEqual(end.phase, .ended)
        XCTAssertEqual(end.points, next.points)
    }
    func testFourLiftSettingAndDisabledOption() {
        var gesture = InteractiveCalibrationGesture()
        XCTAssertNil(gesture.process(four, at: 0, allowFour: true, timing: .liftOff).phase)
        XCTAssertEqual(gesture.process([], at: 0.1, allowFour: true, timing: .liftOff).phase, .ended)
        XCTAssertEqual(gesture.process(four, at: 1, allowFour: false).phase, .cancelled)
        XCTAssertNil(gesture.process([], at: 1.1, allowFour: false).points)
    }
    func testThreeDragSuppressionLatch() {
        var suppression = ThreeFingerDragSuppression()
        suppression.update(contactCount: 3, enabled: true)
        suppression.update(contactCount: 1, enabled: true)
        XCTAssertTrue(suppression.active)
        suppression.update(contactCount: 0, enabled: true)
        XCTAssertFalse(suppression.active)
    }
}
