import XCTest
@testable import TrackpadCore

final class CalibrationTests: XCTestCase {
    private func assertPoint(_ actual: PadPoint, _ expected: PadPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-9, file: file, line: line)
    }
    private func touch(_ id: Int32, _ x: Double, _ y: Double) -> Touch { Touch(id: id, x: x, y: y) }
    private var three: [Touch] { [touch(1, 0.2, 0.2), touch(2, 0.45, 0.55), touch(3, 0.7, 0.35)] }
    private var four: [Touch] { [touch(1, 0.1, 0.2), touch(2, 0.4, 0.3), touch(3, 0.6, 0.5), touch(4, 0.9, 0.3)] }

    func testLeftLayoutSeparatesOperationsAndAllNumbers() {
        let rows = [["⌫", "÷", "7", "8", "9"], ["×", "−", "4", "5", "6"],
                    ["+", "↵", "1", "2", "3"], ["+", "↵", "0", "0", "."]]
        for row in 0..<4 {
            for col in 0..<5 {
                XCTAssertEqual(PadKey.at(x: (Double(col) + 0.5) / 5, y: 1 - (Double(row) + 0.5) / 4,
                                        layout: .left)?.label, rows[row][col])
            }
        }
        var tap = AnchoredTapRecognizer(layout: .left)
        _ = tap.process([touch(1, 0.7, 0.625)], at: 1)
        XCTAssertEqual(tap.process([], at: 1.1)?.label, "5")
    }

    func testRigidUndoesOnlyRotationAndTranslation() throws {
        let logical = ["3", "5", "6"].map { KeypadLayout.left.center(of: $0) }
        let angle = -Double.pi / 3, aspect = PadGeometry.aspectRatio
        let physical = PadTransform(a: cos(angle), b: -sin(angle) / aspect,
            c: sin(angle) * aspect, d: cos(angle), tx: -0.1, ty: 1.4)
        let source = logical.map { physical.apply($0) }
        let fitted = try PadTransform.rigid(source: source, target: logical)
        XCTAssertTrue(fitted.isRigid)
        for (raw, expected) in zip(source, logical) { assertPoint(fitted.apply(raw), expected) }
        for point in [PadPoint(x: 0, y: 0), .init(x: 0.4, y: 0.6), .init(x: 1, y: 1)] {
            assertPoint(fitted.apply(physical.apply(point)), point)
            assertPoint(fitted.inverse.apply(fitted.apply(point)), point)
        }
    }

    func testThreeFingerAssignmentUses456AndAdjustsScaleForEitherLayout() throws {
        for layout in KeypadLayout.allCases {
            let angle = -0.2, aspect = PadGeometry.aspectRatio, scale = 0.7
            let physical = PadTransform(a: scale * cos(angle), b: -scale * sin(angle) / aspect,
                c: scale * sin(angle) * aspect, d: scale * cos(angle), tx: 0.08, ty: 0.2)
            let labels = ["4", "5", "6"]
            let source = labels.map { physical.apply(layout.center(of: $0)) }
            let transform = try PadTransform.calibrating(source.reversed(), layout: layout)
            XCTAssertTrue(transform.isSimilarity)
            XCTAssertFalse(transform.isRigid)
            for (point, label) in zip(source, labels) {
                assertPoint(transform.apply(point), layout.center(of: label))
                XCTAssertEqual(PadKey.at(x: transform.apply(point).x, y: transform.apply(point).y, layout: layout)?.label, label)
            }
        }
    }

    func testMiddleFingerPinsFiveAndOuterFingersOnlySetScaleAndRotation() throws {
        for layout in KeypadLayout.allCases {
            let source = [PadPoint(x: 0.2, y: 0.4), .init(x: 0.43, y: 0.53), .init(x: 0.7, y: 0.42)]
            let transform = try PadTransform.calibrating(source, layout: layout, preserveOrder: true)
            XCTAssertTrue(transform.isSimilarity)
            assertPoint(transform.apply(source[1]), layout.center(of: "5"))
            let movedMiddle = [source[0], PadPoint(x: 0.49, y: 0.62), source[2]]
            let moved = try PadTransform.calibrating(movedMiddle, layout: layout, preserveOrder: true)
            assertPoint(moved.apply(movedMiddle[1]), layout.center(of: "5"))
            // Moving the anchor changes translation, never rotation or scale.
            XCTAssertEqual(transform.a, moved.a, accuracy: 1e-9)
            XCTAssertEqual(transform.b, moved.b, accuracy: 1e-9)
            XCTAssertEqual(transform.c, moved.c, accuracy: 1e-9)
            XCTAssertEqual(transform.d, moved.d, accuracy: 1e-9)
            let display = transform.inverse
            let four = display.apply(layout.center(of: "4"))
            let six = display.apply(layout.center(of: "6"))
            XCTAssertEqual(six.x - four.x, source[2].x - source[0].x, accuracy: 1e-9)
            XCTAssertEqual(six.y - four.y, source[2].y - source[0].y, accuracy: 1e-9)
        }
    }

    func testFourFingerMiddleTwoMatchExactlyWithUniformScale() throws {
        let source = four.map { PadPoint(x: $0.x, y: $0.y) }
        for layout in KeypadLayout.allCases {
            let fitted = try PadTransform.calibrating([source[3], source[1], source[0], source[2]], layout: layout)
            XCTAssertTrue(fitted.isSimilarity)
            assertPoint(fitted.apply(source[1]), layout.center(of: "×"))
            assertPoint(fitted.apply(source[2]), layout.center(of: "−"))
        }
    }

    func testDifferentFingerSpacingCannotScaleKeys() throws {
        let fitted = try PadTransform.rigid(source: [.init(x: 0.2, y: 0.4), .init(x: 0.8, y: 0.4)],
            target: [.init(x: 0.4, y: 0.7), .init(x: 0.6, y: 0.7)])
        XCTAssertTrue(fitted.isRigid)
        XCTAssertEqual(fitted.a, 1, accuracy: 1e-9)
        XCTAssertEqual(fitted.d, 1, accuracy: 1e-9)
        XCTAssertEqual(fitted.ty, 0.3, accuracy: 1e-9)
    }

    func testCollinearContactsWorkAndInvalidContactsAreRejected() throws {
        let target = ["3", "5", "6"].map { KeypadLayout.left.center(of: $0) }
        XCTAssertTrue(try PadTransform.rigid(source: [.init(x: 0.1, y: 0.3), .init(x: 0.3, y: 0.3), .init(x: 0.5, y: 0.3)], target: target).isRigid)
        XCTAssertThrowsError(try PadTransform.rigid(source: [.init(x: 0.3, y: 0.3), .init(x: 0.301, y: 0.3)], target: Array(target.prefix(2))))
        XCTAssertThrowsError(try PadTransform.calibrating([.init(x: .nan, y: 0.3), .init(x: 0.4, y: 0.6), .init(x: 0.8, y: 0.3)], layout: .left))
        XCTAssertFalse(PadTransform(a: 2, b: 0, c: 0, d: 2, tx: 0, ty: 0).isRigid)
    }

    func testThreeFingerTapCommitsOnlyAfterLastLift() {
        var gesture = CalibrationGesture()
        XCTAssertFalse(gesture.process(Array(three.prefix(1)), at: 1, allowFour: false).consumed)
        XCTAssertFalse(gesture.process(Array(three.prefix(2)), at: 1.03, allowFour: false).consumed)
        XCTAssertTrue(gesture.process(three, at: 1.06, allowFour: false).consumed)
        XCTAssertNil(gesture.process(Array(three.prefix(2)), at: 1.1, allowFour: false).points)
        let final = gesture.process([], at: 1.15, allowFour: false)
        XCTAssertTrue(final.consumed)
        XCTAssertEqual(final.points?.count, 3)
        XCTAssertFalse(gesture.process([], at: 2, allowFour: false).consumed)
    }

    func testFourFingerOptionPreventsAccidentalThreeFingerCalibration() {
        for enabled in [false, true] {
            var gesture = CalibrationGesture()
            _ = gesture.process(Array(four.prefix(3)), at: 1, allowFour: enabled)
            _ = gesture.process(four, at: 1.03, allowFour: enabled)
            _ = gesture.process(Array(four.prefix(3)), at: 1.07, allowFour: enabled)
            let final = gesture.process([], at: 1.12, allowFour: enabled)
            XCTAssertTrue(final.consumed)
            XCTAssertEqual(final.points?.count, enabled ? 4 : nil)
        }
    }

    func testMovingLongOrNonSimultaneousContactsCannotCalibrate() {
        var moving = CalibrationGesture()
        _ = moving.process(three, at: 1, allowFour: true)
        _ = moving.process([touch(1, 0.3, 0.2)] + Array(three.dropFirst()), at: 1.03, allowFour: true)
        XCTAssertNil(moving.process([], at: 1.1, allowFour: true).points)
        var long = CalibrationGesture()
        _ = long.process(three, at: 1, allowFour: true)
        XCTAssertNil(long.process([], at: 2, allowFour: true).points)
        var staggered = CalibrationGesture()
        _ = staggered.process(Array(three.prefix(1)), at: 1, allowFour: true)
        _ = staggered.process(three, at: 1.2, allowFour: true)
        XCTAssertNil(staggered.process([], at: 1.3, allowFour: true).points)
    }

    func testNewSmallCenterRegionReportsEntryAndExitWithHysteresis() {
        var feedback = CenterCrossingFeedback(layout: .left)
        func point(_ offset: Double) -> [Touch] { [touch(1, 0.7 + offset, 0.625)] }
        XCTAssertFalse(feedback.process(point(0.1)))
        XCTAssertFalse(feedback.process(point(0.03)))
        XCTAssertTrue(feedback.process(point(0.003)))
        XCTAssertFalse(feedback.process(point(0.009)))
        XCTAssertTrue(feedback.process(point(0.012)))
        XCTAssertFalse(feedback.process(point(0.03)))
        XCTAssertTrue(feedback.process(point(0.003)))
        XCTAssertFalse(feedback.process([]))
    }
}
