#if os(iOS)
import SwiftUI
import HerProofKit

public struct HerProofRootView: View {
    @StateObject private var store = RecordStore()
    @State private var disguised = false

    public init() {}

    public var body: some View {
        Group {
            if disguised {
                DisguiseView { disguised = false }
            } else {
                TabView {
                    PatternMapView()
                        .tabItem { Label("Pattern", systemImage: "square.grid.3x3") }
                    TimelineView()
                        .tabItem { Label("Timeline", systemImage: "list.bullet") }
                    VaultView()
                        .tabItem { Label("Vault", systemImage: "lock.doc") }
                    PacketView()
                        .tabItem { Label("Packet", systemImage: "doc.text") }
                }
                .overlay(alignment: .topTrailing) {
                    Button("Hide") { disguised = true }
                        .font(.footnote.weight(.semibold))
                        .padding(8)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.trailing, 12)
                        .accessibilityLabel("Hide this screen")
                }
            }
        }
        .environmentObject(store)
    }
}

/// The cover screen. One tap from anywhere, and nothing on it reads as
/// evidence to someone glancing over her shoulder.
struct DisguiseView: View {
    let dismiss: () -> Void

    private let recipes = [
        ("Lemon orzo", "20 min"),
        ("Sheet pan chicken", "45 min"),
        ("Overnight oats", "5 min"),
        ("Tomato soup", "30 min"),
    ]

    var body: some View {
        NavigationStack {
            List(recipes, id: \.0) { recipe in
                HStack {
                    Text(recipe.0)
                    Spacer()
                    Text(recipe.1).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Recipes")
        }
        // Deliberately not a labeled button: the way back is a long press
        // nobody else would think to try.
        .onLongPressGesture(minimumDuration: 1.0) { dismiss() }
    }
}
#endif
