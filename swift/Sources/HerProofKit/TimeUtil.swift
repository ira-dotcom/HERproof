import Foundation

/// Timestamp handling, ported with its original reasoning intact.
///
/// Sources disagree about time zones. WhatsApp exports and EXIF are naive local
/// wall-clock times, while a model reading a screenshot sometimes appends an
/// offset or a trailing Z to a time it saw on the screen. Every time a person
/// saw on their phone was local wall-clock time, so an offset is dropped rather
/// than converted, and everything is compared in one naive frame.
///
/// On Apple platforms "naive" means a `Date` built in a fixed UTC calendar: the
/// wall-clock numbers survive untouched, and nothing shifts when the phone
/// crosses a time zone with the evidence on it.
public enum TimeUtil {
    /// The fixed frame every parsed wall-clock time lives in.
    public static let frame: TimeZone = TimeZone(secondsFromGMT: 0)!

    private static let formatters: [DateFormatter] = {
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
        ]
        return patterns.map { pattern in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = frame
            formatter.dateFormat = pattern
            return formatter
        }
    }()

    private static let output: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = frame
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    /// Parse an ISO-ish string into the naive frame, or nil.
    ///
    /// A trailing Z or a numeric offset is stripped, not applied. A time read
    /// off a screenshot is what the screen said, and converting it would move
    /// an incident to a different hour than the one she lived.
    public static func parse(_ raw: String?) -> Date? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasSuffix("Z") { value.removeLast() }
        value = stripOffset(from: value)
        for formatter in formatters {
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    /// Render back out in the same naive ISO shape the pipeline wrote.
    public static func iso(_ date: Date?) -> String? {
        guard let date else { return nil }
        return output.string(from: date)
    }

    /// Whole days between two instants, floored, the way the gap flag counts.
    public static func days(from start: Date, to end: Date) -> Int {
        Int(end.timeIntervalSince(start) / 86_400)
    }

    /// Drop a trailing +HH:MM or -HH:MM without applying it.
    ///
    /// Only an offset that sits after a time is stripped, so the hyphens in the
    /// date itself are left alone.
    private static func stripOffset(from value: String) -> String {
        guard value.contains(":") else { return value }
        let characters = Array(value)
        // Walk back over a well-formed offset tail: [+-]HH:MM or [+-]HHMM.
        for index in stride(from: characters.count - 1, through: max(0, characters.count - 6), by: -1) {
            let character = characters[index]
            guard character == "+" || character == "-" else { continue }
            let tail = String(characters[index...])
            let digits = tail.dropFirst().filter { $0.isNumber }
            let separators = tail.dropFirst().filter { $0 == ":" }
            if (digits.count == 4 || digits.count == 2) && separators.count <= 1 {
                return String(characters[..<index])
            }
        }
        return value
    }
}
