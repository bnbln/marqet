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

/// One card full screen. On wide layouts, store details sit left of the active list; compact
/// layouts keep the existing single-card detail view.
struct StoreFocusScreen: View {
    let page: PageID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isComposerFocused = false
    @State private var showsAddStore = false
    @State private var addFeedback = 0
    @State private var horizontalSafeAreaInsets = EdgeInsets()

    var body: some View {
        let deck = model.deck
        GeometryReader { proxy in
            let metrics = PagerMetrics(
                size: proxy.size,
                fold: FoldGeometry.verticalFold(in: proxy),
                maximumVisibleSlots: 2
            )
            let contextStore = page.storeID.flatMap { model.store($0) }
            let usesSplit = metrics.slots > 1 && contextStore != nil

            Group {
                if let store = contextStore, usesSplit {
                    splitCard(
                        deck: deck,
                        store: store,
                        metrics: metrics,
                        containerWidth: proxy.size.width,
                        safeAreaInsets: proxy.safeAreaInsets
                    )
                } else {
                    card(deck: deck)
                }
            }
            // min and max: exactly the space above keyboard and composer, even if the card is
            // taller – otherwise it pushes the composer's text field behind the keyboard.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .background(Color(.secondarySystemGroupedBackground).ignoresSafeArea())
            .overlay(alignment: .bottom) {
                if model.composerTarget == nil { bottomControls(deck: deck) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Group {
                    if model.composerTarget != nil {
                        let horizontalOffset = usesSplit ? metrics.scrollX + metrics.slotWidth + metrics.spacing : 0
                        ZStack(alignment: .leading) {
                            composerBar
                                .frame(maxWidth: usesSplit ? metrics.slotWidth : .infinity)
                                .offset(x: horizontalOffset)
                                .animation(.smooth, value: horizontalOffset)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: model.composerTarget == nil)
            }
            .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets in
                horizontalSafeAreaInsets = insets
            }
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
            // Zuordnen opens on top of this screen and returns here – the inbox stays open,
            // even when it is empty afterwards.
            .fullScreenCover(isPresented: Binding(get: { model.triage != nil }, set: { if !$0 { model.endTriage() } })) {
                TriageScreen()
            }
        }
    }

    private var composerBar: some View {
        ComposerBar(
            isFocused: $isComposerFocused,
            showsAddStore: $showsAddStore,
            horizontalSafeAreaInsets: horizontalSafeAreaInsets
        )
    }

    /// "Läden zuordnen" centered at the height of the add button (inbox only).
    private func bottomControls(deck: CardDeck) -> some View {
        ZStack(alignment: .bottom) {
            if page == .unsorted, !deck.items(on: page).isEmpty {
                TriageButton()
            }
            HStack {
                Spacer()
                addButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func card(deck: CardDeck) -> some View {
        switch page {
        case .brochures, .more:
            EmptyView()
        case .unsorted:
            StoreCard(page: page, store: nil, items: deck.items(on: page), state: nil, isExpanded: true)
        case .store(let id):
            if let store = model.store(id) {
                StoreCard(page: page, store: store, items: deck.items(on: page), state: deck.state(of: id), isExpanded: true)
            }
        }
    }

    private func splitCard(
        deck: CardDeck,
        store: Store,
        metrics: PagerMetrics,
        containerWidth: CGFloat,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        let storePage = PageID.store(store.id)
        let storeItems = deck.items(on: storePage)
        let listCard = StoreCard(
            page: storePage,
            store: store,
            items: storeItems,
            state: deck.state(of: store.id),
            isExpanded: true,
            showsHeader: false,
            showsOffers: false
        )
        let headerWidth = max(metrics.scrollWidth, containerWidth - metrics.scrollX + safeAreaInsets.trailing)
        let headerBackgroundWidth = containerWidth + safeAreaInsets.leading + safeAreaInsets.trailing
        let headerBackgroundOffset = -(metrics.scrollX + safeAreaInsets.leading)

        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [store.color, store.color.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: headerBackgroundWidth, height: 76)
                .offset(x: headerBackgroundOffset)
                .ignoresSafeArea(edges: .top)
                .backgroundExtensionEffect()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                StoreCardHeader(
                    page: storePage,
                    store: store,
                    items: storeItems,
                    state: deck.state(of: store.id),
                    isExpanded: true,
                    contentWidth: metrics.slotWidth,
                    showsBackground: false
                )
                .frame(width: headerWidth, height: 76, alignment: .leading)

                HStack(spacing: metrics.spacing) {
                    StoreContextPane(store: store)
                        .frame(width: metrics.slotWidth)
                        .background(Color(.secondarySystemGroupedBackground))

                    listCard
                        .frame(width: metrics.slotWidth)
                        .background(Color(.secondarySystemGroupedBackground))
                }
                .frame(width: metrics.scrollWidth)
                .frame(minHeight: 0, maxHeight: .infinity)
                .background(Color(.secondarySystemGroupedBackground))
            }
            .frame(width: headerWidth, alignment: .leading)
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .leading)
        }
        .offset(x: metrics.scrollX)
        .frame(width: containerWidth, alignment: .leading)
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .leading)
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
    }
}

// MARK: - Offers & leaflets

/// The retailer's official leaflet link, shown directly below its detail header.
struct OffersSection: View {
    let store: Store
    @Environment(AppModel.self) private var model
    @State private var showsLeaflet = false

    private var leafletURL: URL? {
        store.catalogKey.flatMap { model.catalog?.entry(forKey: $0) }?.leafletURL
    }

    var body: some View {
        if let leafletURL {
            leafletButton
            .sheet(isPresented: $showsLeaflet) {
                SafariView(url: leafletURL).ignoresSafeArea()
            }
        }
    }

    private var leafletButton: some View {
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
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
