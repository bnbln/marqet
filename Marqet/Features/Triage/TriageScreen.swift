import MarqetCore
import SwiftUI

/// Assign inbox items to stores (KONZEPT §7.4): one item at a time, or a board to pick several.
/// Both modes use the same store tiles and the same bottom bar. On regular width (iPad, iPhone Duo
/// inside) items and stores sit side by side (KONZEPT-DUO-IPAD §4.4).
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
                } else if sizeClass == .regular {
                    AdaptiveSplit {
                        itemsPane
                    } secondary: {
                        ScrollView {
                            StoreTileGrid(showsAddStore: $showsAddStore).padding(20)
                        }
                    }
                } else if mode == .board {
                    VStack(spacing: 0) {
                        TriageBoardList()
                        ScrollView {
                            StoreTileGrid(showsAddStore: $showsAddStore).padding(16)
                        }
                        .frame(maxHeight: 250)
                        .background(Color(.secondarySystemGroupedBackground).opacity(0.6))
                    }
                } else {
                    SingleTriageView(showsAddStore: $showsAddStore)
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                if !model.triageQueue.isEmpty { TriageBottomBar() }
            }
            .animation(.snappy, value: mode)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sensoryFeedback(.impact(weight: .light), trigger: undoFeedback)
            .sheet(isPresented: $showsAddStore) {
                AddStoreSheet(opensComposer: false).leadingSheetPlacement()
            }
        }
    }

    @ViewBuilder
    private var itemsPane: some View {
        if mode == .board {
            TriageBoardList()
        } else {
            SingleTriageView(showsAddStore: $showsAddStore, showsStoreGrid: false)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close) { model.endTriage() }
        }
        ToolbarItem(placement: .principal) {
            if model.triageQueue.isEmpty {
                Text("Zuordnen").font(.headline)
            } else {
                Picker("Modus", selection: Binding(get: { mode }, set: { model.triage?.mode = $0 })) {
                    Text("Einzeln").tag(TriageSession.Mode.single)
                    Text("Mehrere").tag(TriageSession.Mode.board)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Rückgängig", systemImage: "arrow.uturn.backward") {
                undoFeedback += 1
                Task { await model.triageUndo() }
            }
            .disabled(model.triage?.history.isEmpty ?? true)
        }
    }
}

// MARK: - Single item

private struct SingleTriageView: View {
    @Binding var showsAddStore: Bool
    var showsStoreGrid = true
    @Environment(AppModel.self) private var model

    var body: some View {
        if let item = model.triageQueue.first {
            ScrollView {
                VStack(spacing: 20) {
                    progress
                    ItemCardView(item: item)
                        .id(item.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .scale(scale: 0.8).combined(with: .opacity)))
                    if showsStoreGrid {
                        StoreTileGrid(showsAddStore: $showsAddStore)
                    }
                }
                .padding(20)
                .animation(.snappy, value: item.id)
            }
        }
    }

    private var progress: some View {
        let total = model.triage?.itemIDs.count ?? 0
        let done = total - model.triageQueue.count
        return VStack(spacing: 6) {
            Text("\(done + 1) von \(total)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ProgressView(value: Double(done), total: Double(max(total, 1)))
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
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(20)
        .cardSurface()
    }
}

// MARK: - Store tiles

/// Store tiles in a fixed order (muscle memory); a suggestion is only highlighted.
/// Single mode: a tap assigns the current item. Board: a tap assigns the selection, and items can be
/// dragged onto a tile.
private struct StoreTileGrid: View {
    @Binding var showsAddStore: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let isBoard = model.triage?.mode == .board
        let selectionEmpty = model.triage?.selection.isEmpty ?? true
        let highlighted = highlightedSuggestion(isBoard: isBoard)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 140), spacing: 10)], spacing: 10) {
            ForEach(model.sortedStores) { store in
                let suggestion = highlighted?.storeID == store.id ? highlighted : nil
                Button {
                    Task { await assign(to: store, isBoard: isBoard) }
                } label: {
                    StoreTile(
                        store: store,
                        caption: suggestion?.label,
                        captionSymbol: suggestion?.symbol,
                        highlight: suggestion == nil ? nil : store.readableColor,
                        isDimmed: isBoard && selectionEmpty,
                        fill: Color(.secondarySystemGroupedBackground)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint(suggestion == nil ? "" : String(localized: "Vorschlag"))
                .dropDestination(for: String.self) { ids, _ in
                    let items = model.triageQueue.filter { ids.contains($0.id) }
                    guard !items.isEmpty else { return false }
                    Task { for item in items { await model.triageAssign(item, to: store) } }
                    return true
                }
            }
            Button { showsAddStore = true } label: {
                AddStoreTile(fill: Color(.secondarySystemGroupedBackground))
            }
            .buttonStyle(.plain)
        }
    }

    /// Single: the current item's suggestion. Board: the store all selected items point to, if any.
    private func highlightedSuggestion(isBoard: Bool) -> StoreSuggestion? {
        guard isBoard else { return model.triageQueue.first.flatMap(model.suggestion(for:)) }
        let selected = model.triageQueue.filter { model.triage?.selection.contains($0.id) == true }
        let suggestions = selected.map(model.suggestion(for:))
        guard let first = suggestions.first ?? nil,
              suggestions.allSatisfy({ $0?.storeID == first.storeID }) else { return nil }
        return first
    }

    private func assign(to store: Store, isBoard: Bool) async {
        if isBoard {
            await model.triageAssignSelection(to: store)
        } else if let item = model.triageQueue.first {
            await model.triageAssign(item, to: store)
        }
    }
}

extension StoreSuggestion {
    var label: String {
        switch source {
        case .learned, .similar: String(localized: "Wie zuletzt")
        case .intelligence: String(localized: "Vorschlag")
        case .storeType: String(localized: "Passt zum Laden")
        }
    }

    var symbol: String {
        switch source {
        case .learned, .similar: "arrow.counterclockwise"
        case .intelligence, .storeType: "sparkles"
        }
    }
}

// MARK: - Bottom bar

/// Same in both modes: "Überspringen" (single) right above the main action, which takes over all
/// suggestions. A plain glass button, not a prominent one – it is an offer, not the next step.
private struct TriageBottomBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let suggestions = model.triageSuggestions
        VStack(spacing: 10) {
            if model.triage?.mode != .board, let item = model.triageQueue.first {
                Button("Überspringen") {
                    withAnimation(.snappy) { model.triageSkip(item) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            if !suggestions.isEmpty {
                Button {
                    Task { await model.triageAcceptAllSuggestions() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestions.count == 1
                                 ? "1 Eintrag wie vorgeschlagen zuordnen"
                                 : "\(suggestions.count) Einträge wie vorgeschlagen zuordnen")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(summary(of: suggestions))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: 420, minHeight: 56)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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

// MARK: - Board

private struct TriageBoardList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(model.triageQueue) { item in
                    let isSelected = model.triage?.selection.contains(item.id) == true
                    let suggestion = model.suggestion(for: item)
                    Button {
                        if isSelected { model.triage?.selection.remove(item.id) } else { model.triage?.selection.insert(item.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            Text(item.title).foregroundStyle(Color.primary)
                            Spacer()
                            if let suggestion, let store = model.store(suggestion.storeID) {
                                Label(store.name, systemImage: suggestion.symbol)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(store.color.opacity(0.18), in: .capsule)
                                    .foregroundStyle(Color.primary)
                            }
                        }
                    }
                    .draggable(item.id)
                    .accessibilityActions {
                        ForEach(model.sortedStores) { store in
                            Button("Zu \(store.name) zuordnen") {
                                Task { await model.triageAssign(item, to: store) }
                            }
                        }
                    }
                }
            } header: {
                Text("Wähle Artikel und füge sie unten einem Laden hinzu.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }
}

// MARK: - Summary

private struct TriageSummary: View {
    @Environment(AppModel.self) private var model
    @State private var showsPaywall = false

    var body: some View {
        let assigned = model.triage?.history.count ?? 0
        let autoAssignable = model.triage?.autoAssignable ?? 0
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(assigned == 1 ? "1 Eintrag zugeordnet" : "\(assigned) Einträge zugeordnet")
                .font(.title2.bold())
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
            Button("Fertig") { model.endTriage() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showsPaywall) { PaywallView() }
    }
}
