import MarqetCore
import SafariServices
import SwiftUI

extension EnvironmentValues {
    /// Namespace of the pager's card → full-screen zoom; `nil` where cards cannot zoom.
    @Entry var cardZoomNamespace: Namespace.ID?
}

/// Marks a pager card as the source of the zoom into `StoreFocusScreen`.
struct CardZoomSource: ViewModifier {
    let page: PageID
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: page.rawValue, in: namespace) { source in
                source.clipShape(.rect(cornerRadius: 30, style: .continuous))
            }
        } else {
            content
        }
    }
}

/// One card full screen: the card zooms up to the full width, the header runs under the status
/// bar, the add button stays, the page dots are gone. Stores show offers and leaflets below the items.
struct StoreFocusScreen: View {
    let page: PageID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isComposerFocused = false
    @State private var showsAddStore = false
    @State private var addFeedback = 0

    var body: some View {
        let deck = model.deck
        card(deck: deck)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemGroupedBackground).ignoresSafeArea())
            .overlay(alignment: .bottomTrailing) {
                if model.composerTarget == nil { addButton }
            }
            .safeAreaInset(edge: .bottom) {
                if model.composerTarget != nil {
                    ComposerBar(isFocused: $isComposerFocused, showsAddStore: $showsAddStore)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.composerTarget == nil)
            .sensoryFeedback(.impact(weight: .light), trigger: addFeedback)
            .onChange(of: model.composerTarget) { _, target in
                if target != nil { isComposerFocused = true }
            }
            // The store was hidden or deleted meanwhile.
            .onChange(of: deck.pages) { _, pages in
                if !pages.contains(page) { dismiss() }
            }
            .onDisappear {
                if model.composerTarget != nil { model.endComposer() }
            }
            .sheet(isPresented: $showsAddStore) { AddStoreSheet() }
    }

    @ViewBuilder
    private func card(deck: CardDeck) -> some View {
        switch page {
        case .unsorted:
            StoreCard(page: page, store: nil, items: deck.items(on: page), state: nil, isExpanded: true)
        case .store(let id):
            if let store = model.store(id) {
                StoreCard(page: page, store: store, items: deck.items(on: page), state: deck.state(of: id), isExpanded: true)
            }
        case .more:
            EmptyView()
        }
    }

    private var addButton: some View {
        Button {
            addFeedback += 1
            model.startComposer(on: page)
        } label: {
            Image(systemName: "plus")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Eintrag hinzufügen")
        .padding(.trailing, 20)
        .padding(.bottom, 4)
    }
}

// MARK: - Offers & leaflets

/// "Angebote & Prospekte" below a store's items. v1: the chain's official leaflet page
/// (MARKTANALYSE §3) – no offer data of our own, nothing sent anywhere before the tap.
struct OffersSection: View {
    let store: Store
    @Environment(AppModel.self) private var model
    @State private var showsLeaflet = false

    private var leafletURL: URL? {
        store.catalogKey.flatMap { model.catalog?.entry(forKey: $0) }?.leafletURL
    }

    var body: some View {
        if let leafletURL {
            Section {
                Button {
                    showsLeaflet = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "newspaper.fill")
                            .font(.title3)
                            .foregroundStyle(store.foregroundOnColor)
                            .frame(width: 44, height: 44)
                            .background(store.color, in: .rect(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Aktueller Prospekt")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Angebote der Woche bei \(store.name)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                Label("Angebote & Prospekte", systemImage: "tag.fill")
                    .font(.subheadline.weight(.semibold))
                    .textCase(nil)
                    .foregroundStyle(store.readableColor)
            } footer: {
                Text("Öffnet die offizielle Seite von \(store.name). Dort wählst du deinen Markt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .sheet(isPresented: $showsLeaflet) {
                SafariView(url: leafletURL).ignoresSafeArea()
            }
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
