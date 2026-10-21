import XCTest
@testable import TrackpadCore

final class RightModifierChordTests: XCTestCase {
    func testOnlyRightCommandAndRightOptionActivateOnce() {
        var chord = RightModifierChord()
        for flags: UInt64 in [0, 0x80060, 0x100008, 0x180028, 0x180048, 0x180030, 0x180010] {
            XCTAssertFalse(chord.update(flags: flags))
        }
        XCTAssertTrue(chord.update(flags: 0x180050))
        XCTAssertFalse(chord.update(flags: 0x180050))
        XCTAssertFalse(chord.update(flags: 0x100010))
        XCTAssertTrue(chord.update(flags: 0x180050))
    }
    func testRejectsExtraModifiersAndAcceptsEitherOrder() {
        var chord = RightModifierChord()
        XCTAssertFalse(chord.update(flags: 0x1A0050))
        XCTAssertFalse(chord.update(flags: 0x1C0050))
        XCTAssertFalse(chord.update(flags: 0x180070))
        XCTAssertFalse(chord.update(flags: 0x180058))
        chord.reset()
        XCTAssertFalse(chord.update(flags: 0x80040))
        XCTAssertTrue(chord.update(flags: 0x180050))
    }
}
