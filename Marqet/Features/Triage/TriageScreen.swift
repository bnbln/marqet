import MarqetCore
import SwiftUI

/// Assign unsorted items to stores (KONZEPT §7.4): one item at a time, or a board to drag onto.
/// On regular width (iPad, iPhone Duo inside) items and stores sit side by side (KONZEPT-DUO-IPAD §4.4).
struct TriageScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showsAddStore = false
    @State private var undoFeedback = 0

    var body: some View {
        NavigationStack {
            Group {
                if model.triageQueue.isEmpty {
                    TriageSummary()
                } else if sizeClass == .regular {
                    AdaptiveSplit {
                        itemsPane
                    } secondary: {
                        StoreTargets(showsAddStore: $showsAddStore)
                    }
                } else if model.triage?.mode == .board {
                    VStack(spacing: 0) {
                        StoreTargets(showsAddStore: $showsAddStore, compact: true)
                            .frame(maxHeight: 260)
                        Divider()
                        TriageBoardList()
                    }
                } else {
                    SingleTriageView(showsAddStore: $showsAddStore)
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                if !model.triageSuggestions.isEmpty {
                    Button {
                        Task { await model.triageAcceptAllSuggestions() }
                    } label: {
                        Label("Alle Vorschläge übernehmen (\(model.triageSuggestions.count))", systemImage: "sparkles")
                            .frame(maxWidth: 420)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Zuordnen")
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
        if model.triage?.mode == .board {
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
        ToolbarItem(placement: .confirmationAction) {
            Button(role: .confirm) { model.endTriage() }
        }
        if !(model.triage?.history.isEmpty ?? true) {
            ToolbarItem(placement: .bottomBar) {
                Button("Rückgängig", systemImage: "arrow.uturn.backward") {
                    undoFeedback += 1
                    Task { await model.triageUndo() }
                }
            }
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
                        StoreGrid(item: item, showsAddStore: $showsAddStore)
                    }
                    Button("Überspringen") {
                        withAnimation(.snappy) { model.triageSkip(item) }
                    }
                    .foregroundStyle(.secondary)
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

/// Store buttons in a fixed order (muscle memory); the suggestion is only highlighted.
/// Even column count, so the fold never splits a button (KONZEPT-DUO-IPAD §4.4).
private struct StoreGrid: View {
    let item: ShoppingItem
    @Binding var showsAddStore: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let suggestion = model.suggestion(for: item)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(model.sortedStores) { store in
                StoreTargetButton(store: store, suggestion: suggestion?.storeID == store.id ? suggestion : nil) {
                    Task { await model.triageAssign(item, to: store) }
                }
            }
            Button {
                showsAddStore = true
            } label: {
                Label("Laden", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct StoreTargetButton: View {
    let store: Store
    var suggestion: StoreSuggestion?
    var count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                StoreBadge(store: store, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if let suggestion {
                        Label(suggestion.label, systemImage: suggestion.symbol)
                            .font(.caption2.weight(.medium))
                            .labelStyle(.titleAndIcon)
                    } else if let count, count > 0 {
                        Text("\(count) Einträge")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(store.color.opacity(suggestion == nil ? 0.12 : 0.28), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(store.color, lineWidth: suggestion == nil ? 0 : 2.5)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityHint(suggestion == nil ? "" : "Vorschlag")
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

// MARK: - Board

/// Store drop zones; tap assigns the board selection (tap fallback, KONZEPT §7.4).
private struct StoreTargets: View {
    @Binding var showsAddStore: Bool
    var compact = false
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(model.sortedStores) { store in
                    StoreTargetButton(store: store, count: model.openItemCount(of: store.id)) {
                        Task { await assignFocused(to: store) }
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        let items = model.triageQueue.filter { ids.contains($0.id) }
                        guard !items.isEmpty else { return false }
                        Task { for item in items { await model.triageAssign(item, to: store) } }
                        return true
                    }
                }
                Button {
                    showsAddStore = true
                } label: {
                    Label("Laden", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
            }
            .padding(compact ? 12 : 20)
            if !compact {
                Text(model.triage?.mode == .board
                     ? "Einträge links auswählen oder ziehen, dann auf einen Laden tippen."
                     : "Tippe auf den Laden für den Eintrag links.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
        }
    }

    /// Board: assigns the selection. Single mode (side by side): assigns the current item.
    private func assignFocused(to store: Store) async {
        if model.triage?.mode == .board {
            await model.triageAssignSelection(to: store)
        } else if let item = model.triageQueue.first {
            await model.triageAssign(item, to: store)
        }
    }
}

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
            } footer: {
                Text("Auswählen und auf einen Laden tippen – oder einen Eintrag direkt auf den Laden ziehen.")
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
