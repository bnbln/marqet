import MarqetCore
import SwiftUI

/// Last page: hidden own stores, catalog suggestions, "add store" (KONZEPT §7.8).
struct MoreStoresCard: View {
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
            let availableGridHeight = max(120, proxy.size.height - 20 - 42 - 12 - 96)
            let rowsThatFit = max(1, Int((availableGridHeight + 12) / 116))
            let hidden = distanceSorted(model.hiddenStores) { distance(for: $0.id) }
            let suggestions = distanceSorted(model.catalogSuggestions) { distance(forCatalogKey: $0.key) }
            let tiles = hidden.map { Tile.own($0.id) } + suggestions.map { Tile.catalog($0.key) }
            let rows = stride(from: 0, to: tiles.count, by: columnCount).map {
                Array(tiles[$0..<min($0 + columnCount, tiles.count)])
            }
            let rowSpacing = rows.count > 1 && rows.count <= rowsThatFit
                ? min(42, max(12, (availableGridHeight - CGFloat(rows.count * 104)) / CGFloat(rows.count - 1)))
                : 12

            VStack(alignment: .leading, spacing: 12) {
                header
                    .padding(.horizontal, 20)
                if rows.isEmpty {
                    ContentUnavailableView(
                        "Keine weiteren Läden",
                        systemImage: "storefront",
                        description: Text("Füge einen Laden hinzu, um hier eine weitere Liste zu starten.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: rowSpacing) {
                            ForEach(rows.indices, id: \.self) { index in
                                tileRow(rows[index], columns: columnCount)
                            }
                        }
                        .frame(minHeight: availableGridHeight, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.visible)
                    .scrollEdgeEffectStyle(.soft, for: .bottom)
                }
            }
            // The button floats unblurred above the soft edge effect, at the same height as
            // "Läden zuordnen". The list runs to the card edge underneath it.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                addStoreButton
                    .padding(.top, 10)
                    .padding(.bottom, 34)
            }
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cardSurface()
        .sheet(isPresented: $showsAddStore) {
            AddStoreSheet()
                .leadingSheetPlacement()
        }
        .task {
            await model.refreshNearbyCatalogDistancesIfNeeded()
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

    /// Secondary counterpart of `TriageButton`: same glass capsule, without the accent tint.
    private var addStoreButton: some View {
        Button { showsAddStore = true } label: {
            Label("Laden hinzufügen", systemImage: "plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 22)
                .frame(height: 52)
                .glassEffect(.regular.interactive(), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
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

    private func tileRow(_ tiles: [Tile], columns: Int) -> some View {
        HStack(spacing: 12) {
            ForEach(tiles, id: \.self) { tile in
                tileView(tile)
                    .frame(maxWidth: .infinity)
            }
            if tiles.count < columns {
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func tileView(_ selectionTile: Tile) -> some View {
        switch selectionTile {
        case .own(let id):
            if let store = model.store(id) {
                tile(.own(id), name: store.name) { StoreBadge(store: store, size: 48) }
            }
        case .catalog(let key):
            if let entry = model.catalog?.entry(forKey: key) {
                tile(.catalog(key), name: entry.name) { StoreBadge(store: entry.makeStore(sortIndex: 0), size: 48) }
            }
        }
    }

    private func distance(for storeID: Store.ID) -> Double? {
        guard let origin = model.userLocation,
              let location = model.relevantLocation(of: storeID) else { return nil }
        return location.coordinate.distance(to: origin)
    }

    private func distance(forCatalogKey key: String) -> Double? {
        if let origin = model.userLocation,
           let store = model.stores.first(where: { $0.catalogKey == key }),
           let location = model.relevantLocation(of: store.id) {
            return location.coordinate.distance(to: origin)
        }
        return model.nearbyCatalogDistances[key]
    }

    private func distanceSorted<Element>(_ values: [Element], distance: (Element) -> Double?) -> [Element] {
        guard model.userLocation != nil else { return values }
        return values.enumerated().sorted { lhs, rhs in
            let left = distance(lhs.element)
            let right = distance(rhs.element)
            switch (left, right) {
            case let (left?, right?) where left != right: return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
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
