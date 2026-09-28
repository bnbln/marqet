import MarqetCore
import SwiftUI

/// Assign inbox items to stores (KONZEPT §7.4). Zooms out of "Läden zuordnen" and closes by pulling
/// it down. Two views, chosen in the settings:
/// - Karten (default, `TriageCards`): a stack of items above the store grid – drag onto a store,
///   swipe aside for later or right for the suggestion.
/// - Tabelle: one row per item and one column per store; a tap assigns.
/// Both offer the pending suggestions as one step; the end lists every step of the session.
struct TriageScreen: View {
    @Environment(AppModel.self) private var model
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
                        .safeAreaInset(edge: .bottom) { LastStepLine() }
                } else {
                    TriageCards(showsAddStore: $showsAddStore)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(model.triageQueue.isEmpty ? String(localized: "Zuordnen") : String(localized: "Wo kaufst du das?"))
            .navigationSubtitle(subtitle)
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

    /// "3 von 12" on the cards, "12 offen" in the table.
    private var subtitle: String {
        guard !model.triageQueue.isEmpty else { return "" }
        if mode == .board { return String(localized: "\(model.triageQueue.count) offen") }
        let progress = model.triageProgress
        return String(localized: "\(progress.position) von \(progress.total)")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close) { model.endTriage() }
                .tint(.primary)
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

// MARK: - Tabelle

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
struct LastStepLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let step = model.triage?.history.last {
                StepPill(step: step)
                    .id(model.triage?.history.count)
                    .padding(.bottom, 8)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.snappy, value: model.triage?.history.count)
    }
}

/// One step of the session as a glass capsule: "Milch → Rewe" or "Brot kommt später".
private struct StepPill: View {
    let step: TriageSession.Step
    @Environment(AppModel.self) private var model

    var body: some View {
        switch step {
        case .assigned(let itemID, let storeID):
            if let item = model.items.first(where: { $0.id == itemID }), let store = model.store(storeID) {
                pill(Text("\(item.title) → \(store.name)")) { StoreBadge(store: store, size: 20) }
            }
        case .skipped(let itemID):
            if let item = model.items.first(where: { $0.id == itemID }) {
                pill(Text("\(item.title) kommt später")) {
                    Image(systemName: "arrow.turn.up.right").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pill(_ text: Text, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 8) {
            icon()
            text.lineLimit(1)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Rows of pills, centered, wrapping at the width.
private struct CenteredFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(of: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(of: subviews, width: bounds.width) {
            var x = bounds.midX - row.width / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(of subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width += spacing + size.width
                rows[rows.count - 1].height = max(last.height, size.height)
            } else {
                rows.append(([index], min(size.width, width), size.height))
            }
        }
        return rows
    }
}

// MARK: - Summary

private struct TriageSummary: View {
    @Environment(AppModel.self) private var model
    @State private var showsPaywall = false

    var body: some View {
        // Centered while it fits; a long session scrolls.
        ViewThatFits(in: .vertical) {
            content.frame(maxHeight: .infinity)
            ScrollView { content }
        }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    @ViewBuilder
    private var content: some View {
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
            // Every step of the session, as the pills that came up while assigning.
            if let history = model.triage?.history, !history.isEmpty {
                CenteredFlow {
                    ForEach(Array(history.enumerated()), id: \.offset) { _, step in
                        StepPill(step: step)
                    }
                }
                .padding(.vertical, 8)
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
        .frame(maxWidth: .infinity)
    }
}
