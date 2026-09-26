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
    var showsOffers = true
    var horizontalSafeAreaInsets = EdgeInsets()

    @Environment(AppModel.self) private var model
    @Environment(\.cardZoomNamespace) private var zoomNamespace
    /// The user's finger is on the list – only then does pulling up open the card full screen.
    @State private var isDraggingList = false
    /// Measured height of the inbox footer, so the last item can scroll above it.
    @State private var triageFooterHeight: CGFloat = 100
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
            if isExpanded, store != nil {
                itemList
            } else if items.isEmpty && (!model.showsCompleted || completedItems.isEmpty) {
                VStack(spacing: 0) {
                    // With the keyboard up, the card can get too short for the full empty state.
                    ViewThatFits(in: .vertical) {
                        emptyState(showsSymbol: true)
                        emptyState(showsSymbol: false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(perform: dismissComposerFromBackground)
                        }
                }
            } else {
                itemList
            }
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
        // Items dragged from another card move to this store (KONZEPT-DUO-IPAD §4.2).
        .dropDestination(for: String.self) { ids, _ in
            let moved = model.items.filter { ids.contains($0.id) && $0.storeID != store?.id }
            guard !moved.isEmpty else { return false }
            Task { for item in moved { await model.assign(item, to: store) } }
            return true
        }
    }

    // MARK: Header

    private var header: some View {
        StoreCardHeader(page: page, store: store, items: items, state: state, isExpanded: isExpanded)
    }

    // MARK: Items

    private var itemList: some View {
        ScrollViewReader { proxy in
            List {
                if isExpanded, showsOffers, let store {
                    Section {
                        OffersSection(store: store)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                            .listRowSeparator(.hidden)
                    }
                }
                if items.isEmpty && (!model.showsCompleted || completedItems.isEmpty) {
                    Section {
                        emptyState(showsSymbol: true)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                            .listRowSeparator(.hidden)
                    }
                } else {
                    // Category sections in walking order for grocery stores, one flat list otherwise (KONZEPT §6.3).
                    ForEach(model.sections(for: page, items: items)) { section in
                        Section {
                            ForEach(section.items) { item in
                                ItemRow(item: item, tint: readableTint)
                                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                                    .listRowSeparator(.visible, edges: .bottom)
                                    .listRowSeparatorTint(Color(.separator).opacity(0.4))
                                    .id(item.id)
                            }
                        } header: {
                            if let category = section.category {
                                Label(category.displayName, systemImage: category.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .textCase(nil)
                                    .foregroundStyle(readableTint)
                            }
                        }
                    }
                }
                completedSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background {
                // A tap on unused list space closes the composer. List rows and their
                // controls stay in front of this background hit target.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismissComposerFromBackground)
            }
            .scrollIndicators(.visible)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: isExpanded ? 72 : (showsTriageFooter ? triageFooterHeight : 54))
            }
            .overlay(alignment: .bottom) {
                if showsTriageFooter {
                    triageFooter
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { triageFooterHeight = $0 }
                        .padding(.bottom, 4)
                        // Keep the action at the card edge when the keyboard appears;
                        // the keyboard may cover it until the user dismisses the composer.
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            }
            // Pulling the list up opens the card full screen (not while typing or when full screen).
            .onScrollPhaseChange { _, phase in
                isDraggingList = phase == .interacting
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 36
            } action: { _, pulledUp in
                if pulledUp, isDraggingList, !isExpanded { model.focus(page) }
            }
            // No keyboard dismissal on scroll here: the scroll to a new item would close the composer.
            .onChange(of: items.count) { old, new in
                // Newly added items appear at the bottom – keep them in view while typing.
                if new > old, model.composerTarget == page, let last = items.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func dismissComposerFromBackground() {
        guard model.composerTarget != nil else { return }
        model.endComposer()
    }

    /// Entry into the triage flow, pinned to the bottom of the inbox card (KONZEPT §7.4), centered.
    /// Full screen, `StoreFocusScreen` shows it next to the add button instead.
    private var triageFooter: some View {
        TriageButton()
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 30)
            .background(Color(.secondarySystemGroupedBackground))
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

    @Environment(AppModel.self) private var model
    @State private var showsSectionOrder = false
    @State private var showsStoreDetails = false
    @State private var showsMap = false

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
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let store { cardMenu(for: store) }
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
        .sheet(isPresented: $showsSectionOrder) {
            if let store { SectionOrderSheet(store: store).leadingSheetPlacement() }
        }
        .sheet(isPresented: $showsStoreDetails) {
            if let store { StoreDetailsSheet(store: store).leadingSheetPlacement() }
        }
        .sheet(isPresented: $showsMap) {
            if let store { MapScreen(focusedStoreID: store.id).leadingSheetPlacement() }
        }
    }

    private var subtitle: String {
        let open = items.filter { !$0.isCompleted }.count
        guard let store else {
            return open == 0 ? String(localized: "Alles sortiert") : String(localized: "\(open) zum Zuordnen")
        }
        let distance = model.distanceText(to: store.id)
        if let address = store.address, !address.isEmpty { return [address, distance].compactMap { $0 }.joined(separator: " · ") }
        if let detail = store.detail, !detail.isEmpty { return [detail, distance].compactMap { $0 }.joined(separator: " · ") }
        if let distance, open > 0 { return String(localized: "\(open) offen · \(distance)") }
        switch state {
        case .shoppedEmpty: return String(localized: "Alles erledigt")
        case .planned where open == 0: return String(localized: "Noch keine Einträge")
        default: return String(localized: "\(open) offen")
        }
    }

    private func cardMenu(for store: Store) -> some View {
        Menu {
            Button("Eintrag hinzufügen", systemImage: "plus") { model.startComposer(on: page) }
            Button("Karte", systemImage: "map") { showsMap = true }
            Button("Adresse & Info", systemImage: "mappin.and.ellipse") { showsStoreDetails = true }
            if store.type.showsCategorySections {
                Button("Abschnitte sortieren", systemImage: "arrow.up.arrow.down") { showsSectionOrder = true }
            }
            if items.isEmpty {
                Button("Aus Übersicht entfernen", systemImage: "eye.slash") { model.hide(store.id) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.22), in: .circle)
        }
        .tint(.primary)
        .accessibilityLabel("Laden-Optionen")
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
        }
        .padding(.vertical, 2)
        .animation(.snappy, value: item.isCompleted)
        // A noticeable tap for checking off; un-checking stays silent (undo has its own feedback).
        .sensoryFeedback(trigger: item.isCompleted) { old, new in
            !old && new ? .impact(weight: .heavy, intensity: 0.9) : nil
        }
        .draggable(item.id)
        .contextMenu {
            Menu("Laden ändern", systemImage: "storefront") {
                Button("Inbox", systemImage: item.storeID == nil ? "checkmark" : "tray") {
                    Task { await model.assign(item, to: nil) }
                }
                ForEach(model.stores.sorted { $0.sortIndex < $1.sortIndex }) { store in
                    Button(store.name, systemImage: item.storeID == store.id ? "checkmark" : "circle.fill") {
                        Task { await model.assign(item, to: store) }
                    }
                }
            }
            Menu("Kategorie ändern", systemImage: "square.grid.2x2") {
                let current = model.category(of: item)
                ForEach(ItemCategory.allCases, id: \.self) { category in
                    Button(category.displayName, systemImage: category == current ? "checkmark" : category.symbol) {
                        model.setCategory(category, for: item)
                    }
                }
            }
            Button("Bearbeiten", systemImage: "pencil", action: startEditing)
            Button("Löschen", systemImage: "trash", role: .destructive) {
                Task { await model.delete(item) }
            }
        }
        .tint(.primary)
    }

    private func quantityTag(_ value: String) -> some View {
        Text(value)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemFill), in: .capsule)
    }

    private func startEditing() {
        draftTitle = item.title
        isEditing = true
        DispatchQueue.main.async { isTitleFocused = true }
    }

    private func finishEditing() {
        guard isEditing else { return }
        isEditing = false
        isTitleFocused = false
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty && title != item.title {
            Task { await model.rename(item, to: title) }
        }
    }
}

private struct ItemTitleParts {
    let name: String
    let prefix: String?
    let suffix: String?

    init(_ title: String) {
        var remaining = title
        var leading: String?
        var trailing: String?
        if let match = Self.prefixPattern.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
           let tagRange = Range(match.range(at: 1), in: remaining),
           let nameRange = Range(match.range(at: 2), in: remaining) {
            leading = String(remaining[tagRange])
            remaining = String(remaining[nameRange])
        }
        if let match = Self.suffixPattern.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
           let nameRange = Range(match.range(at: 1), in: remaining),
           let tagRange = Range(match.range(at: 2), in: remaining) {
            trailing = String(remaining[tagRange])
            remaining = String(remaining[nameRange])
        }
        name = remaining
        prefix = leading
        suffix = trailing
    }

    private static let prefixPattern = try! NSRegularExpression(
        pattern: #"^((?:\d+(?:[.,]\d+)?\s*)?(?:x|×|kg|g|mg|l|ml|Stück|Stk\.?))\s+(.+)$"#,
        options: [.caseInsensitive]
    )
    private static let suffixPattern = try! NSRegularExpression(
        pattern: #"^(.+?)\s+((?:\d+(?:[.,]\d+)?\s*)?(?:x|×|kg|g|mg|l|ml|Stück|Stk\.?))$"#,
        options: [.caseInsensitive]
    )
}

/// Card look in the pager, edge-to-edge surface full screen.
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
