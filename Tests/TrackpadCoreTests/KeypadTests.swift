import XCTest
@testable import TrackpadCore

final class KeypadTests: XCTestCase {
    func testEveryCellIncludingSpanningKeysAndOrientation() {
        let expected = [
            ["7", "8", "9", "⌫", "÷"], ["4", "5", "6", "×", "−"],
            ["1", "2", "3", "+", "↵"], ["0", "0", ".", "+", "↵"]
        ]
        for row in 0..<4 {
            for column in 0..<5 {
                XCTAssertEqual(PadKey.at(x: (Double(column) + 0.5) / 5,
                                        y: 1 - (Double(row) + 0.5) / 4)?.label, expected[row][column])
            }
        }
        XCTAssertEqual(PadKey.at(x: 0, y: 1)?.label, "7")
        XCTAssertEqual(PadKey.at(x: 1, y: 0)?.label, "↵")
        XCTAssertNil(PadKey.at(x: .nan, y: 0))
        XCTAssertNil(PadKey.at(x: 0.5, y: .infinity))
        XCTAssertNil(PadKey.at(x: -0.01, y: 0))
    }

    func testTapEmitsOnlyOnceAtLiftAndAllowsRepeatedTaps() {
        var recognizer = TapRecognizer()
        let finger = Touch(id: 1, x: 0.3, y: 0.625)
        for time in [1.0, 1.01, 1.03] { XCTAssertNil(recognizer.process([finger], at: time)) }
        XCTAssertEqual(recognizer.process([], at: 1.08)?.label, "5")
        XCTAssertNil(recognizer.process([], at: 1.09))
        XCTAssertNil(recognizer.process([finger], at: 1.1))
        XCTAssertEqual(recognizer.process([], at: 1.2)?.label, "5")
    }

    func testSwipeCannotReturnToOriginAndProduceKey() {
        var recognizer = TapRecognizer()
        let finger = Touch(id: 1, x: 0.3, y: 0.625)
        _ = recognizer.process([finger], at: 1)
        _ = recognizer.process([Touch(id: 1, x: 0.395, y: 0.625)], at: 1.05)
        _ = recognizer.process([finger], at: 1.10)
        XCTAssertNil(recognizer.process([], at: 1.15))
    }

    func testSecondFingerCancelsUntilAllFingersLift() {
        var recognizer = TapRecognizer()
        let finger = Touch(id: 1, x: 0.3, y: 0.625)
        _ = recognizer.process([finger], at: 1)
        _ = recognizer.process([finger, Touch(id: 2, x: 0.8, y: 0.5)], at: 1.03)
        _ = recognizer.process([finger], at: 1.06)
        XCTAssertNil(recognizer.process([], at: 1.10))
        _ = recognizer.process([finger], at: 2)
        XCTAssertEqual(recognizer.process([], at: 2.1)?.label, "5")
    }

    func testRejectsLongPressNoiseAndChangedFingerIdentity() {
        for (end, changedID) in [(1.8, false), (1.01, false), (1.1, true)] {
            var recognizer = TapRecognizer()
            _ = recognizer.process([Touch(id: 1, x: 0.3, y: 0.625)], at: 1)
            if changedID { _ = recognizer.process([Touch(id: 2, x: 0.3, y: 0.625)], at: 1.05) }
            XCTAssertNil(recognizer.process([], at: end))
        }
    }

    func testResetDiscardsPendingInputAndRequiresLiftWhenRequested() {
        var recognizer = TapRecognizer()
        let finger = Touch(id: 1, x: 0.3, y: 0.625)
        _ = recognizer.process([finger], at: 1)
        recognizer.reset(waitForLift: true)
        _ = recognizer.process([finger], at: 1.05)
        XCTAssertNil(recognizer.process([], at: 1.1))
        _ = recognizer.process([finger], at: 2)
        XCTAssertEqual(recognizer.process([], at: 2.1)?.label, "5")
    }

    func testCrossingCellBoundaryCancelsEvenWithSmallMovement() {
        var recognizer = TapRecognizer()
        _ = recognizer.process([Touch(id: 1, x: 0.199, y: 0.625)], at: 1)
        _ = recognizer.process([Touch(id: 1, x: 0.201, y: 0.625)], at: 1.05)
        XCTAssertNil(recognizer.process([], at: 1.1))
    }

    func testInvalidDataCancelsWithoutCrashing() {
        var recognizer = TapRecognizer()
        _ = recognizer.process([Touch(id: 1, x: .nan, y: 0.5)], at: 1)
        XCTAssertNil(recognizer.process([], at: 1.1))
        _ = recognizer.process([Touch(id: 1, x: 0.3, y: 0.625)], at: 2)
        XCTAssertNil(recognizer.process([], at: .nan))
        XCTAssertNil(recognizer.process([], at: 2.1))
    }
}
