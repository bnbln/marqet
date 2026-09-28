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
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else if mode == .board {
                    TriageOverview(showsAddStore: $showsAddStore)
                        .safeAreaInset(edge: .bottom) { LastStepLine() }
                } else {
                    TriageCards(showsAddStore: $showsAddStore)
                }
            }
            .animation(.smooth(duration: 0.35), value: model.triageQueue.isEmpty)
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

/// The end of a round as a small reward: the check pops, then every step of the round comes up
/// as a pill, one after the other with a light tick each, closed by a success haptic and a ring
/// around the check. "Fertig" sits full width at the thumb.
private struct TriageSummary: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsPaywall = false
    @State private var viewportHeight: CGFloat = 0
    @State private var hasAppeared = false
    /// Pills shown so far.
    @State private var revealed = 0
    @State private var isComplete = false

    var body: some View {
        let history = model.triage?.history ?? []
        ScrollView {
            content(history)
                .frame(maxWidth: .infinity, minHeight: viewportHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .sensoryFeedback(trigger: revealed) { _, count in
            // Ticks grow a little firmer towards the end.
            count > 0 ? .impact(weight: .light, intensity: min(1, 0.45 + Double(count) * 0.05)) : nil
        }
        .sensoryFeedback(.success, trigger: isComplete)
        .task { await reveal(count: history.count) }
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }

    private func reveal(count: Int) async {
        guard !reduceMotion else {
            hasAppeared = true
            revealed = count
            isComplete = true
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { hasAppeared = true }
        try? await Task.sleep(for: .milliseconds(380))
        // About a second and a half for the whole round, however long it was.
        let step = min(0.13, 1.5 / Double(max(count, 1)))
        for index in stride(from: 1, through: count, by: 1) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.58)) { revealed = index }
            try? await Task.sleep(for: .seconds(step))
        }
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { isComplete = true }
    }

    private func content(_ history: [TriageSession.Step]) -> some View {
        let assigned = model.triage?.assignedCount ?? 0
        let autoAssignable = model.triage?.autoAssignable ?? 0
        let skipped = model.triageSkippedItems.count
        let allSkipped = assigned == 0 && skipped > 0
        return VStack(spacing: 16) {
            badge(allSkipped: allSkipped)
            Group {
                if allSkipped {
                    Text(skipped == 1 ? "1 Eintrag übersprungen" : "\(skipped) Einträge übersprungen")
                } else {
                    Text(assigned == 1 ? "1 Eintrag zugeordnet" : "\(assigned) Einträge zugeordnet")
                }
            }
            .font(.title2.bold())
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            if assigned > 0, skipped > 0 {
                Text(skipped == 1 ? "1 Eintrag hast du übersprungen." : "\(skipped) Einträge hast du übersprungen.")
                    .foregroundStyle(.secondary)
            }
            // Every step of the round; hidden pills keep their place so nothing jumps.
            if !history.isEmpty {
                CenteredFlow {
                    ForEach(Array(history.enumerated()), id: \.offset) { index, step in
                        let isShown = index < revealed
                        StepPill(step: step)
                            .scaleEffect(isShown ? 1 : 0.5)
                            .opacity(isShown ? 1 : 0)
                            .offset(y: isShown ? 0 : 12)
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
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }

    /// The check pops in, bounces once all pills are there and sends a ring out.
    private func badge(allSkipped: Bool) -> some View {
        ZStack {
            if !allSkipped {
                Circle()
                    .stroke(.tint, lineWidth: 3)
                    .frame(width: 64, height: 64)
                    .scaleEffect(isComplete ? 2.1 : 1)
                    .opacity(isComplete ? 0 : (hasAppeared ? 0.5 : 0))
                    .animation(.easeOut(duration: 0.9), value: isComplete)
            }
            Image(systemName: allSkipped ? "tray.full.fill" : "checkmark.circle.fill")
                .font(.system(size: allSkipped ? 56 : 64))
                .foregroundStyle(allSkipped ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .symbolEffect(.bounce, value: isComplete)
        }
        .scaleEffect(hasAppeared ? 1 : 0.3)
        .opacity(hasAppeared ? 1 : 0)
    }

    private var actions: some View {
        VStack(spacing: 4) {
            if model.triageSkippedItems.isEmpty {
                TriageWideButton(title: String(localized: "Fertig")) { model.endTriage() }
            } else {
                Button("Später") { model.endTriage() }
                    .font(.body.weight(.semibold))
                    .frame(height: 44)
                    .tint(.primary)
                TriageWideButton(title: String(localized: "Jetzt zuordnen")) {
                    withAnimation(.snappy) { model.triageRevisitSkipped() }
                }
            }
        }
        .padding(.bottom, 8)
    }
}
