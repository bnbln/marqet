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

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !model.hiddenStores.isEmpty {
                    section("Deine Läden") {
                        ForEach(model.hiddenStores) { store in
                            tile(.own(store.id), name: store.name) { StoreBadge(store: store, size: 48) }
                        }
                    }
                }

                if !model.catalogSuggestions.isEmpty {
                    section(model.stores.isEmpty ? "Wo kaufst du ein?" : "Vorschläge") {
                        ForEach(model.catalogSuggestions.prefix(12)) { entry in
                            tile(.catalog(entry.key), name: entry.name) {
                                StoreBadge(store: entry.makeStore(sortIndex: 0), size: 48)
                            }
                        }
                        addStoreTile
                    }
                } else {
                    section("Läden") { addStoreTile }
                }
            }
            .padding(20)
            .padding(.bottom, 58)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cardSurface(isFocused: isFocused)
        .sheet(isPresented: $showsAddStore) {
            AddStoreSheet()
                .leadingSheetPlacement()
        }
    }

    private var header: some View {
        let nothingElse = model.deck.pages == [.unsorted, .more] && model.unsortedItems.isEmpty
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isSelecting ? "Läden auswählen" : (nothingElse ? "Alles eingekauft 🎉" : "Weitere Läden"))
                    .font(.title2.bold())
                Text(nothingElse
                     ? "Plane deinen nächsten Einkauf: Tippe auf einen Laden."
                     : "Tippe auf einen Laden, um etwas für ihn einzutragen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
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
            if isSelecting {
                Button("\(selection.count) planen") { planSelection() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.isEmpty)
            }
        }
    }

    private var addStoreTile: some View {
        Button { showsAddStore = true } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                    .frame(width: 48, height: 48)
                    .background(Color(.tertiarySystemFill), in: .circle)
                Text("Laden hinzufügen")
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 16) {
                content()
            }
        }
    }

    private func tile(_ tile: Tile, name: String, @ViewBuilder badge: () -> some View) -> some View {
        let isSelected = selection.contains(tile)
        return Button {
            if isSelecting {
                if isSelected { selection.remove(tile) } else { selection.insert(tile) }
            } else {
                open(tile)
            }
        } label: {
            VStack(spacing: 8) {
                badge()
                    .overlay(alignment: .topTrailing) {
                        if isSelecting {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                .background(Circle().fill(Color(.systemBackground)))
                                .offset(x: 6, y: -6)
                        }
                    }
                Text(name)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
            .contentShape(.rect)
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
