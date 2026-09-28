import XCTest
@testable import HerProofKit

final class OrganizerTests: XCTestCase {
    private func shot(
        _ file: String,
        exif: String? = nil,
        parseError: String? = nil,
        _ messages: [Message]
    ) -> Entry {
        Entry(
            sourceFile: file,
            fileHash: String(repeating: "a", count: 64),
            sourceType: "screenshot",
            exifTimestamp: TimeUtil.parse(exif),
            parseError: parseError,
            messages: messages
        )
    }

    private func other(_ text: String, _ at: String? = nil) -> Message {
        Message(sender: .other, text: text, timestamp: TimeUtil.parse(at))
    }

    func testOverlapBetweenConsecutiveScreenshotsIsCountedOnce() {
        let previous = [other("ok"), other("where are you"), other("answer me")]
        let current = [other("where are you"), other("answer me"), other("i said now")]
        let result = Organizer.removeOverlap(previous: previous, current: current)
        XCTAssertEqual(result.dropped, 2)
        XCTAssertEqual(result.kept.map(\.text), ["i said now"])
    }

    func testTwoGenuinelySeparateOksAreBothKept() {
        // The overlap rule drops a repeated run, never every repeat of a word.
        let previous = [other("ok")]
        let current = [other("see you then"), other("ok")]
        let result = Organizer.removeOverlap(previous: previous, current: current)
        XCTAssertEqual(result.dropped, 0)
        XCTAssertEqual(result.kept.count, 2)
    }

    func testMessagesWithNoSendTimeAreDatedByTheScreenshot() {
        let entries = [shot("IMG_1.PNG", exif: "2026-03-01T11:26:27", [other("where are you")])]
        let timeline = Organizer.organize(entries: entries)
        XCTAssertNil(timeline.messages[0].timestamp)
        XCTAssertEqual(timeline.messages[0].approxTimestamp, TimeUtil.parse("2026-03-01T11:26:27"))
        XCTAssertTrue(timeline.flags.contains { $0.kind == .approxTime })
        XCTAssertTrue(timeline.incidents[0].approximate)
    }

    func testUntimedMessagesSortLastInFileOrder() {
        let entries = [
            Entry(sourceFile: "a.txt", sourceType: "whatsapp", messages: [
                other("no time at all"),
                other("timed", "2026-05-01T10:00:00"),
            ])
        ]
        let timeline = Organizer.organize(entries: entries)
        XCTAssertEqual(timeline.messages.map(\.text), ["timed", "no time at all"])
        XCTAssertTrue(timeline.flags.contains { $0.kind == .noTime })
    }

    func testAGapLongerThanSixHoursStartsANewIncident() {
        let entries = [
            Entry(sourceFile: "a.txt", sourceType: "whatsapp", messages: [
                other("morning", "2026-05-01T08:00:00"),
                other("still morning", "2026-05-01T09:00:00"),
                other("three days later", "2026-05-04T09:00:00"),
            ])
        ]
        let timeline = Organizer.organize(entries: entries)
        XCTAssertEqual(timeline.incidents.count, 2)
        XCTAssertEqual(timeline.incidents[0].messageCount, 2)
    }

    func testTheGapIsFlaggedAsMissingEvidenceNotCalm() {
        let entries = [
            Entry(sourceFile: "a.txt", sourceType: "whatsapp", messages: [
                other("first", "2026-05-01T08:00:00"),
                other("much later", "2026-06-10T08:00:00"),
            ])
        ]
        let timeline = Organizer.organize(entries: entries)
        let gap = timeline.flags.first { $0.kind == .gap }
        XCTAssertNotNil(gap)
        XCTAssertEqual(gap?.days, 40)
        XCTAssertTrue(gap!.text.contains("not necessarily a calm period"))
    }

    func testTheSameExportImportedTwiceIsCountedOnce() {
        let message = other("where are you", "2026-05-01T08:00:00")
        let entries = [
            Entry(sourceFile: "a.txt", sourceType: "whatsapp", messages: [message]),
            Entry(sourceFile: "a-copy.txt", sourceType: "whatsapp", messages: [message]),
        ]
        let timeline = Organizer.organize(entries: entries)
        XCTAssertEqual(timeline.messages.count, 1)
        XCTAssertTrue(timeline.flags.contains { $0.kind == .overlap })
    }

    func testLowConfidenceAndParseErrorsAreBothFlagged() {
        let entries = [
            shot("bad.PNG", parseError: "could not read the screen", []),
            Entry(sourceFile: "b.PNG", sourceType: "screenshot", messages: [
                Message(sender: .other, text: "blurry line", confidence: 0.41),
            ]),
        ]
        let timeline = Organizer.organize(entries: entries)
        XCTAssertTrue(timeline.flags.contains { $0.kind == .parseError })
        XCTAssertTrue(timeline.flags.contains { $0.kind == .lowConfidence })
    }

    func testNoSummarizerMeansNoSentenceNobodySaid() {
        let entries = [Entry(sourceFile: "a.txt", sourceType: "whatsapp", messages: [
            other("where are you", "2026-05-01T08:00:00"),
        ])]
        let timeline = Organizer.organize(entries: entries)
        XCTAssertEqual(timeline.incidents[0].summary, "")
    }

    func testThePrevalenceSourceTravelsWithTheRecord() {
        let timeline = Organizer.organize(entries: [])
        XCTAssertTrue(timeline.prevalenceSource.contains("NISVS"))
    }

    func testTheRecordRoundTripsThroughJSON() {
        let entries = [Entry(sourceFile: "a.txt", sourceType: "whatsapp", messages: [
            other("where are you", "2026-05-01T08:00:00"),
        ])]
        let timeline = Organizer.organize(entries: entries)
        let data = try! JSONEncoder().encode(timeline)
        let decoded = try! JSONDecoder().decode(Timeline.self, from: data)
        XCTAssertEqual(decoded.messages.count, timeline.messages.count)
        XCTAssertEqual(decoded.patterns.first?.category, "Monitoring")
    }
}
