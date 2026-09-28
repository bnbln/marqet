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

/// One card full screen. On wide layouts, store details sit left of the active list. Compact
/// layouts show the list alone; identity, menu and close sit in the system bar.
struct StoreFocusScreen: View {
    let page: PageID
    /// Duo: add, store menu and close sit in the system bar, as on Home (KONZEPT-DUO-IPAD §3).
    var hinge: HingeState = .none
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isComposerFocused = false
    @State private var showsAddStore = false
    @State private var addFeedback = 0
    @State private var horizontalSafeAreaInsets = EdgeInsets()
    @State private var viewportWidth: CGFloat = 390
    /// Store context left of the list (iPad, open Duo). Otherwise the system bar carries the actions.
    @State private var isSplit = false

    /// The wide iPad layout keeps its own header actions; everything else uses the system bar.
    private var showsSystemBar: Bool { hinge.hasHinge || !isSplit }

    /// The inbox header is gray with white text, so it takes the dark variant as well.
    private var headerColorScheme: ColorScheme {
        page.storeID.flatMap { model.store($0) }?.colorSchemeOnColor ?? .dark
    }

    private var headerColor: Color {
        page.storeID.flatMap { model.store($0) }?.color ?? .gray
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { if showsSystemBar { systemToolbar } }
                .toolbar(showsSystemBar ? .automatic : .hidden, for: .navigationBar)
                .toolbarBackground(headerColor, for: .navigationBar)
                // Split: the header gradient already runs under the bar (Duo). A solid bar on top
                // of it left a darker strip with a visible edge where the gradient lightens.
                .toolbarBackground(showsSystemBar && !isSplit ? .visible : .hidden, for: .navigationBar)
                // Bar buttons and status bar sit on the brand color: take their light or dark
                // variant from it, like the header text (white on Aldi, black on yellow chains).
                .toolbarColorScheme(isSplit && !hinge.hasHinge ? nil : headerColorScheme, for: .navigationBar)
                .toolbarVerticalCompressionPreferringItems()
        }
        // As on Home: the stack would otherwise reset the tint to the app accent.
        .tint(.primary)
        .voiceCaptureCover(isPresenter: true)
    }

    private var content: some View {
        let deck = model.deck
        return GeometryReader { proxy in
            let metrics = PagerMetrics(
                size: proxy.size,
                fold: FoldGeometry.verticalFold(in: proxy),
                maximumVisibleSlots: 2
            )
            let contextStore = page.storeID.flatMap { model.store($0) }
            let usesSplit = metrics.slots > 1 && contextStore != nil

            Group {
                if let store = contextStore, usesSplit {
                    splitCard(deck: deck, store: store, metrics: metrics, containerWidth: proxy.size.width)
                } else {
                    card(deck: deck)
                }
            }
            // min and max: exactly the space above keyboard and composer, even if the card is
            // taller – otherwise it pushes the composer's text field behind the keyboard.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            // As on Home: a tap on the card ends the composer – empty list space included,
            // which the list itself would swallow. Attached before the composer inset, so
            // taps on its chips and text field do not end it.
            .simultaneousGesture(TapGesture().onEnded {
                if model.composerTarget != nil { model.endComposer() }
            })
            .background(alignment: .top) {
                // The header color spans the whole screen, edge to edge and under the system bar.
                // Drawn here rather than offset inside the split: an offset keeps the layout frame,
                // and the background extension clips to it, so the color stopped at the column.
                if let store = contextStore, usesSplit {
                    LinearGradient(colors: [store.color, store.color.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        // Also under the top bar: on the Duo its items sit in the side bar, but it keeps its height.
                        .frame(height: StoreFocusScreen.headerHeight + proxy.safeAreaInsets.top)
                        .offset(y: -proxy.safeAreaInsets.top)
                        .ignoresSafeArea(edges: .horizontal)
                        .accessibilityHidden(true)
                }
            }
            .background(Color(.secondarySystemGroupedBackground).ignoresSafeArea())
            .overlay(alignment: .top) {
                // Duo outer display: no status bar, and the bar sits 24 pt below the top edge with
                // its background starting 10 pt above it. The strip above stayed white. Fill from
                // the top edge to the bar's bottom, over list rows scrolling under the bar.
                if !usesSplit, showsSystemBar {
                    headerColor
                        .frame(height: proxy.safeAreaInsets.top)
                        .offset(y: -proxy.safeAreaInsets.top)
                        .ignoresSafeArea(edges: .horizontal)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottom) {
                if model.editingItemID != nil {
                    editingCloseButton
                } else if model.composerTarget == nil {
                    bottomControls(deck: deck, metrics: metrics)
                }
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
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                viewportWidth = width
            }
            .onChange(of: usesSplit, initial: true) { _, split in isSplit = split }
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

    private var editingCloseButton: some View {
        HStack {
            Spacer()
            Button {
                model.editingItemID = nil
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bearbeiten schließen")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    /// "Läden zuordnen" centered at the height of the add button (inbox only).
    private func bottomControls(deck: CardDeck, metrics: PagerMetrics) -> some View {
        ZStack(alignment: .bottom) {
            if page == .unsorted, !deck.items(on: page).isEmpty {
                if metrics.anchor == .trailing {
                    // Duo inside: centered in the right half (the anchor side), not on the crease.
                    TriageButton()
                        .frame(width: metrics.slotWidth)
                        .padding(.leading, metrics.scrollX + metrics.slotWidth + metrics.spacing - 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TriageButton()
                }
            }
            if !hinge.hasHinge {
                HStack {
                    Spacer()
                    addButton
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func card(deck: CardDeck) -> some View {
        switch page {
        case .map, .brochures, .more:
            EmptyView()
        case .unsorted:
            StoreCard(page: page, store: nil, items: deck.items(on: page), state: nil, isExpanded: true, showsHeader: false)
        case .store(let id):
            if let store = model.store(id) {
                StoreCard(page: page, store: store, items: deck.items(on: page), state: deck.state(of: id), isExpanded: true, showsHeader: false)
            }
        }
    }

    private static let headerHeight: CGFloat = 76

    /// Store context left, list right. The context column fills the whole left half: on the Duo
    /// the right half is narrower (system bar), and two equal columns left a wide gap on the left.
    private func splitCard(deck: CardDeck, store: Store, metrics: PagerMetrics, containerWidth: CGFloat) -> some View {
        let storePage = PageID.store(store.id)
        let storeItems = deck.items(on: storePage)
        let listCard = StoreCard(
            page: storePage,
            store: store,
            items: storeItems,
            state: deck.state(of: store.id),
            isExpanded: true,
            showsHeader: false
        )
        let contextWidth = metrics.scrollX + metrics.slotWidth - metrics.leadingMargin

        return VStack(alignment: .leading, spacing: 0) {
            StoreCardHeader(
                page: storePage,
                store: store,
                items: storeItems,
                state: deck.state(of: store.id),
                isExpanded: true,
                contentWidth: contextWidth,
                showsBackground: false,
                showsActions: !hinge.hasHinge
            )
            .frame(width: containerWidth - metrics.leadingMargin, height: Self.headerHeight, alignment: .leading)

            HStack(spacing: metrics.spacing) {
                StoreContextPane(store: store)
                    .frame(width: contextWidth)
                listCard
                    .frame(width: metrics.slotWidth)
            }
            .frame(minHeight: 0, maxHeight: .infinity)
        }
        .padding(.leading, metrics.leadingMargin)
        .frame(width: containerWidth, alignment: .leading)
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
    }

    /// System bar: the card identity, store menu and close. Duo: add at the thumb like on Home.
    @ToolbarContentBuilder
    private var systemToolbar: some ToolbarContent {
        if !isSplit {
            ToolbarItem(placement: .topBarLeading) {
                compactTitle
            }
            .sharedBackgroundVisibility(.hidden)
        }
        if hinge.hasHinge, model.editingItemID == nil {
            ToolbarItem(placement: .bottomBar) {
                Button("Hinzufügen", systemImage: "plus") {
                    addFeedback += 1
                    model.startComposer(on: page)
                }
                .tint(.primary)
            }
        }
        if let store = page.storeID.flatMap({ model.store($0) }) {
            ToolbarItem(placement: .topBarTrailing) {
                StoreActionsMenu(page: page, store: store, items: model.deck.items(on: page)) {
                    Label("Laden-Optionen", systemImage: "ellipsis")
                }
            }
        }
        if hinge.hasHinge {
            // Duo: closing is its own action, apart from the store actions (HIG: a divided
            // group, not first in a shared one) and shown as the system close button.
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Schließen", systemImage: "xmark", role: .close) { model.focusedPage = nil }
                    .tint(.primary)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Schließen", systemImage: "chevron.down") { model.focusedPage = nil }
                    .tint(.primary)
            }
        }
    }

    private var compactTitle: some View {
        let store = page.storeID.flatMap { model.store($0) }
        let items = model.deck.items(on: page)
        let subtitle = StoreCardHeader.subtitle(
            store: store, items: items,
            state: store.map { model.deck.state(of: $0.id) } ?? nil,
            distance: store.flatMap { model.distanceText(to: $0.id) },
            presenceStoreID: model.presence?.storeID
        )
        return HStack(spacing: 9) {
            if let store {
                StoreBadge(store: store, size: 36)
            } else {
                Image(systemName: "tray.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.2), in: .circle)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(store?.name ?? String(localized: "Inbox"))
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(width: min(max(viewportWidth - 205, 95), 195), alignment: .leading)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(store?.foregroundOnColor ?? .white)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
