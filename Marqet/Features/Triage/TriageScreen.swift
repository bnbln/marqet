import MarqetCore
import SwiftUI

/// Assign inbox items to stores (KONZEPT §7.4) in two modes:
/// - "Nacheinander": one item at a time above big store tiles. On regular width (iPad, iPhone Duo
///   inside) item and tiles sit side by side (KONZEPT-DUO-IPAD §4.4).
/// - "Übersicht": a table with one row per item and one column per store; a tap assigns.
/// Both offer the pending suggestions as one step and show the last step at the bottom.
struct TriageScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showsAddStore = false
    @State private var undoFeedback = 0

    private var mode: TriageSession.Mode { model.triage?.mode ?? .single }

    var body: some View {
        NavigationStack {
            Group {
                if model.triageQueue.isEmpty {
                    TriageSummary()
                } else if mode == .board {
                    TriageOverview(showsAddStore: $showsAddStore)
                } else if sizeClass == .regular {
                    AdaptiveSplit {
                        ScrollView { SingleItemPane().padding(20) }
                    } secondary: {
                        ScrollView { StoreTileGrid(showsAddStore: $showsAddStore).padding(20) }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            SingleItemPane()
                            StoreTileGrid(showsAddStore: $showsAddStore)
                        }
                        .padding(20)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                if !model.triageQueue.isEmpty { LastStepLine() }
            }
            .animation(.snappy, value: mode)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sensoryFeedback(.impact(weight: .light), trigger: undoFeedback)
            .sensoryFeedback(.selection, trigger: model.triage?.history.count)
            .sheet(isPresented: $showsAddStore) {
                AddStoreSheet(opensComposer: false).leadingSheetPlacement()
            }
        }
        .task { Task { await model.refreshPrices() } }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close) { model.endTriage() }
                .tint(.primary)
        }
        ToolbarItem(placement: .principal) {
            if model.triageQueue.isEmpty {
                Text("Zuordnen").font(.headline)
            } else {
                Picker("Modus", selection: Binding(get: { mode }, set: { model.setTriageMode($0) })) {
                    Text("Nacheinander").tag(TriageSession.Mode.single)
                    Text("Übersicht").tag(TriageSession.Mode.board)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Rückgängig", systemImage: "arrow.uturn.backward") {
                undoFeedback += 1
                Task { await model.triageUndo() }
            }
            .tint(.primary)
            .disabled(model.triage?.history.isEmpty ?? true)
        }
    }
}

// MARK: - Nacheinander

/// Question, progress, suggestions shortcut, the current item and what comes next.
private struct SingleItemPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let item = model.triageQueue.first {
            let progress = model.triageProgress
            VStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("Wo kaufst du das?")
                        .font(.title3.bold())
                    Text("\(progress.position) von \(progress.total)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                if model.triageSuggestions.count >= 2 {
                    AcceptSuggestionsButton()
                }
                ItemCardView(item: item)
                    .id(item.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity)
                    ))
                let upcoming = model.triageQueue.dropFirst().prefix(3).map(\.title)
                if !upcoming.isEmpty {
                    Text("Als Nächstes: \(upcoming.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
            .animation(.snappy, value: item.id)
        }
    }
}

private struct ItemCardView: View {
    let item: ShoppingItem
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            Text(item.title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
            if let notes = item.userNotes {
                Text(notes)
                    .foregroundStyle(.secondary)
            }
            Label(model.category(of: item).displayName, systemImage: model.category(of: item).symbol)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let hint = model.priceHint(for: item) {
                PriceHintLine(hint: hint)
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(20)
        .cardSurface()
    }
}

/// Store tiles in a fixed order (muscle memory); the current item's suggestion is only highlighted.
/// A tap assigns the current item. Below: "Später" and "Laden hinzufügen".
private struct StoreTileGrid: View {
    @Binding var showsAddStore: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let item = model.triageQueue.first
        let highlighted = item.flatMap(model.suggestion(for:))
        let prices = item.flatMap(model.priceHint(for:))
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 140), spacing: 10)], spacing: 10) {
                ForEach(model.sortedStores) { store in
                    let suggestion = highlighted?.storeID == store.id ? highlighted : nil
                    let price = prices?.price(of: store.id)
                    let isCheapest = prices?.isCheapest(store.id) == true
                    Button {
                        guard let item else { return }
                        Task { await model.triageAssign(item, to: store) }
                    } label: {
                        // A habit keeps its label; otherwise the tile shows the price (tag on the cheapest).
                        let showsLabel = suggestion != nil && (suggestion?.source != .price || price == nil)
                        StoreTile(
                            store: store,
                            caption: showsLabel ? suggestion?.label : price?.shortText,
                            captionSymbol: showsLabel ? suggestion?.symbol : (isCheapest ? "tag.fill" : nil),
                            highlight: suggestion == nil ? nil : store.readableColor,
                            fill: Color(.secondarySystemGroupedBackground)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(suggestion == nil ? "" : String(localized: "Vorschlag"))
                    .accessibilityValue(price?.displayText ?? "")
                }
            }

            HStack(spacing: 10) {
                SecondaryTriageButton(title: "Später", symbol: "arrow.turn.up.right") {
                    guard let item else { return }
                    withAnimation(.snappy) { model.triageSkip(item) }
                }
                SecondaryTriageButton(title: "Laden hinzufügen", symbol: "plus") {
                    showsAddStore = true
                }
            }
            if prices != nil {
                OpenPricesAttribution()
            }
        }
    }
}

private struct SecondaryTriageButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20, style: .continuous))
                .contentShape(.rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension StoreSuggestion {
    var label: String {
        switch source {
        case .learned, .similar: String(localized: "Wie zuletzt")
        case .intelligence, .storeType: String(localized: "Vorschlag")
        case .price: String(localized: "Am günstigsten")
        }
    }

    var symbol: String {
        switch source {
        case .learned, .similar: "arrow.counterclockwise"
        case .intelligence, .storeType: "sparkles"
        case .price: "tag.fill"
        }
    }
}

// MARK: - Übersicht

/// One row per item, one column per store – like a poll. The first stores in the user's order get
/// a column; the rest sit behind "…" in each row. A tap assigns right away, there is no selection.
private struct TriageOverview: View {
    @Binding var showsAddStore: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let cellWidth: CGFloat = 52

    var body: some View {
        let maxColumns = sizeClass == .regular ? 8 : 4
        let stores = model.sortedStores
        let hasOverflow = stores.count > maxColumns
        let columns = hasOverflow ? Array(stores.prefix(maxColumns - 1)) : stores
        let overflow = hasOverflow ? Array(stores.dropFirst(maxColumns - 1)) : []

        ScrollView {
            VStack(spacing: 16) {
                if !model.triageSuggestions.isEmpty {
                    AcceptSuggestionsButton()
                }
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        VStack(spacing: 0) {
                            ForEach(model.triageQueue) { item in
                                OverviewRow(item: item, columns: columns, overflow: overflow, cellWidth: cellWidth)
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                                if item.id != model.triageQueue.last?.id {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20, style: .continuous))
                    } header: {
                        header(columns: columns, hasOverflow: hasOverflow)
                    }
                }
                .animation(.snappy, value: model.triageQueue.map(\.id))

                SecondaryTriageButton(title: "Laden hinzufügen", symbol: "plus") {
                    showsAddStore = true
                }
                if model.triageQueue.contains(where: { model.priceHint(for: $0) != nil }) {
                    OpenPricesAttribution()
                }
            }
            .padding(16)
        }
    }

    private func header(columns: [Store], hasOverflow: Bool) -> some View {
        HStack(spacing: 0) {
            Text("Artikel")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns) { store in
                VStack(spacing: 3) {
                    StoreBadge(store: store, size: 30)
                    Text(store.name)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: cellWidth)
                .accessibilityElement(children: .combine)
            }
            if hasOverflow {
                Text("Weitere")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: cellWidth)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
}

private struct OverviewRow: View {
    let item: ShoppingItem
    let columns: [Store]
    let overflow: [Store]
    let cellWidth: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        let suggestion = model.suggestion(for: item)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .foregroundStyle(.primary)
                if let suggestion, let store = model.store(suggestion.storeID) {
                    // A price suggestion names store and price: "🏷 Lidl · 0,95 €/l".
                    let price = suggestion.source == .price ? model.priceHint(for: item)?.price(of: store.id) : nil
                    Label(price.map { "\(store.name) · \($0.shortText)" } ?? "\(suggestion.label): \(store.name)",
                          systemImage: suggestion.symbol)
                        .font(.caption)
                        .foregroundStyle(store.readableColor)
                        .lineLimit(1)
                }
                // A habit or Apple Intelligence stays; the cheapest store is named below it.
                if suggestion?.source != .price, let cheapest = model.priceHint(for: item)?.cheapest,
                   let store = model.store(cheapest.storeID) {
                    Label("\(store.name) · \(cheapest.price.shortText)", systemImage: "tag")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)

            ForEach(columns) { store in
                let isSuggested = suggestion?.storeID == store.id
                Button {
                    Task { await model.triageAssign(item, to: store) }
                } label: {
                    Circle()
                        .strokeBorder(isSuggested ? store.readableColor : Color(.tertiaryLabel), lineWidth: isSuggested ? 2.5 : 1.5)
                        .background(Circle().fill(isSuggested ? store.color.opacity(0.18) : .clear))
                        .frame(width: 30, height: 30)
                        .frame(width: cellWidth, height: 52)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title) zu \(store.name)")
                .accessibilityHint(isSuggested ? String(localized: "Vorschlag") : "")
            }
            if !overflow.isEmpty {
                Menu {
                    ForEach(overflow) { store in
                        Button(store.name) {
                            Task { await model.triageAssign(item, to: store) }
                        }
                    }
                } label: {
                    let isSuggested = overflow.contains { $0.id == suggestion?.storeID }
                    Image(systemName: isSuggested ? "ellipsis.circle.fill" : "ellipsis.circle")
                        .font(.title2)
                        .foregroundStyle(isSuggested ? Color.accentColor : .secondary)
                        .frame(width: cellWidth, height: 52)
                        .contentShape(.rect)
                }
                .accessibilityLabel("\(item.title) zu weiterem Laden")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
    }
}

// MARK: - Shared

/// "4 Vorschläge übernehmen" – every item with a suggestion in one step.
private struct AcceptSuggestionsButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let suggestions = model.triageSuggestions
        Button {
            Task { await model.triageAcceptAllSuggestions() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestions.count == 1 ? "1 Vorschlag übernehmen" : "\(suggestions.count) Vorschläge übernehmen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(summary(of: suggestions))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20, style: .continuous))
            .contentShape(.rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// "Rewe 3 · dm 2"
    private func summary(of suggestions: [(item: ShoppingItem, store: Store)]) -> String {
        var counts: [(store: Store, count: Int)] = []
        for (_, store) in suggestions {
            if let index = counts.firstIndex(where: { $0.store.id == store.id }) {
                counts[index].count += 1
            } else {
                counts.append((store, 1))
            }
        }
        return counts.map { "\($0.store.name) \($0.count)" }.joined(separator: " · ")
    }
}

/// "Batterien AA → Rewe": where the last step went, next to "Rückgängig" in meaning.
private struct LastStepLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.triage?.history.last {
            case .assigned(let itemID, let storeID):
                if let item = model.items.first(where: { $0.id == itemID }), let store = model.store(storeID) {
                    line(Text("\(item.title) → \(store.name)")) { StoreBadge(store: store, size: 20) }
                        .id(model.triage?.history.count)
                }
            case .skipped(let itemID):
                if let item = model.items.first(where: { $0.id == itemID }) {
                    line(Text("\(item.title) kommt später")) {
                        Image(systemName: "arrow.turn.up.right").foregroundStyle(.secondary)
                    }
                    .id(model.triage?.history.count)
                }
            case nil:
                EmptyView()
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.snappy, value: model.triage?.history.count)
    }

    private func line(_ text: Text, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 8) {
            icon()
            text.lineLimit(1)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 8)
    }
}

// MARK: - Summary

private struct TriageSummary: View {
    @Environment(AppModel.self) private var model
    @State private var showsPaywall = false

    var body: some View {
        let assigned = model.triage?.assignedCount ?? 0
        let autoAssignable = model.triage?.autoAssignable ?? 0
        let skipped = model.triageSkippedItems.count
        VStack(spacing: 16) {
            if assigned == 0, skipped > 0 {
                // Everything skipped: no success check, just what is still open.
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text(skipped == 1 ? "1 Eintrag übersprungen" : "\(skipped) Einträge übersprungen")
                    .font(.title2.bold())
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text(assigned == 1 ? "1 Eintrag zugeordnet" : "\(assigned) Einträge zugeordnet")
                    .font(.title2.bold())
            }
            if assigned > 0, skipped > 0 {
                Text(skipped == 1 ? "1 Eintrag hast du übersprungen." : "\(skipped) Einträge hast du übersprungen.")
                    .foregroundStyle(.secondary)
            }
            if !model.isPro, autoAssignable > 0 {
                Label(autoAssignable == 1
                      ? "Mit Marqet Pro wäre einer davon automatisch zugeordnet worden."
                      : "Mit Marqet Pro wären \(autoAssignable) davon automatisch zugeordnet worden.",
                      systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Mehr über Marqet Pro") { showsPaywall = true }
                    .font(.subheadline.weight(.semibold))
            }
            if skipped > 0 {
                Button("Jetzt zuordnen") {
                    withAnimation(.snappy) { model.triageRevisitSkipped() }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                Button("Später") { model.endTriage() }
                    .font(.body.weight(.semibold))
            } else {
                Button("Fertig") { model.endTriage() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }
}
