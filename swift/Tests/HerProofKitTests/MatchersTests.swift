import XCTest
@testable import HerProofKit

final class MatchersTests: XCTestCase {
    private func categories(_ text: String) -> [String] {
        Matchers.classify(text).map(\.category)
    }

    func testMonitoringMatchesTheQuestionAndTheWhoWith() {
        XCTAssertEqual(categories("where are you and who are you with"), ["Monitoring"])
    }

    func testDegradationCarriesItsCaveat() {
        let hits = Matchers.classify("nobody else would ever want you")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].category, "Degradation")
        XCTAssertEqual(hits[0].prevalence, "20.4%")
        XCTAssertTrue(hits[0].measured)
        XCTAssertNotNil(hits[0].caveat)
    }

    func testTypographicApostropheStillMatches() {
        // The curly apostrophe an iPhone inserts must not be the reason a
        // threat is missed.
        XCTAssertEqual(categories("that never happened, you\u{2019}re imagining it"), ["Reality denial"])
        XCTAssertEqual(categories("you\u{2019}re crazy"), ["Reality denial"])
    }

    func testRealityDenialIsSurfacedWithoutAPrevalenceFigure() {
        let hits = Matchers.classify("i never said that")
        XCTAssertEqual(hits.count, 1)
        XCTAssertFalse(hits[0].measured)
        XCTAssertNil(hits[0].nisvs)
        XCTAssertNil(hits[0].prevalence)
    }

    func testOneHitPerCategoryEvenWhenTwoPatternsFire() {
        let hits = Matchers.classify("where are you, send me a pic, every hour")
        XCTAssertEqual(hits.filter { $0.category == "Monitoring" }.count, 1)
    }

    func testSpanIsTheWordsThatMatched() {
        let hits = Matchers.classify("i will hurt you")
        XCTAssertEqual(hits.first?.category, "Threats of harm")
        XCTAssertEqual(hits.first?.span, "i will hurt you")
    }

    func testOrdinaryMessagesAreNotFlagged() {
        XCTAssertTrue(Matchers.classify("running late, see you at seven").isEmpty)
        XCTAssertTrue(Matchers.classify("").isEmpty)
    }

    func testOnlyTheOtherPersonIsClassified() {
        let messages = [
            Message(sender: .selfSender, text: "where are you"),
            Message(sender: .other, text: "where are you"),
            Message(sender: .system, text: "where are you"),
            Message(sender: .other, text: "where are you", attachment: true),
        ]
        let enriched = Matchers.enrich(messages)
        XCTAssertTrue(enriched[0].flags.isEmpty)
        XCTAssertEqual(enriched[1].flags.count, 1)
        XCTAssertTrue(enriched[2].flags.isEmpty)
        XCTAssertTrue(enriched[3].flags.isEmpty)
    }

    func testSummaryCountsAndDatesTheRun() {
        let first = TimeUtil.parse("2026-01-02T09:00:00")
        let last = TimeUtil.parse("2026-03-04T21:30:00")
        let messages = Matchers.enrich([
            Message(sender: .other, text: "where are you", timestamp: first),
            Message(sender: .other, text: "who are you with", timestamp: last),
            Message(sender: .other, text: "you are worthless", timestamp: first),
        ])
        let summary = Matchers.summary(messages)
        XCTAssertEqual(summary.first?.category, "Monitoring")
        XCTAssertEqual(summary.first?.count, 2)
        XCTAssertEqual(summary.first?.first, first)
        XCTAssertEqual(summary.first?.last, last)
    }

    func testEveryPatternCompiles() {
        for category in Matchers.categories {
            for pattern in category.patterns {
                XCTAssertNoThrow(
                    try NSRegularExpression(pattern: pattern),
                    "\(category.name) has an unusable pattern: \(pattern)"
                )
            }
        }
    }

    func testMeasuredCategoriesAllCarryAFigure() {
        for category in Matchers.categories where category.measured {
            XCTAssertNotNil(category.prevalence, "\(category.name) is measured but has no prevalence")
        }
    }
}
