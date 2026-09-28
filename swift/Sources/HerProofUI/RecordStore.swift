import Foundation
import HerProofKit

/// Everything the screens read from, held in one place.
///
/// The record lives on the phone. Nothing here reaches the network, so an
/// import cannot quietly send her messages anywhere, and the app still works
/// with the phone in airplane mode in a shelter with no signal.
@MainActor
public final class RecordStore: ObservableObject {
    @Published public private(set) var entries: [Entry] = []
    @Published public private(set) var timeline: Timeline?
    @Published public var selfName: String = ""

    public init() {}

    public var messages: [Message] { timeline?.messages ?? [] }
    public var incidents: [Incident] { timeline?.incidents ?? [] }
    public var patterns: [PatternSummary] { timeline?.patterns ?? [] }
    public var flags: [Flag] { timeline?.flags ?? [] }

    /// Messages the matchers surfaced, which is what an attorney reads first.
    public var flagged: [Message] { messages.filter { !$0.flags.isEmpty } }

    public func importWhatsAppExport(at url: URL) throws {
        let entry = try WhatsAppExport.parse(fileAt: url, selfName: selfName.isEmpty ? nil : selfName)
        entries.append(entry)
        rebuild()
    }

    public func add(_ entry: Entry) {
        entries.append(entry)
        rebuild()
    }

    /// Remove an import and rebuild. Hers to take back out: an evidence tool
    /// that will not let go of a file is one more thing holding her.
    public func remove(sourceFile: String) {
        entries.removeAll { $0.sourceFile == sourceFile }
        rebuild()
    }

    public func rebuild() {
        timeline = Organizer.organize(entries: entries)
    }
}
