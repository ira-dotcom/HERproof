#if os(iOS)
import SwiftUI
import HerProofKit

/// What repeats, and how often, with the national figure beside it.
public struct PatternMapView: View {
    @EnvironmentObject private var store: RecordStore

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if store.patterns.isEmpty {
                    ContentUnavailableView(
                        "Nothing imported yet",
                        systemImage: "tray",
                        description: Text("Add a chat export or screenshots and the pattern shows up here.")
                    )
                }

                ForEach(store.patterns, id: \.category) { pattern in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(pattern.category).font(.headline)
                            Spacer()
                            Text("\(pattern.count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                        if let nisvs = pattern.nisvs, let prevalence = pattern.prevalence {
                            Text("\(nisvs). \(prevalence) of women report this.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            // Said plainly rather than left to look measured.
                            Text("Survivors name this constantly. The national survey does not measure it, "
                                 + "so there is no figure to put next to it.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if let caveat = pattern.caveat {
                            Text(caveat).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !store.flags.isEmpty {
                    Section("Check by hand") {
                        ForEach(Array(store.flags.enumerated()), id: \.offset) { _, flag in
                            Text(flag.text).font(.footnote)
                        }
                    }
                }

                if !store.patterns.isEmpty {
                    Section {
                        Text(Matchers.prevalenceSource).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Pattern")
        }
    }
}

/// Every message, in order, with the ones the matchers surfaced marked.
public struct TimelineView: View {
    @EnvironmentObject private var store: RecordStore
    @State private var flaggedOnly = false

    public init() {}

    private var shown: [Message] { flaggedOnly ? store.flagged : store.messages }

    public var body: some View {
        NavigationStack {
            List {
                Toggle("Only what was flagged", isOn: $flaggedOnly)

                ForEach(Array(shown.enumerated()), id: \.offset) { _, message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.text)
                        HStack(spacing: 8) {
                            Text(stamp(for: message)).font(.caption).foregroundStyle(.secondary)
                            ForEach(message.flags, id: \.category) { flag in
                                Text(flag.category)
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Timeline")
        }
    }

    private func stamp(for message: Message) -> String {
        if let timestamp = message.timestamp {
            return TimeUtil.iso(timestamp) ?? ""
        }
        if let approx = message.approxTimestamp {
            // Never shown as a send time: it is when the screenshot was taken.
            return "at or before \(TimeUtil.iso(approx) ?? "")"
        }
        return "no time on the screen"
    }
}

/// Where everything came from, and its fingerprint.
public struct VaultView: View {
    @EnvironmentObject private var store: RecordStore

    public init() {}

    public var body: some View {
        NavigationStack {
            List(store.entries, id: \.sourceFile) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.sourceFile).font(.headline)
                    Text("\(entry.messages.count) messages, \(entry.sourceType)")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let hash = entry.fileHash {
                        Text(hash.prefix(16) + "...")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) { store.remove(sourceFile: entry.sourceFile) }
                }
            }
            .navigationTitle("Vault")
        }
    }
}

/// The record as it goes to an attorney.
public struct PacketView: View {
    @EnvironmentObject private var store: RecordStore

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("What's in it") {
                    LabeledContent("Messages", value: "\(store.messages.count)")
                    LabeledContent("Flagged", value: "\(store.flagged.count)")
                    LabeledContent("Incidents", value: "\(store.incidents.count)")
                    LabeledContent("To check by hand", value: "\(store.flags.count)")
                }

                Section("Incidents") {
                    ForEach(Array(store.incidents.enumerated()), id: \.offset) { index, incident in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(index + 1). \(TimeUtil.iso(incident.start) ?? "undated")")
                                .font(.subheadline.weight(.semibold))
                            Text("\(incident.messageCount) messages"
                                 + (incident.approximate ? ", dated by screenshot" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Text("HerProof is not a law firm and does not give legal advice. "
                         + "It gets the record ready for a lawyer and hands it over.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("US National Domestic Violence Hotline: 1-800-799-7233, or text START to 88788.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Packet")
        }
    }
}
#endif
