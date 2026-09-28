import Foundation

/// Merge imported entries into one organized record.
///
/// Ported from `organize.py`: merges all messages, removes the overlap between
/// consecutive screenshots, sorts by time, tags each message against the CDC
/// categories, groups into incidents on time gaps, and builds the flags list.
///
/// One thing is deliberately not ported. The Python version asked Gemini for a
/// neutral summary of every incident, which meant the text of a survivor's
/// messages left the machine. On the phone the record is built locally and a
/// summary is supplied by the caller, so nothing here sends her words anywhere.
public enum Organizer {
    /// Split incidents when messages are more than this far apart.
    public static let gapHours: Double = 6
    /// Flag messages read below this confidence.
    public static let lowConfidence: Double = 0.6

    /// Supplies the neutral per-incident summary. Injected so the engine never
    /// reaches the network on its own.
    public typealias Summarizer = ([Message]) -> String

    /// The default: no summary rather than an invented one. A record that says
    /// nothing is fixable; a record that says something nobody said is not.
    public static let noSummary: Summarizer = { _ in "" }

    public static func organize(
        entries: [Entry],
        summarize: Summarizer = noSummary
    ) -> Timeline {
        let (merged, overlapDropped) = loadMessages(entries)
        let sorted = merged.sorted(by: isBefore)
        let messages = Matchers.enrich(sorted)
        let grouped = groupIncidents(messages)

        let incidents: [Incident] = grouped.map { group in
            let bounds = self.bounds(of: group)
            return Incident(
                start: bounds.start,
                end: bounds.end,
                approximate: bounds.approximate,
                summary: summarize(group),
                messageCount: group.count
            )
        }

        return Timeline(
            messages: messages,
            incidents: incidents,
            patterns: Matchers.summary(messages),
            prevalenceSource: Matchers.prevalenceSource,
            flags: buildFlags(
                entries: entries,
                messages: messages,
                incidents: grouped,
                overlapDropped: overlapDropped
            )
        )
    }

    // MARK: - Merging

    private static func key(_ message: Message) -> String {
        let collapsed = message.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return "\(message.sender.rawValue)|\(collapsed.lowercased())"
    }

    /// Consecutive screenshots of one thread usually overlap: the bottom of one
    /// repeats at the top of the next. Drop only that repeated run, so two
    /// genuinely separate "ok" messages are both kept.
    static func removeOverlap(
        previous: [Message],
        current: [Message]
    ) -> (kept: [Message], dropped: Int) {
        var length = min(previous.count, current.count)
        while length > 0 {
            let tail = previous.suffix(length).map(key)
            let head = current.prefix(length).map(key)
            if tail == head {
                return (Array(current.dropFirst(length)), length)
            }
            length -= 1
        }
        return (current, 0)
    }

    static func loadMessages(_ entries: [Entry]) -> (messages: [Message], overlapDropped: Int) {
        var out: [Message] = []
        var overlapDropped = 0
        var previousShot: [Message] = []

        for (order, entry) in entries.enumerated() {
            var current = entry.messages.enumerated().map { index, message -> Message in
                var copy = message
                copy.sourceIndex = index
                copy.entryOrder = order
                copy.sourceFile = copy.sourceFile ?? entry.sourceFile
                // No send time on screen: date it by when the screenshot was
                // taken, which means at or before that moment, never after.
                if copy.timestamp == nil, let exif = entry.exifTimestamp {
                    copy.approxTimestamp = exif
                }
                return copy
            }

            if entry.sourceType == "screenshot" {
                let result = removeOverlap(previous: previousShot, current: current)
                current = result.kept
                overlapDropped += result.dropped
                previousShot = entry.messages
            } else {
                previousShot = []
            }

            out.append(contentsOf: current)
        }

        // The same export imported twice: identical sender, exact time and text.
        var seen = Set<String>()
        var deduped: [Message] = []
        for message in out {
            if let timestamp = message.timestamp {
                let composite = "\(key(message))|\(timestamp.timeIntervalSince1970)"
                if seen.contains(composite) {
                    overlapDropped += 1
                    continue
                }
                seen.insert(composite)
            }
            deduped.append(message)
        }
        return (deduped, overlapDropped)
    }

    /// Messages with no time at all go last, in the order they appeared.
    static func isBefore(_ lhs: Message, _ rhs: Message) -> Bool {
        switch (lhs.effectiveDate, rhs.effectiveDate) {
        case let (left?, right?):
            if left != right { return left < right }
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        case (nil, nil):
            break
        }
        if lhs.entryOrder != rhs.entryOrder { return lhs.entryOrder < rhs.entryOrder }
        return lhs.sourceIndex < rhs.sourceIndex
    }

    // MARK: - Incidents

    static func groupIncidents(_ messages: [Message]) -> [[Message]] {
        var incidents: [[Message]] = []
        var current: [Message] = []
        var lastDate: Date?

        for message in messages {
            let date = message.effectiveDate
            if let date, let lastDate, date.timeIntervalSince(lastDate) > gapHours * 3600 {
                incidents.append(current)
                current = []
            }
            current.append(message)
            if let date { lastDate = date }
        }
        if !current.isEmpty { incidents.append(current) }
        return incidents
    }

    static func bounds(of incident: [Message]) -> (start: Date?, end: Date?, approximate: Bool) {
        let timed = incident.compactMap { message -> (Date, Message)? in
            guard let date = message.effectiveDate else { return nil }
            return (date, message)
        }
        guard let first = timed.first, let last = timed.last else { return (nil, nil, false) }
        let approximate = timed.contains { $0.1.timestamp == nil }
        return (first.0, last.0, approximate)
    }

    // MARK: - Flags

    static func buildFlags(
        entries: [Entry],
        messages: [Message],
        incidents: [[Message]],
        overlapDropped: Int
    ) -> [Flag] {
        var flags: [Flag] = []

        for entry in entries where entry.parseError != nil {
            flags.append(
                Flag(
                    kind: .parseError,
                    text: "\(entry.sourceFile): \(entry.parseError!). Check the original file by hand.",
                    sourceFile: entry.sourceFile
                )
            )
        }

        for message in messages where message.confidence < lowConfidence {
            let snippet = String(message.text.prefix(40))
            let file = message.sourceFile ?? "unknown file"
            flags.append(
                Flag(
                    kind: .lowConfidence,
                    text: String(
                        format: "Low OCR confidence (%.2f) on %@: \"%@\". Review the original.",
                        message.confidence, file, snippet
                    ),
                    sourceFile: message.sourceFile
                )
            )
        }

        let untimed = messages.filter { $0.effectiveDate == nil }
        if !untimed.isEmpty {
            let files = Set(untimed.compactMap { $0.sourceFile }).sorted()
            flags.append(
                Flag(
                    kind: .noTime,
                    text: "\(untimed.count) messages have no time at all (\(files.joined(separator: ", "))). "
                        + "They are listed last, in file order.",
                    count: untimed.count
                )
            )
        }

        let approximate = messages.filter { $0.timestamp == nil && $0.approxTimestamp != nil }
        if !approximate.isEmpty {
            flags.append(
                Flag(
                    kind: .approxTime,
                    text: "\(approximate.count) messages show no send-time; they are dated by when the "
                        + "screenshot was taken, so they were sent at or before it.",
                    count: approximate.count
                )
            )
        }

        if overlapDropped > 0 {
            flags.append(
                Flag(
                    kind: .overlap,
                    text: "\(overlapDropped) repeated messages from overlapping screenshots were counted once.",
                    count: overlapDropped
                )
            )
        }

        // A stretch with no messages is missing evidence, never proof of calm.
        for (earlier, later) in zip(incidents, incidents.dropFirst()) {
            guard let end = bounds(of: earlier).end, let start = bounds(of: later).start else { continue }
            let days = TimeUtil.days(from: end, to: start)
            let endText = TimeUtil.iso(end) ?? ""
            let startText = TimeUtil.iso(start) ?? ""
            let dayText = days > 0 ? " (\(days) days)" : ""
            flags.append(
                Flag(
                    kind: .gap,
                    text: "No records between \(endText) and \(startText)\(dayText). "
                        + "Possible missing messages, not necessarily a calm period.",
                    start: end,
                    end: start,
                    days: days
                )
            )
        }

        return flags
    }
}
