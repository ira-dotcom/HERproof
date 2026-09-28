import Foundation

/// Who sent a message. `system` covers WhatsApp notices and anything the app
/// itself inserted, and is never classified.
public enum Sender: String, Codable, Sendable {
    case selfSender = "self"
    case other
    case system
}

/// One matched CDC category on one message.
///
/// `nisvs` and `prevalence` are nil for a category the survey does not measure.
/// Keeping the field rather than dropping the category is deliberate: survivors
/// name reality denial constantly, and the honest thing is to surface it while
/// saying plainly that there is no national figure behind it.
public struct PatternHit: Codable, Hashable, Sendable {
    public let category: String
    public let nisvs: String?
    public let prevalence: String?
    public let measured: Bool
    public let caveat: String?
    /// The exact words that matched. The record shows why a message was
    /// surfaced, never a paraphrase of it.
    public let span: String

    public init(
        category: String,
        nisvs: String?,
        prevalence: String?,
        measured: Bool,
        caveat: String?,
        span: String
    ) {
        self.category = category
        self.nisvs = nisvs
        self.prevalence = prevalence
        self.measured = measured
        self.caveat = caveat
        self.span = span
    }
}

public struct Message: Codable, Hashable, Sendable {
    public var sender: Sender
    public var text: String
    /// The send time the phone showed. Naive local wall-clock, no offset.
    public var timestamp: Date?
    /// Filled from the screenshot's capture time when the screen showed no send
    /// times. The message was sent at or before this.
    public var approxTimestamp: Date?
    public var confidence: Double
    public var sourceFile: String?
    public var attachment: Bool
    public var flags: [PatternHit]

    /// Position within the source entry, kept so untimed messages can still be
    /// put back in the order they appeared on screen.
    public var sourceIndex: Int
    public var entryOrder: Int

    public init(
        sender: Sender,
        text: String,
        timestamp: Date? = nil,
        approxTimestamp: Date? = nil,
        confidence: Double = 1.0,
        sourceFile: String? = nil,
        attachment: Bool = false,
        flags: [PatternHit] = [],
        sourceIndex: Int = 0,
        entryOrder: Int = 0
    ) {
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
        self.approxTimestamp = approxTimestamp
        self.confidence = confidence
        self.sourceFile = sourceFile
        self.attachment = attachment
        self.flags = flags
        self.sourceIndex = sourceIndex
        self.entryOrder = entryOrder
    }

    /// The time this message is placed at, real or approximate.
    public var effectiveDate: Date? { timestamp ?? approxTimestamp }
}

/// One imported file: a screenshot, a WhatsApp export, a photo.
public struct Entry: Codable, Sendable {
    public var sourceFile: String
    public var importedAt: Date?
    /// SHA-256 of the file as imported. The fingerprint is the whole point of
    /// the vault, so it is not optional in practice, only in the type.
    public var fileHash: String?
    public var sourceType: String
    public var exifTimestamp: Date?
    public var parseError: String?
    public var messages: [Message]

    public init(
        sourceFile: String,
        importedAt: Date? = nil,
        fileHash: String? = nil,
        sourceType: String,
        exifTimestamp: Date? = nil,
        parseError: String? = nil,
        messages: [Message]
    ) {
        self.sourceFile = sourceFile
        self.importedAt = importedAt
        self.fileHash = fileHash
        self.sourceType = sourceType
        self.exifTimestamp = exifTimestamp
        self.parseError = parseError
        self.messages = messages
    }
}

public struct Incident: Codable, Sendable {
    public var start: Date?
    public var end: Date?
    /// True when any message in the incident is dated by screenshot capture
    /// time rather than by a send time.
    public var approximate: Bool
    public var summary: String
    public var messageCount: Int

    public init(start: Date?, end: Date?, approximate: Bool, summary: String, messageCount: Int) {
        self.start = start
        self.end = end
        self.approximate = approximate
        self.summary = summary
        self.messageCount = messageCount
    }
}

/// Everything the record needs a human to look at by hand.
public struct Flag: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case parseError = "parse_error"
        case lowConfidence = "low_confidence"
        case noTime = "no_time"
        case approxTime = "approx_time"
        case overlap
        case gap
    }

    public var kind: Kind
    public var text: String
    public var sourceFile: String?
    public var count: Int?
    public var start: Date?
    public var end: Date?
    public var days: Int?

    public init(
        kind: Kind,
        text: String,
        sourceFile: String? = nil,
        count: Int? = nil,
        start: Date? = nil,
        end: Date? = nil,
        days: Int? = nil
    ) {
        self.kind = kind
        self.text = text
        self.sourceFile = sourceFile
        self.count = count
        self.start = start
        self.end = end
        self.days = days
    }
}

/// One category counted across the whole record.
public struct PatternSummary: Codable, Sendable {
    public var category: String
    public var count: Int
    public var first: Date?
    public var last: Date?
    public var prevalence: String?
    public var measured: Bool
    public var nisvs: String?
    public var caveat: String?
}

/// The organized record: what `timeline.json` held in the Python pipeline.
public struct Timeline: Codable, Sendable {
    public var messages: [Message]
    public var incidents: [Incident]
    public var patterns: [PatternSummary]
    public var prevalenceSource: String
    public var flags: [Flag]
}
