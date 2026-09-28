import XCTest
@testable import HerProofKit

final class TimeUtilTests: XCTestCase {
    func testTrailingZIsDroppedNotApplied() {
        // A model sometimes appends Z to a time it read off a screen. Converting
        // it would move the incident to an hour she did not live.
        XCTAssertEqual(TimeUtil.parse("2026-02-03T14:05:00Z"), TimeUtil.parse("2026-02-03T14:05:00"))
    }

    func testOffsetIsDroppedNotApplied() {
        XCTAssertEqual(TimeUtil.parse("2026-02-03T14:05:00-08:00"), TimeUtil.parse("2026-02-03T14:05:00"))
        XCTAssertEqual(TimeUtil.parse("2026-02-03T14:05:00+0530"), TimeUtil.parse("2026-02-03T14:05:00"))
    }

    func testDateOnlyAndMicrosecondsBothParse() {
        XCTAssertNotNil(TimeUtil.parse("2026-02-03"))
        XCTAssertNotNil(TimeUtil.parse("2026-09-25T19:19:26.763666"))
        XCTAssertNotNil(TimeUtil.parse("2026-02-03 14:05"))
    }

    func testUnparseableAndEmptyGiveNil() {
        XCTAssertNil(TimeUtil.parse(nil))
        XCTAssertNil(TimeUtil.parse("   "))
        XCTAssertNil(TimeUtil.parse("yesterday evening"))
    }

    func testRoundTripKeepsTheWallClock() {
        XCTAssertEqual(TimeUtil.iso(TimeUtil.parse("2026-02-03T14:05:00")), "2026-02-03T14:05:00")
    }

    func testDaysBetweenIsFloored() {
        let start = TimeUtil.parse("2026-01-01T00:00:00")!
        let end = TimeUtil.parse("2026-01-11T23:00:00")!
        XCTAssertEqual(TimeUtil.days(from: start, to: end), 10)
    }
}
