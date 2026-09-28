import Foundation

/// CDC-taxonomy matchers, ported from `matchers.py` with the taxonomy intact.
///
/// Every message is classified against the coercive-control and
/// expressive-aggression items measured in the CDC's National Intimate Partner
/// and Sexual Violence Survey (NISVS 2023/2024).
///
/// Deliberately regex and counting. No model, no inference, no confidence
/// score. The output is always two things: the message, and why it was
/// surfaced. The survivor names what it was; a lawyer decides what it proves.
///
/// Attaching a category also attaches a published national prevalence figure,
/// which is the difference between "this tool thinks" and "the CDC measures
/// this, and N percent of women report it".
public enum Matchers {
    public static let prevalenceSource = """
        CDC, National Intimate Partner and Sexual Violence Survey (NISVS) \
        2023/2024 IPV Data Brief, Table 7, lifetime prevalence among women
        """

    /// Things one message cannot show about a survey item.
    public static let caveats: [String: String] = [
        "Degradation": "The survey item covers insults made in front of others; "
            + "a message alone does not show who else saw it.",
    ]

    public struct Category {
        public let name: String
        /// The survey item as the CDC words it. Nil for a category the survey
        /// does not measure.
        public let nisvs: String?
        /// Lifetime prevalence among women. Nil where there is no figure.
        public let prevalence: String?
        public let patterns: [String]

        public var measured: Bool { nisvs != nil }
    }

    /// Order is the order the record presents them in, so it is fixed here
    /// rather than left to a dictionary.
    public static let categories: [Category] = [
        Category(
            name: "Financial control",
            nisvs: "Kept you from having your own money",
            prevalence: "8.8%",
            patterns: [
                #"\b(my|the) money\b"#,
                #"you (can't|cant|don't|dont) (have|need|touch)\b.*\bmoney"#,
                #"\ballowance\b"#,
                #"\bstop spending\b"#,
                #"give (me|it) back"#,
                #"who (paid|pays) for"#,
            ]
        ),
        Category(
            name: "Isolation",
            nisvs: "Tried to keep you from seeing or talking to family or friends",
            prevalence: "16.0%",
            patterns: [
                #"\bdon'?t (see|talk to|call|text)\b"#,
                #"\byour (family|friends|sister|mom)\b.*\b(again|anymore)\b"#,
                #"you (can't|cant) go"#,
                #"stay (home|away from)"#,
                #"\bnobody but me\b"#,
                #"\byou don'?t need (anyone|anybody) else\b"#,
            ]
        ),
        Category(
            name: "Monitoring",
            nisvs: "Kept track of you by demanding to know where you were",
            prevalence: "18.6%",
            patterns: [
                #"where (are|were) you"#,
                #"who (are|were) you with"#,
                #"send (me )?(a )?(pic|photo|location)"#,
                #"share your location"#,
                #"\bevery (hour|minute)\b"#,
                #"why (aren'?t|didn'?t) you (answer|reply|pick up)"#,
            ]
        ),
        Category(
            name: "Threats of harm",
            nisvs: "Made threats to physically harm you",
            prevalence: "12.4%",
            patterns: [
                #"\bi('| wi)ll (hurt|kill|find|end) you"#,
                #"you('?ll| will) (regret|be sorry)"#,
                #"\bwatch what happens\b"#,
                #"\b(ruin|destroy) your (life|career|reputation|job)\b"#,
                #"\byou('?re| are) dead\b"#,
                #"i know where you"#,
            ]
        ),
        Category(
            name: "Threatened self-harm",
            nisvs: "Threatened to hurt themselves or die by suicide",
            prevalence: "14.0%",
            patterns: [
                #"\bi('| wi)ll (kill|hurt|end) myself\b"#,
                #"\bwithout you i('| wi)ll\b"#,
                #"\byou'?ll make me\b.*\b(hurt|kill)\b"#,
                #"\bit'?s your fault if i\b"#,
            ]
        ),
        Category(
            name: "Decisions taken",
            nisvs: "Made decisions that should have been yours to make",
            prevalence: "15.2%",
            patterns: [
                #"\byou('?re| are) not (going|allowed)\b"#,
                #"\bi (already )?decided\b"#,
                #"\byou don'?t get to\b"#,
                #"\bi said no\b"#,
                #"\bthat'?s final\b"#,
            ]
        ),
        Category(
            name: "Property destroyed",
            nisvs: "Destroyed something important to you",
            prevalence: "14.6%",
            patterns: [
                #"\bi (broke|smashed|threw out|burned|ripped)\b"#,
                #"\byour (phone|things|stuff)\b.*\b(gone|broken)\b"#,
            ]
        ),
        Category(
            name: "Degradation",
            nisvs: "Insulted, humiliated or made fun of you in front of others",
            prevalence: "20.4%",
            patterns: [
                #"\byou('?re| are) (so |such )?(stupid|worthless|pathetic|nothing|ugly|a joke|useless)\b"#,
                #"\bnobody (else )?(would|will) (ever )?(want|love)\b"#,
                #"\beveryone (thinks|knows) you\b"#,
                #"\byou (useless|worthless|stupid|pathetic|idiot)\b"#,
                #"\b(more useful|better|smarter) than you\b"#,
            ]
        ),
        // Kept because survivors name it constantly, but NOT a NISVS item, so it
        // carries no prevalence figure and the record says so.
        Category(
            name: "Reality denial",
            nisvs: nil,
            prevalence: nil,
            patterns: [
                #"\bthat (didn'?t|never) happen(ed)?\b"#,
                #"\byou('?re| are) (imagining|remembering it wrong)\b"#,
                #"\bi never said that\b"#,
                #"\byou('?re| are) (so |being )?(crazy|paranoid|dramatic)\b"#,
            ]
        ),
    ]

    /// iPhone text uses typographic quotes; the patterns are written with ASCII
    /// ones, so a curly apostrophe must not be the reason a threat is missed.
    public static func normalize(_ text: String) -> String {
        var value = text
        for (typographic, ascii) in [("\u{2019}", "'"), ("\u{2018}", "'"), ("\u{02bc}", "'"),
                                     ("\u{201c}", "\""), ("\u{201d}", "\"")] {
            value = value.replacingOccurrences(of: typographic, with: ascii)
        }
        return value.lowercased()
    }

    private static let compiled: [(Category, [NSRegularExpression])] = categories.map { category in
        let expressions = category.patterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [])
        }
        return (category, expressions)
    }

    /// Matched categories for one message's text. At most one hit per category:
    /// a second pattern firing does not make the same thing more true.
    public static func classify(_ text: String) -> [PatternHit] {
        guard !text.isEmpty else { return [] }
        let lowered = normalize(text)
        let range = NSRange(lowered.startIndex..., in: lowered)
        var hits: [PatternHit] = []

        for (category, expressions) in compiled {
            for expression in expressions {
                guard let match = expression.firstMatch(in: lowered, options: [], range: range),
                      let span = Range(match.range, in: lowered)
                else { continue }
                hits.append(
                    PatternHit(
                        category: category.name,
                        nisvs: category.nisvs,
                        prevalence: category.prevalence,
                        measured: category.measured,
                        caveat: caveats[category.name],
                        span: String(lowered[span])
                    )
                )
                break
            }
        }
        return hits
    }

    /// Attach flags to every message.
    ///
    /// Only messages from the other person are classified: she is documenting
    /// what was said to her, and running the matchers over her own words would
    /// put her sentences in a court packet as though they were the pattern.
    /// System notices and attachment placeholders are skipped.
    public static func enrich(_ messages: [Message]) -> [Message] {
        messages.map { message in
            var copy = message
            copy.flags = (message.sender == .other && !message.attachment)
                ? classify(message.text)
                : []
            return copy
        }
    }

    /// Count flagged categories across the record, with first and last
    /// occurrence, sorted by count descending.
    public static func summary(_ messages: [Message]) -> [PatternSummary] {
        var aggregate: [String: PatternSummary] = [:]

        for message in messages {
            for flag in message.flags {
                var record = aggregate[flag.category] ?? PatternSummary(
                    category: flag.category,
                    count: 0,
                    first: nil,
                    last: nil,
                    prevalence: flag.prevalence,
                    measured: flag.measured,
                    nisvs: flag.nisvs,
                    caveat: flag.caveat
                )
                record.count += 1
                if let date = message.effectiveDate {
                    record.first = min(record.first ?? date, date)
                    record.last = max(record.last ?? date, date)
                }
                aggregate[flag.category] = record
            }
        }

        // Ties keep taxonomy order, so the same record renders the same way twice.
        let order = Dictionary(uniqueKeysWithValues: categories.enumerated().map { ($1.name, $0) })
        return aggregate.values.sorted {
            $0.count == $1.count
                ? (order[$0.category] ?? 0) < (order[$1.category] ?? 0)
                : $0.count > $1.count
        }
    }
}
