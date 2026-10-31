import MarqetCore
import SwiftUI

/// Last page (KONZEPT §7.8): "Meine Läden" without a card, then – set apart – a few nearby chains
/// to discover. Own stores and chains the user never added are never mixed in one grid.
struct MoreStoresCard: View {
    /// Chains shown under "Entdecken"; the full catalog stays in "Laden hinzufügen".
    static let discoverLimit = 6

    @Environment(AppModel.self) private var model
    @State private var showsAddStore = false
    @State private var isSelecting = false
    @State private var selection: Set<Tile> = []
    /// A chain tapped under "Entdecken": shown before anything is added.
    @State private var previewEntry: StoreCatalog.Entry?
    @State private var leafletURL: URL?

    private enum Tile: Hashable {
        case own(Store.ID)
        case catalog(String)
    }

    var body: some View {
        GeometryReader { proxy in
            let columnCount = max(1, Int((proxy.size.width - 40 + 12) / 104))
            let own = distanceSorted(model.hiddenStores) { distance(for: $0.id) }.map { Tile.own($0.id) }
            let allSuggestions = distanceSorted(model.catalogSuggestions) { distance(forCatalogKey: $0.key) }
            let discover = allSuggestions.prefix(Self.discoverLimit).map { Tile.catalog($0.key) }

            VStack(alignment: .leading, spacing: 12) {
                header(isEmpty: own.isEmpty && discover.isEmpty)
                    .padding(.horizontal, 20)
                if own.isEmpty && discover.isEmpty {
                    ContentUnavailableView(
                        "Keine weiteren Läden",
                        systemImage: "storefront",
                        description: Text("Füge einen Laden hinzu, um hier eine weitere Liste zu starten.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if !own.isEmpty {
                                section(
                                    title: "Meine Läden",
                                    detail: "Gespeichert, gerade ohne Card. Antippen, um etwas einzutragen.",
                                    tiles: own,
                                    columns: columnCount
                                )
                            }
                            if !discover.isEmpty {
                                section(
                                    title: "Entdecken",
                                    detail: "In deiner Nähe, noch nicht bei deinen Läden.",
                                    tiles: Array(discover),
                                    columns: columnCount
                                )
                                if allSuggestions.count > discover.count {
                                    Button("Alle Läden anzeigen") { showsAddStore = true }
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.visible)
                    .scrollEdgeEffectStyle(.soft, for: .bottom)
                }
            }
            // The button floats unblurred above the soft edge effect, at the same height as
            // "Läden zuordnen". The list runs to the card edge underneath it.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                bottomButton
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
        .sheet(item: Binding(get: { leafletURL.map(LeafletLink.init) }, set: { if $0 == nil { leafletURL = nil } })) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
        .confirmationDialog(
            previewEntry?.name ?? "",
            isPresented: Binding(get: { previewEntry != nil }, set: { if !$0 { previewEntry = nil } }),
            titleVisibility: .visible,
            presenting: previewEntry
        ) { entry in
            Button("Anheften", systemImage: "pin") { pin(entry) }
            Button("Eintrag hinzufügen", systemImage: "plus") { addItem(at: entry) }
            if let url = entry.leafletURL {
                Button("Prospekt ansehen", systemImage: "newspaper") { leafletURL = url }
            }
        } message: { entry in
            if let meters = distance(forCatalogKey: entry.key) {
                Text("Noch nicht bei deinen Läden. Nächste Filiale \(AppModel.distanceText(meters: meters)).")
            } else {
                Text("Noch nicht bei deinen Läden.")
            }
        }
        .task {
            await model.refreshNearbyCatalogDistancesIfNeeded()
        }
    }

    private func header(isEmpty: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Weitere Läden")
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if isSelecting && !selection.isEmpty {
                Button("\(selection.count) anheften") { pinSelection() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill), in: .capsule)
                    .buttonStyle(.plain)
            }
            if !isEmpty {
                Button(isSelecting ? "Fertig" : "Auswählen") {
                    isSelecting.toggle()
                    if !isSelecting { selection = [] }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: .capsule)
                .buttonStyle(.plain)
                .accessibilityHint(isSelecting ? "" : String(localized: "Mehrere Läden auf einmal anheften"))
            }
        }
    }

    private func section(title: LocalizedStringKey, detail: LocalizedStringKey, tiles: [Tile], columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                ForEach(rows(of: tiles, columns: columns).indices, id: \.self) { index in
                    tileRow(rows(of: tiles, columns: columns)[index], columns: columns)
                }
            }
        }
    }

    private func rows(of tiles: [Tile], columns: Int) -> [[Tile]] {
        stride(from: 0, to: tiles.count, by: columns).map {
            Array(tiles[$0..<min($0 + columns, tiles.count)])
        }
    }

    /// Secondary counterpart of `TriageButton`: same glass capsule, without the accent tint.
    private var bottomButton: some View {
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
                ForEach(0..<(columns - tiles.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
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

    /// Own store: fill it. A chain the user does not have yet: show it first, nothing is added
    /// by a mere tap.
    private func open(_ tile: Tile) {
        switch tile {
        case .own(let id):
            model.startComposer(on: .store(id))
        case .catalog(let key):
            previewEntry = model.catalog?.entry(forKey: key)
        }
    }

    private func pin(_ entry: StoreCatalog.Entry) {
        let page = PageID.store(model.addStore(from: entry, planned: true).id)
        model.activePage = page
        model.pageRequest = page
    }

    private func addItem(at entry: StoreCatalog.Entry) {
        let store = model.addStore(from: entry, planned: true)
        model.startComposer(on: .store(store.id))
    }

    /// Pins several stores at once: their cards appear, to be filled later (KONZEPT §7.8).
    private func pinSelection() {
        var first: PageID?
        for tile in selection {
            let id: Store.ID?
            switch tile {
            case .own(let storeID):
                model.pin(storeID)
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

private struct LeafletLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
