import Foundation
import MarqetCore

/// Store management: add, pin, unpin, rename, reorder, delete (KONZEPT §4.4, §7.2, §7.6).
extension AppModel {
    var hiddenStores: [Store] {
        let deck = deck
        return sortedStores.filter { deck.state(of: $0.id) == nil }
    }

    /// Catalog chains of the current region the user has not added yet.
    var catalogSuggestions: [StoreCatalog.Entry] {
        let ownKeys = Set(stores.compactMap(\.catalogKey))
        return (catalog?.entries(for: region) ?? []).filter { !ownKeys.contains($0.key) }
    }

    /// Adds a catalog chain as a planned card. Returns the (possibly already existing) store.
    @discardableResult
    func addStore(from entry: StoreCatalog.Entry, planned: Bool = true) -> Store {
        if let existing = stores.first(where: { $0.catalogKey == entry.key }) {
            if planned { pin(existing.id) }
            return existing
        }
        var store = entry.makeStore(sortIndex: nextSortIndex)
        store.plannedAt = planned ? .now : nil
        stores.append(store)
        persist(store)
        return store
    }

    @discardableResult
    func addCustomStore(name: String, type: StoreType, colorHex: String, systemImage: String) -> Store? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let existing = stores.first(where: { ItemKeyNormalizer.storeNameKey($0.name) == ItemKeyNormalizer.storeNameKey(name) }) {
            pin(existing.id)
            return existing
        }
        let store = Store(
            name: String(name.prefix(StoreMarker.maxNameLength)),
            colorHex: colorHex,
            symbol: .systemImage(systemImage),
            sortIndex: nextSortIndex,
            origin: .custom,
            type: type,
            plannedAt: .now
        )
        stores.append(store)
        persist(store)
        return store
    }

    func isNameTaken(_ name: String, except id: Store.ID? = nil) -> Bool {
        let key = ItemKeyNormalizer.storeNameKey(name)
        return !key.isEmpty && stores.contains { $0.id != id && ItemKeyNormalizer.storeNameKey($0.name) == key }
    }

    /// "Anheften": keeps the store's card on screen even without items, until shopped there or
    /// "Lösen" (KONZEPT §7.2). Pinned = `Store.plannedAt` is set.
    func pin(_ id: Store.ID) {
        guard let index = stores.firstIndex(where: { $0.id == id }), stores[index].plannedAt == nil else { return }
        recordStoresUndo()
        stores[index].plannedAt = .now
        persist(stores[index])
    }

    /// "Lösen" / "Ausblenden": the card goes back to "Weitere Läden". The store stays one of
    /// "Meine Läden" with its branches and loyalty cards – only `deleteStore` removes it.
    func unpin(_ id: Store.ID) {
        recordStoresUndo()
        let page = PageID.store(id)
        let oldIndex = deck.pages.firstIndex(of: page) ?? 0
        emptiedInSession.remove(id)
        dismissedPages.insert(page)
        if let index = stores.firstIndex(where: { $0.id == id }) {
            stores[index].plannedAt = nil
            persist(stores[index])
        }
        // Continue with the card that slides into the freed place.
        if activePage == page {
            let pages = deck.pages
            activePage = pages[min(oldIndex, pages.count - 1)]
            pageRequest = activePage
        }
    }

    func isPinned(_ id: Store.ID) -> Bool {
        store(id)?.plannedAt != nil
    }

    /// The "Angeheftet" switch in the store settings.
    func setPinned(_ pinned: Bool, for id: Store.ID) {
        if pinned { pin(id) } else { unpin(id) }
    }

    /// Color, symbol and type. Renaming goes through `rename(_:to:)` because of the markers.
    func updateAppearance(of id: Store.ID, colorHex: String, systemImage: String?, type: StoreType) {
        guard let index = stores.firstIndex(where: { $0.id == id }) else { return }
        recordStoresUndo()
        stores[index].colorHex = colorHex
        if let systemImage { stores[index].symbol = .systemImage(systemImage) }
        stores[index].type = type
        persist(stores[index])
    }

    func updateDetails(of id: Store.ID, address: String, detail: String) {
        guard let index = stores.firstIndex(where: { $0.id == id }) else { return }
        recordStoresUndo()
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        stores[index].address = address.isEmpty ? nil : address
        stores[index].detail = detail.isEmpty ? nil : detail
        persist(stores[index])
        placeManualAddress(address, for: id)
    }

    /// Renames a store and rewrites the markers of its open items. The old name stays as an
    /// alias, so devices of household members that still write it keep matching (KONZEPT §4.4).
    func rename(storeID id: Store.ID, to newName: String) async {
        let newName = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(StoreMarker.maxNameLength))
        guard !newName.isEmpty, let index = stores.firstIndex(where: { $0.id == id }), stores[index].name != newName,
              !isNameTaken(newName, except: id) else { return }
        recordStoresUndo()
        let oldName = stores[index].name
        stores[index].name = newName
        if !stores[index].aliases.contains(oldName) { stores[index].aliases.append(oldName) }
        persist(stores[index])

        for item in items where item.storeID == id {
            await perform { try await $0.setStore(named: newName, forReminder: item.id) }
        }
    }

    /// Applies a drag-and-drop reorder from the store settings.
    /// Reordering by hand means "my order": distance or smart sorting would otherwise keep the
    /// cards where they were, and the move would not show on Home.
    func moveStores(from source: IndexSet, to destination: Int) {
        recordStoresUndo()
        if storeSortMode != .manual {
            storeSortMode = .manual
            storeOrderSnapshot = nil
        }
        var ordered = sortedStores
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, store) in ordered.enumerated() {
            guard let position = stores.firstIndex(where: { $0.id == store.id }), stores[position].sortIndex != index else { continue }
            stores[position].sortIndex = index
            persist(stores[position])
        }
    }

    func openItemCount(of id: Store.ID) -> Int {
        items.filter { $0.storeID == id && !$0.isCompleted }.count
    }

    /// Deletes a store: its open items become unsorted, its learned data is forgotten (KONZEPT §4.4).
    func deleteStore(_ id: Store.ID) async {
        let affected = items.filter { $0.storeID == id }
        stores.removeAll { $0.id == id }
        emptiedInSession.remove(id)
        assignmentMemory.forget(storeID: id)
        categoryPositions[id] = nil
        itemPositions[id] = nil
        if activePage == .store(id) { activePage = .unsorted }
        do {
            try storeRepository.delete(id: id)
            try learning.forget(storeID: id)
            try locationRepository.deleteAll(storeID: id)
            locations.removeAll { $0.storeID == id }
            detachLoyaltyCards(from: id)
        } catch {
            present(error)
        }
        for item in affected {
            update(item.id) { $0.storeRef = nil }
            await perform { try await $0.setStore(named: nil, forReminder: item.id) }
        }
    }
}

extension AppModel {
    /// Stores picked in onboarding, in tap order. Planned, so their cards show right away –
    /// otherwise the first screen after onboarding is an empty inbox without the chosen stores.
    func addOnboardingStores(_ keys: [String]) {
        for key in keys {
            guard let entry = catalog?.entry(forKey: key) else { continue }
            addStore(from: entry, planned: true)
        }
    }
}
