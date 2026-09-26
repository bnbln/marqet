import MarqetCore
import SwiftUI

/// Last page: hidden own stores, catalog suggestions, "add store" (KONZEPT §7.8).
struct MoreStoresCard: View {
    var isFocused = false

    @Environment(AppModel.self) private var model
    @State private var showsAddStore = false
    @State private var isSelecting = false
    @State private var selection: Set<Tile> = []

    private enum Tile: Hashable {
        case own(Store.ID)
        case catalog(String)
    }

    var body: some View {
        GeometryReader { proxy in
            let columnCount = max(1, Int((proxy.size.width - 40 + 12) / 104))
            let rowCount = max(1, Int((proxy.size.height - 40 - 52 + 12) / 126))
            let storeCapacity = max(0, columnCount * rowCount - 1)
            let ownCount = min(model.hiddenStores.count, storeCapacity)
            let suggestionCount = max(0, storeCapacity - ownCount)

            VStack(alignment: .leading, spacing: 12) {
                header
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount), spacing: 12) {
                    ForEach(model.hiddenStores.prefix(ownCount)) { store in
                        tile(.own(store.id), name: store.name) { StoreBadge(store: store, size: 48) }
                    }
                    ForEach(model.catalogSuggestions.prefix(suggestionCount)) { entry in
                        tile(.catalog(entry.key), name: entry.name) {
                            StoreBadge(store: entry.makeStore(sortIndex: 0), size: 48)
                        }
                    }
                    addStoreTile
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cardSurface(isFocused: isFocused)
        .sheet(isPresented: $showsAddStore) {
            AddStoreSheet()
                .leadingSheetPlacement()
        }
    }

    private var header: some View {
        return HStack(alignment: .center, spacing: 8) {
            Text(model.hiddenStores.isEmpty ? "Weitere Läden" : "Deine Läden")
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if isSelecting {
                Button("\(selection.count) planen") { planSelection() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill), in: .capsule)
                    .buttonStyle(.plain)
                    .disabled(selection.isEmpty)
            }
            if !model.hiddenStores.isEmpty || !model.catalogSuggestions.isEmpty {
                Button {
                    isSelecting.toggle()
                    if !isSelecting { selection = [] }
                } label: {
                    Image(systemName: isSelecting ? "xmark" : "checklist")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .background(Color(.tertiarySystemFill), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelecting ? "Mehrfachauswahl beenden" : "Mehrere Läden planen")
            }
        }
    }

    private var addStoreTile: some View {
        Button { showsAddStore = true } label: { AddStoreTile() }
            .buttonStyle(.plain)
    }

    private func tile(_ tile: Tile, name: String, @ViewBuilder badge: () -> some View) -> some View {
        let isSelected = selection.contains(tile)
        let badge = badge()
        return Button {
            if isSelecting {
                if isSelected { selection.remove(tile) } else { selection.insert(tile) }
            } else {
                open(tile)
            }
        } label: {
            StoreTile(name: name, isSelected: isSelecting ? isSelected : nil) { badge }
        }
        .buttonStyle(.plain)
    }

    private func open(_ tile: Tile) {
        switch tile {
        case .own(let id):
            model.startComposer(on: .store(id))
        case .catalog(let key):
            guard let entry = model.catalog?.entry(forKey: key) else { return }
            let store = model.addStore(from: entry)
            model.startComposer(on: .store(store.id))
        }
    }

    /// Planning workflow: add several stores first, fill them later (KONZEPT §7.8).
    private func planSelection() {
        var first: PageID?
        for tile in selection {
            let id: Store.ID?
            switch tile {
            case .own(let storeID):
                model.plan(storeID)
                id = storeID
            case .catalog(let key):
                id = model.catalog?.entry(forKey: key).map { model.addStore(from: $0).id }
            }
            if first == nil, let id { first = .store(id) }
        }
        isSelecting = false
        selection = []
        if let first {
            model.activePage = first
            model.pageRequest = first
        }
    }
}
