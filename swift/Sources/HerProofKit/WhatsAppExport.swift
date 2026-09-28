import Foundation

/// WhatsApp .txt export parser, ported from `whatsapp.py`.
///
/// Handles both export styles:
///   iOS:      [2026-09-24, 9:42:13 PM] Other Person: where are you
///   Android:  24/09/2026, 21:42 - Other Person: where are you
///
/// Day and month order is ambiguous (24/09 against 09/24); formats are tried in
/// order and the first that parses wins.
///
/// The exporting person's display name maps to `self`. Everything else from a
/// named sender is `other`, and WhatsApp's own notices are `system`.
public enum WhatsAppExport {
    /// Invisible direction marks iOS puts before system text and attachments.
    private static let bidi = CharacterSet(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}")

    private static let dateFormats = [
        "yyyy-MM-dd, h:mm:ss a",
        "yyyy-MM-dd, h:mm a",
        "dd/MM/yyyy, HH:mm:ss",
        "dd/MM/yyyy, HH:mm",
        "dd/MM/yy, HH:mm:ss",
        "dd/MM/yy, HH:mm",
        "MM/dd/yy, h:mm:ss a",
        "MM/dd/yy, h:mm a",
        "MM/dd/yyyy, h:mm a",
        "dd.MM.yy, HH:mm:ss",
        "dd.MM.yyyy, HH:mm",
    ]

    private static let formatters: [DateFormatter] = dateFormats.map { pattern in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeUtil.frame
        formatter.dateFormat = pattern
        return formatter
    }

    /// WhatsApp's own notices, written by neither person.
    private static let systemPhrases = [
        "messages and calls are end-to-end encrypted",
        "created group", "added you", "changed the subject", "changed this group",
        "changed their phone number", "security code", "left", "joined using",
        "this message was deleted", "you deleted this message",
    ]

    private static let iosLine = try! NSRegularExpression(pattern: #"^\[([^\]]+)\]\s*(.*)$"#)
    private static let androidLine = try! NSRegularExpression(
        pattern: #"^(\d{1,4}[/.\-]\d{1,2}[/.\-]\d{1,4},?\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s?[APap][Mm])?)\s+-\s+(.*)$"#
    )
    private static let senderLine = try! NSRegularExpression(
        pattern: #"^([^:]{1,80}):\s([\s\S]*)$"#
    )
    private static let attachment = try! NSRegularExpression(
        pattern: #"^(<media omitted>|(image|video|audio|sticker|gif|document) omitted|<attached: .+>)"#,
        options: [.caseInsensitive]
    )

    /// Parse an export into messages. `selfName` is the exporting person's
    /// display name; without it every named sender reads as `other`, which
    /// over-counts rather than under-counts, so it is worth asking for.
    public static func parse(text raw: String, sourceFile: String, selfName: String? = nil) -> [Message] {
        var messages: [Message] = []

        for rawLine in raw.components(separatedBy: .newlines) {
            let line = trimBidi(rawLine)
            guard let (stamp, rest) = matchLine(line) else {
                // A continuation of the previous multi-line message.
                if !messages.isEmpty, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    messages[messages.count - 1].text += "\n" + line
                }
                continue
            }

            let sender: Sender
            let body: String
            if let parts = capture(senderLine, in: rest), parts.count == 2 {
                let senderName = parts[0].trimmingCharacters(in: .whitespaces)
                let rawText = parts[1]
                let text = trimBidi(rawText)
                if startsWithBidi(rawText), isSystem(text) {
                    sender = .system
                } else if let selfName, !selfName.isEmpty, senderName == selfName {
                    sender = .selfSender
                } else {
                    sender = .other
                }
                body = text
            } else {
                // No "Name:" part at all, for instance "You created group".
                sender = .system
                body = trimBidi(rest)
            }

            messages.append(
                Message(
                    sender: sender,
                    text: body,
                    timestamp: parseStamp(stamp),
                    confidence: 1.0,
                    sourceFile: sourceFile,
                    attachment: matches(attachment, body),
                    sourceIndex: messages.count
                )
            )
        }
        return messages
    }

    public static func parse(fileAt url: URL, selfName: String? = nil) throws -> Entry {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        return Entry(
            sourceFile: url.lastPathComponent,
            importedAt: Date(),
            fileHash: Fingerprint.sha256(of: data),
            sourceType: "whatsapp",
            messages: parse(text: text, sourceFile: url.lastPathComponent, selfName: selfName)
        )
    }

    // MARK: - Helpers

    static func parseStamp(_ raw: String) -> Date? {
        // WhatsApp uses narrow and non-breaking spaces around AM/PM.
        let cleaned = raw
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespaces)
        for formatter in formatters {
            if let date = formatter.date(from: cleaned) { return date }
        }
        return nil
    }

    private static func matchLine(_ line: String) -> (String, String)? {
        for expression in [iosLine, androidLine] {
            guard let parts = capture(expression, in: line), parts.count == 2 else { continue }
            if parseStamp(parts[0]) != nil { return (parts[0], parts[1]) }
        }
        return nil
    }

    private static func isSystem(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return systemPhrases.contains { lowered.contains($0) }
    }

    private static func trimBidi(_ value: String) -> String {
        var result = Substring(value)
        while let first = result.unicodeScalars.first, bidi.contains(first) {
            result = result.dropFirst()
        }
        return String(result)
    }

    private static func startsWithBidi(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else { return false }
        return bidi.contains(first)
    }

    private static func matches(_ expression: NSRegularExpression, _ value: String) -> Bool {
        expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    private static func capture(_ expression: NSRegularExpression, in value: String) -> [String]? {
        let range = NSRange(value.startIndex..., in: value)
        guard let match = expression.firstMatch(in: value, range: range) else { return nil }
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let sub = Range(match.range(at: index), in: value) else { return nil }
            groups.append(String(value[sub]))
        }
        return groups
    }
}
