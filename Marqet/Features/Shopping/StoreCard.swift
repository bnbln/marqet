import MarqetCore
import SwiftUI

/// One store (or the unsorted bucket) as a tall card (KONZEPT §7.2).
struct StoreCard: View {
    let page: PageID
    /// `nil` for the unsorted card.
    let store: Store?
    let items: [ShoppingItem]
    let state: StoreCardState?
    /// Full screen in `StoreFocusScreen` instead of a card in the pager.
    var isExpanded = false
    var showsHeader = true
    /// Store menu and close button in the header; the Duo detail view has them in the system bar.
    var showsHeaderActions = true
    var horizontalSafeAreaInsets = EdgeInsets()

    @Environment(AppModel.self) private var model
    @Environment(\.cardZoomNamespace) private var zoomNamespace
    /// The user's finger is on the list – only then does pulling up open the card full screen.
    @State private var isDraggingList = false
    /// Measured height of the inbox footer, so the last item can scroll above it.
    @State private var revealLoadedContent = false
    @State private var hasShownSkeleton = false
    @State private var skeletonPulse = false
    /// Top edge of each category title row in the list, for the pinned title.
    @State private var titleOffsets: [ItemCategory: CGFloat] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isTyping: Bool { model.composerTarget != nil || model.editingItemID != nil }

    private var keyboardInset: CGFloat {
        if model.editingItemID != nil { return 220 }
        if model.composerTarget != nil { return 120 }
        return isExpanded ? 72 : 54
    }

    private var showsTriageFooter: Bool { store == nil && !items.isEmpty && !isExpanded }

    private var tint: Color { store?.color ?? .gray }
    /// Store color for text and symbols on the card surface (WCAG AA in light and dark mode).
    private var readableTint: Color { store?.readableColor ?? .secondary }
    private var completedItems: [ShoppingItem] {
        model.recentlyCompleted.filter { $0.storeID == store?.id && !items.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader { header }
            ZStack {
                if !model.hasLoadedItems {
                    loadingContent
                        .transition(.opacity.combined(with: .offset(y: -8)))
                } else {
                    loadedContent
                        .opacity(revealLoadedContent ? 1 : 0)
                        .offset(y: revealLoadedContent ? 0 : 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(CardChrome(isExpanded: isExpanded, glowColor: store?.color))
        // CardSurface clips its rounded foreground at the safe-area edge. Keep a separate,
        // noninteractive copy of the header artwork behind that clipped surface so the Duo
        // sidebar can sit over it without leaving a pale gap.
        .background(alignment: .top) {
            if !isExpanded, showsHeader {
                LinearGradient(colors: [tint, tint.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 76)
                    .padding(.leading, -horizontalSafeAreaInsets.leading)
                    .padding(.trailing, -horizontalSafeAreaInsets.trailing)
                    .backgroundExtensionEffect()
                    .accessibilityHidden(true)
            }
        }
        .modifier(CardZoomSource(page: page, namespace: isExpanded ? nil : zoomNamespace))
        // iPad and the open Duo: items dragged from another card move to this store
        // (KONZEPT-DUO-IPAD §4.2). On the iPhone a drag stays inside its store.
        .dropDestination(for: String.self) { ids, _ in
            guard sizeClass == .regular else { return false }
            let moved = model.items.filter { ids.contains($0.id) && $0.storeID != store?.id }
            guard !moved.isEmpty else { return false }
            Task { for item in moved { await model.assign(item, to: store) } }
            return true
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.38), value: model.hasLoadedItems)
        .onChange(of: model.hasLoadedItems, initial: true) { old, loaded in
            if !loaded {
                hasShownSkeleton = true
                revealLoadedContent = false
            } else if hasShownSkeleton && old != loaded && !reduceMotion {
                withAnimation(.smooth(duration: 0.48).delay(0.1)) {
                    revealLoadedContent = true
                }
            } else {
                revealLoadedContent = true
            }
        }
        .task(id: model.activePage == page || isExpanded) {
            if store != nil && (model.activePage == page || isExpanded) {
                Task { await model.refreshPrices(for: items) }
            }
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if items.isEmpty && (!model.showsCompleted || completedItems.isEmpty) {
            ViewThatFits(in: .vertical) {
                emptyState(showsSymbol: true)
                emptyState(showsSymbol: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isExpanded && model.composerTarget == nil {
                    Color(.secondarySystemGroupedBackground)
                } else {
                    Button(action: handleBackgroundTap) {
                        Color(.secondarySystemGroupedBackground)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.composerTarget == nil ? "Liste öffnen" : "Eingabe schließen")
                }
            }
        } else {
            itemList
        }
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 14) {
                    Circle()
                        .strokeBorder(Color(.tertiarySystemFill), lineWidth: 2)
                        .frame(width: 27, height: 27)
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: [144, 106, 178, 126, 158, 96][index], height: 9)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .frame(height: 58)
                if index < 5 {
                    Rectangle()
                        .fill(Color(.separator).opacity(0.3))
                        .frame(height: 0.5)
                        .padding(.leading, 62)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .opacity(skeletonPulse ? 0.68 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                skeletonPulse = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Einträge werden geladen")
    }

    // MARK: Header

    private var header: some View {
        StoreCardHeader(page: page, store: store, items: items, state: state, isExpanded: isExpanded, showsActions: showsHeaderActions, isLoading: !model.hasLoadedItems)
    }

    // MARK: Items

    private var itemList: some View {
        ScrollViewReader { proxy in
            List {
                if items.isEmpty && (!model.showsCompleted || completedItems.isEmpty) {
                    Section {
                        emptyState(showsSymbol: true)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                            .listRowSeparator(.hidden)
                    }
                } else {
                    // Category sections in walking order for grocery stores, one flat list otherwise
                    // (KONZEPT §6.3). One run of rows with the titles as rows: the list's own
                    // reordering then carries an item past a title into another category, and
                    // the other rows make room while the finger moves (KONZEPT #55). The current
                    // title is pinned on top by `pinnedTitle`.
                    let lines = CardLine.lines(of: model.sections(for: page, items: items))
                    ForEach(lines) { line in
                        switch line {
                        case .header(let category):
                            titleLabel(category)
                                .frame(maxWidth: .infinity, minHeight: Self.titleHeight, alignment: .bottomLeading)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowBackground(Color(.secondarySystemGroupedBackground))
                                .listRowSeparator(.hidden)
                                .moveDisabled(true)
                                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.listSpace)).minY } action: { minY in
                                    titleOffsets[category] = minY
                                }
                                .onDisappear { titleOffsets[category] = nil }
                        case .item(let item, let index):
                            ItemRow(item: item, tint: readableTint)
                                .opacity(revealLoadedContent ? 1 : 0)
                                .offset(y: revealLoadedContent ? 0 : 8)
                                .animation(reduceMotion ? nil : .smooth(duration: 0.42).delay(Double(min(index, 8)) * 0.045), value: revealLoadedContent)
                                .listRowBackground(Color(.secondarySystemGroupedBackground))
                                .listRowSeparator(.visible, edges: .bottom)
                                // No line between a title and its first item.
                                .listRowSeparator(.hidden, edges: .top)
                                .listRowSeparatorTint(Color(.separator).opacity(0.4))
                                // The drag of the list's reordering; side by side it can also
                                // leave the list for another card.
                                .itemProvider { NSItemProvider(object: item.id as NSString) }
                        }
                    }
                    // Hold and drag: the other rows make room, the item takes its place on drop;
                    // below another title it takes that category. Not in the inbox.
                    .onMove(perform: store == nil ? nil : { source, destination in
                        guard let store, let placement = CardLine.placement(afterMoving: source, to: destination, in: lines) else { return }
                        model.arrangeItem(placement.item, into: placement.category, order: placement.order, in: store.id)
                    })
                    // An item from another card (iPad, open Duo, KONZEPT-DUO-IPAD §4.2).
                    .dropDestination(for: String.self) { ids, _ in
                        guard sizeClass == .regular, let store else { return }
                        let moved = model.items.filter { ids.contains($0.id) && $0.storeID != store.id }
                        Task { for item in moved { await model.assign(item, to: store) } }
                    }
                }
                completedSection
            }
            .listStyle(.plain)
            .coordinateSpace(.named(Self.listSpace))
            .overlay(alignment: .top) { pinnedTitle.clipped() }
            .modifier(DragSessionTracker())
            .scrollContentBackground(.hidden)
            // The pinned section titles carry their own opaque band. The top edge effect would
            // tint them with the bar's color scheme (black under a dark brand color).
            .scrollEdgeEffectHidden(true, for: .top)
            // The List's own scroll view consumes taps before its background sees them.
            // A parent tap handles unused white space; row buttons keep their own actions.
            .onTapGesture(perform: handleBackgroundTap)
            .scrollIndicators(.visible)
            // Every card blurs its list progressively above the bottom controls (mic, add, dots,
            // triage), which float unblurred on top. The bar reserves the space and drives the effect.
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            // With the keyboard up the card is short already; the blur would hide even more rows.
            .scrollEdgeEffectHidden(model.composerTarget != nil, for: .bottom)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if showsTriageFooter {
                    triageFooter
                } else {
                    // While typing, extra room lets the last rows scroll clear of the keyboard.
                    Color.clear.frame(height: keyboardInset)
                }
            }
            // The pager already sizes the card above keyboard and composer. Without this the bar
            // would ride up with the keyboard; the button stays at the card edge instead.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            // Pulling the list up opens the card full screen (not while typing or when full screen).
            .onScrollPhaseChange { _, phase in
                isDraggingList = phase == .interacting
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 36
            } action: { _, pulledUp in
                if pulledUp, isDraggingList, !isExpanded { model.focus(page) }
            }
            // Bring the row being edited above the keyboard, once the inset has grown.
            .onChange(of: model.editingItemID) { _, id in
                guard let id, items.contains(where: { $0.id == id }) else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            // No keyboard dismissal on scroll here: the scroll to a new item would close the composer.
            .onChange(of: model.recentlyAddedItemID) { _, id in
                // A new item lands in its category section, not necessarily at the bottom.
                // Ask the model, not `items`: a full-screen card that just switched stores can
                // still hold the previous render's items here.
                guard let id, model.deck.items(on: page).contains(where: { $0.id == id }) else { return }
                Task { @MainActor in
                    // The list inserts the row in a later layout pass; scroll once it exists,
                    // and once more in case the first pass was still before it.
                    await Task.yield()
                    withAnimation(.smooth) { proxy.scrollTo(id) }
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation(.smooth) { proxy.scrollTo(id) }
                }
            }
        }
    }

    // MARK: Category titles

    static let titleHeight: CGFloat = 40
    static let listSpace = "cardList"

    /// Icon and title close together, like a section header – a `Label` in a list row would get
    /// the row's wide icon column.
    private func titleLabel(_ category: ItemCategory) -> some View {
        HStack(spacing: 6) {
            Image(systemName: category.symbol)
            Text(category.displayName)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(readableTint)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The title of the section under the top edge, pinned like a list section header – pushed
    /// up by the next title as it arrives. The titles themselves are rows (see `itemList`).
    @ViewBuilder
    private var pinnedTitle: some View {
        if let current = titleOffsets.filter({ $0.value <= 0.5 }).max(by: { $0.value < $1.value }) {
            let next = titleOffsets.values.filter { $0 > 0.5 }.min() ?? .infinity
            titleLabel(current.key)
                .frame(maxWidth: .infinity, minHeight: Self.titleHeight, alignment: .bottomLeading)
                .padding(.horizontal, 20)
                // An opaque band, so rows never show through the title.
                .background(Color(.secondarySystemGroupedBackground))
                .offset(y: min(0, next - Self.titleHeight))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func handleBackgroundTap() {
        if model.composerTarget != nil {
            model.endComposer()
        } else if !isExpanded {
            model.focus(page)
        }
    }

    /// Entry into the triage flow, pinned to the bottom of the inbox card (KONZEPT §7.4), centered.
    /// Full screen, `StoreFocusScreen` shows it next to the add button instead.
    private var triageFooter: some View {
        TriageButton()
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 34)
            // The card is sized above keyboard and composer, so the button would float over
            // the composer. It stays out of sight while typing and returns with the keyboard down.
            .opacity(isTyping ? 0 : 1)
            .allowsHitTesting(!isTyping)
            .animation(.snappy, value: isTyping)
    }

    @ViewBuilder
    private var completedSection: some View {
        let completed = completedItems
        if model.showsCompleted {
            Section("Erledigt") {
                ForEach(completed) { item in
                    Button {
                        Task { await model.restore(item) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(readableTint)
                            Text(item.title)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "arrow.uturn.backward")
                                .foregroundStyle(.tertiary)
                                .accessibilityLabel("Nochmal kaufen")
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                    .listRowSeparator(.visible, edges: .bottom)
                    .listRowSeparatorTint(Color(.separator).opacity(0.4))
                }
                if completed.isEmpty {
                    Text("In den letzten 7 Tagen nichts erledigt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                }
            }
        }
    }

    // MARK: Empty states (KONZEPT §7.2 lifecycle)

    @ViewBuilder
    private func emptyState(showsSymbol: Bool) -> some View {
        VStack(spacing: 14) {
            switch state {
            case .shoppedEmpty:
                if showsSymbol {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(readableTint)
                }
                Text("Alles erledigt bei \(store?.name ?? "")")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                if let store {
                    Button("Ausblenden") { model.hide(store.id) }
                        .buttonStyle(.bordered)
                        .tint(readableTint)
                }
            case .planned:
                if showsSymbol {
                    Image(systemName: "cart.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(readableTint)
                }
                Text("Noch leer")
                    .font(.title3.bold())
                Text("Tippe auf +, um etwas für \(store?.name ?? "") hinzuzufügen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Eintrag hinzufügen", systemImage: "plus") { model.startComposer(on: page) }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .foregroundStyle(store?.foregroundOnColor ?? .white)
            default:
                if store == nil {
                    if showsSymbol {
                        Image(systemName: "tray")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(width: 88, height: 88)
                            .background(Color(.tertiarySystemGroupedBackground), in: .circle)
                    }
                    Text("Alles sortiert")
                        .font(.title3.bold())
                    Text("Einträge ohne Laden findest du hier.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Eintrag hinzufügen", systemImage: "plus") { model.startComposer(on: .unsorted) }
                        .buttonStyle(.bordered)
                } else if let store {
                    if showsSymbol {
                        Image(systemName: "cart")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                    }
                    Text("Leer")
                        .font(.title3.bold())
                    Button("Ausblenden") { model.hide(store.id) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(24)
    }
}

/// A header that owns its environment-dependent content. Keeping it as a rendered child is
/// important: accessing a computed header from a parent evaluates `@Environment` too early and
/// crashes when the card is opened in the Duo split detail view.
struct StoreCardHeader: View {
    let page: PageID
    let store: Store?
    let items: [ShoppingItem]
    let state: StoreCardState?
    let isExpanded: Bool
    var contentWidth: CGFloat? = nil
    var showsBackground = true
    /// Store menu and close button. Off where the system bar carries them (Duo detail view).
    var showsActions = true
    var isLoading = false

    @Environment(AppModel.self) private var model

    private var tint: Color { store?.color ?? .gray }

    var body: some View {
        HStack(spacing: 14) {
            if let store {
                StoreBadge(store: store, size: 44)
            } else {
                Image(systemName: "tray.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.2), in: .circle)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(store?.name ?? String(localized: "Inbox"))
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if isLoading {
                    Capsule()
                        .fill(.white.opacity(0.4))
                        .frame(width: 94, height: 8)
                        .accessibilityLabel("Einträge werden geladen")
                } else {
                    Text(Self.subtitle(store: store, items: items, state: state, distance: store.flatMap { model.distanceText(to: $0.id) }, presenceStoreID: model.presence?.storeID))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if showsActions {
                if let store {
                    StoreActionsMenu(page: page, store: store, items: items) {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.22), in: .circle)
                    }
                }
                if isExpanded {
                    Button {
                        model.focusedPage = nil
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.22), in: .circle)
                    }
                    .accessibilityLabel("Schließen")
                }
            }
        }
        .frame(width: contentWidth.map { max($0 - 36, 0) })
        .foregroundStyle(store?.foregroundOnColor ?? .white)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .contentShape(.rect)
        .onTapGesture {
            if isExpanded { model.focusedPage = nil } else { model.focus(page) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let gradient = LinearGradient(colors: [tint, tint.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if isExpanded {
                if showsBackground {
                    gradient
                        .ignoresSafeArea(edges: .top)
                        .backgroundExtensionEffect()
                } else {
                    Color.clear
                }
            } else {
                gradient
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityAction(named: isExpanded ? "Schließen" : "Vollbild") {
            if isExpanded { model.focusedPage = nil } else { model.focus(page) }
        }
    }

    static func subtitle(store: Store?, items: [ShoppingItem], state: StoreCardState?, distance: String?, presenceStoreID: Store.ID?) -> String {
        let open = items.filter { !$0.isCompleted }.count
        guard let store else {
            return open == 0 ? String(localized: "Alles sortiert") : String(localized: "\(open) zum Zuordnen")
        }
        // At this store right now (KONZEPT-WIDGETS §13).
        if presenceStoreID == store.id, open > 0 { return String(localized: "Du bist hier · \(open) offen") }
        if let address = store.address, !address.isEmpty { return [address, distance].compactMap { $0 }.joined(separator: " · ") }
        if let detail = store.detail, !detail.isEmpty { return [detail, distance].compactMap { $0 }.joined(separator: " · ") }
        if let distance, open > 0 { return String(localized: "\(open) offen · \(distance)") }
        switch state {
        case .shoppedEmpty: return String(localized: "Alles erledigt")
        case .planned where open == 0: return String(localized: "Noch keine Einträge")
        default: return String(localized: "\(open) offen")
        }
    }
}

/// The store's options ("…"): in the card header, or in the system bar on the Duo detail view.
/// Owns its sheets, so it works wherever it is placed.
struct StoreActionsMenu<MenuLabel: View>: View {
    let page: PageID
    let store: Store
    let items: [ShoppingItem]
    @ViewBuilder var label: MenuLabel

    @Environment(AppModel.self) private var model
    @State private var showsSectionOrder = false
    @State private var showsStoreDetails = false
    @State private var showsMap = false
    @State private var showsLoyaltyEditor = false
    @State private var showsLoyaltyCards = false
    @State private var showsLeaflet = false

    private var cards: [LoyaltyCard] { model.loyaltyCards(for: store.id) }
    private var leafletURL: URL? {
        store.catalogKey.flatMap { model.catalog?.entry(forKey: $0) }?.leafletURL
    }

    var body: some View {
        Menu {
            Section {
                if leafletURL != nil {
                    Button("Aktueller Prospekt", systemImage: "newspaper") { showsLeaflet = true }
                }
                if !cards.isEmpty {
                    Button(cards.count == 1 ? "Kundenkarte zeigen" : "Kundenkarten zeigen", systemImage: "wallet.pass.fill") {
                        showsLoyaltyCards = true
                    }
                }
                Button("Kundenkarte hinzufügen", systemImage: "wallet.pass") { showsLoyaltyEditor = true }
            }
            Section {
                Button("Eintrag hinzufügen", systemImage: "plus") { model.startComposer(on: page) }
                // The Live Activity "Einkauf" (KONZEPT-WIDGETS §5).
                if model.trip?.storeID == store.id {
                    Button("Einkauf beenden", systemImage: "cart.badge.minus") { Task { await model.endTrip() } }
                } else if !items.isEmpty {
                    Button("Einkauf starten", systemImage: "cart") { Task { await model.startTrip(at: store.id) } }
                }
                Button("In der Nähe", systemImage: "map") { showsMap = true }
                Button("Adresse & Info", systemImage: "mappin.and.ellipse") { showsStoreDetails = true }
                if store.type.showsCategorySections {
                    Button("Abschnitte sortieren", systemImage: "arrow.up.arrow.down") { showsSectionOrder = true }
                }
                if items.isEmpty {
                    Button("Aus Übersicht entfernen", systemImage: "eye.slash") { model.hide(store.id) }
                }
            }
        } label: {
            label
        }
        .tint(.primary)
        .accessibilityLabel("Laden-Optionen")
        .sheet(isPresented: $showsSectionOrder) {
            SectionOrderSheet(store: store).leadingSheetPlacement()
        }
        .sheet(isPresented: $showsStoreDetails) {
            StoreDetailsSheet(store: store).leadingSheetPlacement()
        }
        .sheet(isPresented: $showsMap) {
            MapScreen(focusedStoreID: store.id).leadingSheetPlacement()
        }
        .sheet(isPresented: $showsLoyaltyEditor) {
            LoyaltyCardEditor(for: store).leadingSheetPlacement()
        }
        .fullScreenCover(isPresented: $showsLoyaltyCards) {
            LoyaltyCardScreen(cards: cards)
        }
        .sheet(isPresented: $showsLeaflet) {
            if let leafletURL { SafariView(url: leafletURL).ignoresSafeArea() }
        }
    }
}

private struct StoreDetailsSheet: View {
    let store: Store
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var detail = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Adresse", text: $address)
                        .textContentType(.fullStreetAddress)
                    TextField("Weitere Info", text: $detail)
                } header: {
                    Text("Filiale")
                } footer: {
                    Text("Die Adresse oder Info erscheint unter dem Ladennamen auf der Card.")
                }
                BranchPickerSection(store: store)
            }
            .onChange(of: model.store(store.id)?.address) { _, new in
                // Choosing a preferred branch fills in its address.
                if let new { address = new }
            }
            .navigationTitle(store.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        model.updateDetails(of: store.id, address: address, detail: detail)
                        dismiss()
                    }
                }
            }
            .onAppear {
                address = store.address ?? ""
                detail = store.detail ?? ""
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A shopping item row, Reminders-style: circle to check off, 1.5 s undo window.
struct ItemRow: View {
    let item: ShoppingItem
    let tint: Color

    @Environment(AppModel.self) private var model
    @State private var isEditing = false
    @State private var isEditingNote = false
    @State private var draftTitle = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Task { await model.toggleCompletion(item) }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isCompleted ? tint : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.isCompleted ? "Erledigt, tippen zum Rückgängigmachen" : "Abhaken")

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Eintrag", text: $draftTitle)
                        .focused($isTitleFocused)
                        .submitLabel(.done)
                        .onSubmit(finishEditing)
                        .onChange(of: isTitleFocused) { _, focused in
                            if !focused { finishEditing() }
                        }
                } else {
                    Button(action: startEditing) {
                        let parts = ItemTitleParts(item.title)
                        HStack(spacing: 6) {
                            if let prefix = parts.prefix { quantityTag(prefix) }
                            Text(parts.name)
                                .strikethrough(item.isCompleted)
                                .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                            if let suffix = parts.suffix { quantityTag(suffix) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.title), bearbeiten")
                }
                if let notes = item.userNotes {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let storeID = item.storeID,
               let price = model.priceHint(for: item)?.price(of: storeID) {
                Text(price.estimateText(for: item.title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel("Geschätzter Richtwert: \(price.estimateText(for: item.title))")
            }
        }
        .padding(.vertical, 2)
        .animation(.snappy, value: item.isCompleted)
        // A noticeable tap for checking off; un-checking stays silent (undo has its own feedback).
        .sensoryFeedback(trigger: item.isCompleted) { old, new in
            !old && new ? .impact(weight: .heavy, intensity: 0.9) : nil
        }
        .contextMenu {
            #if DEBUG
            // `-no-item-menu`: synthesized simulator touches cannot turn the menu into a drag.
            if !ProcessInfo.processInfo.arguments.contains("-no-item-menu") {
                ItemContextMenu(item: item, onEdit: startEditing, onEditNote: { isEditingNote = true })
            }
            #else
            ItemContextMenu(item: item, onEdit: startEditing, onEditNote: { isEditingNote = true })
            #endif
        }
        .sheet(isPresented: $isEditingNote) {
            ItemNoteSheet(item: item)
        }
        .onChange(of: model.editingItemID) { _, editingID in
            if isEditing && editingID != item.id { finishEditing() }
        }
        .onDisappear {
            if isEditing { finishEditing() }
        }
        .tint(.primary)
    }

    private func quantityTag(_ value: String) -> some View {
        QuantityTag(value: value)
    }

    private func startEditing() {
        draftTitle = item.title
        isEditing = true
        model.editingItemID = item.id
        DispatchQueue.main.async { isTitleFocused = true }
    }

    private func finishEditing() {
        guard isEditing else { return }
        isEditing = false
        isTitleFocused = false
        if model.editingItemID == item.id { model.editingItemID = nil }
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty && title != item.title {
            Task { await model.rename(item, to: title) }
        }
    }
}

/// Card look in the pager, edge-to-edge surface full screen.
/// Reports an item drag to the model, so the pager does not page while the finger moves an item
/// (iOS 27: drag sessions are observable; before, the pager stays as it is).
private struct DragSessionTracker: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content.onDragSessionUpdated { session in
                switch session.phase {
                case .initial, .active:
                    if !model.isDraggingItem { model.isDraggingItem = true }
                default:
                    if model.isDraggingItem { model.isDraggingItem = false }
                }
            }
        } else {
            content
        }
    }
}

private struct CardChrome: ViewModifier {
    let isExpanded: Bool
    let glowColor: Color?

    func body(content: Content) -> some View {
        if isExpanded {
            content.background(Color(.secondarySystemGroupedBackground))
        } else {
            content.cardSurface(glowColor: glowColor)
        }
    }
}
