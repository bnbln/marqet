import Foundation
import MarqetCore

/// A running "Zuordnen" session (KONZEPT §7.4). Survives folding because it lives in the model.
struct TriageSession: Equatable {
    /// `single` = card stack (default), `board` = table; chosen in the settings.
    enum Mode: String, CaseIterable {
        case single, board
    }

    /// One step of the session, for "Rückgängig" and the last-step line.
    enum Step: Equatable {
        case assigned(ShoppingItem.ID, Store.ID)
        case skipped(ShoppingItem.ID)
    }

    /// Items of the current pass, in list order. A second pass holds only the skipped ones.
    var itemIDs: [ShoppingItem.ID]
    var mode: Mode
    var skipped: Set<ShoppingItem.ID> = []
    /// Steps of this session, newest last.
    var history: [Step] = []
    /// How many of the assigned items Pro would have assigned automatically (upsell line).
    var autoAssignable = 0
    /// Catalog chains added by dropping an item on them; undo removes them again while empty.
    var addedStores: Set<Store.ID> = []

    var assignedCount: Int {
        history.count { if case .assigned = $0 { true } else { false } }
    }
}

/// A chain the user does not have yet, filling up the triage grid: cheaper for this item, or a
/// usual store for its kind of product.
struct TriageFiller: Identifiable, Equatable {
    let entry: StoreCatalog.Entry
    /// Preview for badge and colors; only becomes a store when an item is dropped on it.
    let store: Store
    let price: PriceIndex.ChainPrice?
    /// Clearly cheaper than every own store (tag on the tile).
    let isCheaper: Bool

    var id: String { entry.key }
}

/// Pro auto-assignment, shown as a toast with undo.
struct AutoAssignReport: Equatable {
    let assignments: [ShoppingItem.ID: Store.ID]
}

extension AppModel {
    // MARK: Suggestions (KONZEPT §6.1)

    /// Memory first (Free and Pro); Apple Intelligence and the store-type heuristic only with Pro.
    /// Open Prices then may move a weaker suggestion to the cheapest store (Free, docs/OFFENE-DATEN.md §4).
    func suggestion(for item: ShoppingItem) -> StoreSuggestion? {
        SuggestionEngine.applyingPrice(habitOrIntelligenceSuggestion(for: item), hint: priceHint(for: item))
    }

    // MARK: Prices (docs/OFFENE-DATEN.md)

    static let openPricesKey = "openPricesEnabled"

    /// Price fetching is tied to a visible price surface, never to app launch.
    var openPricesEnabled: Bool {
        defaults.object(forKey: Self.openPricesKey) as? Bool ?? true
    }

    var priceArea: PriceUpdateService.Area {
        PriceUpdateService.Area(location: locationAuthorization == .authorized ? userLocation : nil)
    }

    var lastPriceCheck: Date? {
        // `priceUpdates` is not observed; the revision is, so the settings row follows each refresh.
        _ = priceRevision
        let prefix = "\(region.rawValue):\(priceArea.key):"
        return priceUpdates.entries.filter { $0.key.hasPrefix(prefix) }.values.map(\.checkedAt).max()
    }

    var offerPriceFinds: [PriceUpdateService.PriceFind] {
        _ = priceRevision
        guard openPricesEnabled, priceArea.center != nil else { return [] }
        let prefix = "\(region.rawValue):\(priceArea.key):"
        let recent = priceUpdates.entries.filter {
            $0.key.hasPrefix(prefix) && Date().timeIntervalSince($0.value.checkedAt) < PriceFreshness.findsDisplayLimit
        }
        var seen = Set<String>()
        return recent.values.flatMap { $0.finds ?? [] }
            .sorted {
                if $0.kind != $1.kind { return $0.kind == .observedDiscount }
                return $0.date > $1.date
            }
            .filter { seen.insert("\($0.title.lowercased()):\($0.store)").inserted }
            .prefix(6)
            .map { $0 }
    }

    /// Only downloaded observations can produce a hint.
    func priceHint(for item: ShoppingItem) -> StorePriceHint? {
        priceMatch(for: item).flatMap { StorePriceHint(match: $0, stores: stores) }
    }

    /// Prices of every chain for the item's category, not only the user's stores.
    func priceMatch(for item: ShoppingItem) -> PriceIndex.Match? {
        guard openPricesEnabled else { return nil }
        _ = priceRevision
        guard let category = PriceIndex.bundled?.category(for: item.title),
              let rows = displayablePrices(for: category.tag) else { return nil }
        return PriceIndex.bundled?.match(categoryTag: category.tag, rows: rows)
    }

    /// Share a chain must be below the cheapest own store to be offered as "cheaper elsewhere".
    static let fillerSavingsShare = 0.1

    /// Chains to fill up the triage grid, best first: clearly cheaper ones, then usual stores for
    /// the item's kind of product (nearest first when known, else catalog order).
    func triageFillers(for item: ShoppingItem, limit: Int) -> [TriageFiller] {
        guard limit > 0, let catalog else { return [] }
        let ownKeys = Set(stores.compactMap(\.catalogKey))
        let available = catalog.entries(for: region).filter { !ownKeys.contains($0.key) }
        var fillers: [TriageFiller] = []
        var seen = Set<String>()

        if let match = priceMatch(for: item) {
            let reliable = match.prices.filter { $0.count >= StorePriceHint.minimumReliableCount }
            let ownCheapest = priceHint(for: item)?.storePrices.map(\.price.typical).min()
            for price in reliable.sorted(by: { $0.typical < $1.typical }) {
                guard let ownCheapest, price.typical <= ownCheapest * (1 - Self.fillerSavingsShare),
                      let entry = available.first(where: { $0.key == price.store }),
                      seen.insert(entry.key).inserted else { continue }
                fillers.append(TriageFiller(entry: entry, store: entry.makeStore(sortIndex: 0), price: price, isCheaper: true))
            }
        }

        let types = SuggestionEngine.preferredStoreTypes(for: category(of: item))
        let fitting = types.isEmpty ? [.supermarket, .discounter] : types
        let usual = available
            .filter { fitting.contains($0.type) && !seen.contains($0.key) }
            .enumerated()
            .sorted { lhs, rhs in
                let (l, r) = (fitting.firstIndex(of: lhs.element.type) ?? 0, fitting.firstIndex(of: rhs.element.type) ?? 0)
                if l != r { return l < r }
                let (ld, rd) = (nearbyCatalogDistances[lhs.element.key], nearbyCatalogDistances[rhs.element.key])
                switch (ld, rd) {
                case let (ld?, rd?): return ld < rd
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
        let match = priceMatch(for: item)
        for entry in usual {
            let price = match?.prices.first { $0.store == entry.key }
            fillers.append(TriageFiller(entry: entry, store: entry.makeStore(sortIndex: 0), price: price, isCheaper: false))
        }
        return Array(fillers.prefix(limit))
    }

    /// Load categories needed by visible list prices and, when requested, the offers card.
    /// Reopening the surface reuses the local cache for a day.
    func refreshPrices(for visibleItems: [ShoppingItem]? = nil, force: Bool = false,
                       includeOffers: Bool = false) async {
        guard openPricesEnabled,
              let catalog, let index = PriceIndex.bundled else { return }
        var tags = Set((visibleItems ?? unsortedItems).filter { !$0.isCompleted }
            .compactMap { index.category(for: $0.title)?.tag })
        if includeOffers {
            tags.formUnion(["en:bananas", "en:butters", "en:breads", "en:whole-milks",
                            "en:chicken-eggs", "en:apples", "en:pastas"].filter { index.categories[$0] != nil })
        }
        guard !tags.isEmpty else { return }
        if isRefreshingPrices {
            queuedPriceTags.formUnion(tags)
            return
        }
        // Busy before the location fix: that can take seconds, and the settings button shows the spinner.
        isRefreshingPrices = true
        priceRefreshError = nil
        defer { isRefreshingPrices = false }
        if locationAuthorization == .authorized, userLocation == nil {
            userLocation = await locationProvider.currentLocation()
        }
        let area = priceArea
        var failed = false
        while !tags.isEmpty {
            guard let tag = tags.popFirst() else { break }
            guard openPricesEnabled else { break }
            let key = PriceUpdateService.Cache.key(region: region, area: area, tag: tag)
            if !force, let checked = priceUpdates.entries[key]?.checkedAt,
               PriceFreshness.state(checkedAt: checked) == .fresh {
                if tags.isEmpty { tags.formUnion(queuedPriceTags); queuedPriceTags.removeAll() }
                continue
            }
            if !force, let failedAt = failedPriceChecks[key],
               failedAt > Date().addingTimeInterval(-60 * 60) {
                if tags.isEmpty { tags.formUnion(queuedPriceTags); queuedPriceTags.removeAll() }
                continue
            }
            do {
                let name = index.categories[tag]?.name(for: Locale.current.language.languageCode?.identifier) ?? tag
                let result = try await PriceUpdateService.fetch(
                    tag: tag, categoryName: name, region: region, area: area, catalog: catalog
                )
                priceUpdates.entries[key] = .init(checkedAt: Date(), prices: result.prices, finds: result.finds)
                try priceUpdates.save()
                failedPriceChecks.removeValue(forKey: key)
                priceRevision += 1
            } catch {
                if error is CancellationError { break }
                failedPriceChecks[key] = Date()
                failed = true
            }
            if tags.isEmpty { tags.formUnion(queuedPriceTags); queuedPriceTags.removeAll() }
        }
        if failed { priceRefreshError = String(localized: "Einige Preise konnten nicht aktualisiert werden.") }
    }

    private func habitOrIntelligenceSuggestion(for item: ShoppingItem) -> StoreSuggestion? {
        let valid = Set(stores.map(\.id))
        if let memory = SuggestionEngine.suggestion(for: item.title, memory: assignmentMemory, validStores: valid) {
            return memory
        }
        guard isPro, intelligenceEnabled else { return nil }
        if let id = intelligentSuggestions[ItemKeyNormalizer.matchingKey(for: item.title)], valid.contains(id) {
            return StoreSuggestion(storeID: id, source: .intelligence, confidence: .medium)
        }
        return SuggestionEngine.storeTypeSuggestion(for: category(of: item), stores: stores)
    }

    func rememberAssignment(of item: ShoppingItem, to store: Store) {
        let key = ItemKeyNormalizer.matchingKey(for: item.title)
        assignmentMemory.record(itemKey: key, storeID: store.id)
        do {
            try learning.recordAssignment(itemKey: key, storeID: store.id)
        } catch {
            present(error)
        }
    }

    // MARK: After every reload

    /// Pro auto-assignment; the rest waits in the unsorted card (KONZEPT §7.4).
    func afterReload() async {
        guard hasCompletedOnboarding else { return }
        await autoAssignIfPossible()
        await learnMissingCategories()
    }

    // MARK: Session

    func startTriage() {
        let ids = unsortedItems.map(\.id)
        guard !ids.isEmpty else { return }
        dismissBriefing()
        triage = TriageSession(itemIDs: ids, mode: preferredTriageMode)
        Task { await prepareIntelligentSuggestions(for: unsortedItems) }
    }

    /// End of onboarding. Triage never opens by itself – not here, not at launch: the user starts
    /// it from the inbox, the briefing or a widget (KONZEPT #11).
    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func endTriage() {
        triage = nil
    }

    /// Remaining items of the session: still unsorted and not skipped.
    var triageQueue: [ShoppingItem] {
        guard let triage else { return [] }
        let unsorted = Dictionary(uniqueKeysWithValues: unsortedItems.map { ($0.id, $0) })
        return triage.itemIDs.compactMap { unsorted[$0] }.filter { !triage.skipped.contains($0.id) }
    }

    /// "2 von 12" in the current pass.
    var triageProgress: (position: Int, total: Int) {
        let total = triage?.itemIDs.count ?? 0
        return (min(total, total - triageQueue.count + 1), total)
    }

    /// Skipped items that are still unsorted – offered again at the end.
    var triageSkippedItems: [ShoppingItem] {
        guard let triage else { return [] }
        let unsorted = Dictionary(uniqueKeysWithValues: unsortedItems.map { ($0.id, $0) })
        return triage.itemIDs.filter(triage.skipped.contains).compactMap { unsorted[$0] }
    }

    func triageAssign(_ item: ShoppingItem, to store: Store) async {
        if suggestion(for: item)?.allowsAutoAssign == true { triage?.autoAssignable += 1 }
        triage?.history.append(.assigned(item.id, store.id))
        await assign(item, to: store)
    }

    /// Drop on a chain the user does not have yet: it becomes a store, then gets the item.
    func triageAssign(_ item: ShoppingItem, toNew entry: StoreCatalog.Entry) async {
        let isNew = !stores.contains { $0.catalogKey == entry.key }
        let store = addStore(from: entry, planned: false)
        if isNew { triage?.addedStores.insert(store.id) }
        await triageAssign(item, to: store)
    }

    /// Swipe right: the suggested store, otherwise later.
    func triageAcceptSuggestion(for item: ShoppingItem) async {
        if let suggestion = suggestion(for: item), let store = store(suggestion.storeID) {
            await triageAssign(item, to: store)
        } else {
            triageSkip(item)
        }
    }

    func triageSkip(_ item: ShoppingItem) {
        triage?.skipped.insert(item.id)
        triage?.history.append(.skipped(item.id))
    }

    /// Second pass over the skipped items.
    func triageRevisitSkipped() {
        let skippedIDs = triageSkippedItems.map(\.id)
        triage?.itemIDs = skippedIDs
        triage?.skipped = []
    }

    /// Undoes the last step of this session; the item returns to the queue.
    func triageUndo() async {
        switch triage?.history.popLast() {
        case .skipped(let itemID):
            triage?.skipped.remove(itemID)
        case .assigned(let itemID, let storeID):
            guard let item = items.first(where: { $0.id == itemID }) else { return }
            let key = ItemKeyNormalizer.matchingKey(for: item.title)
            assignmentMemory.penalize(itemKey: key, storeID: storeID)
            try? learning.penalizeAssignment(itemKey: key, storeID: storeID)
            await assign(item, to: nil, learn: false)
            // A chain added by this drop leaves again once it is empty.
            if triage?.addedStores.contains(storeID) == true, !items.contains(where: { $0.storeID == storeID }) {
                triage?.addedStores.remove(storeID)
                await deleteStore(storeID)
            }
        case nil:
            break
        }
    }

    /// Items of the queue that have a suggestion right now.
    var triageSuggestions: [(item: ShoppingItem, store: Store)] {
        triageQueue.compactMap { item in
            guard let suggestion = suggestion(for: item), let store = store(suggestion.storeID) else { return nil }
            return (item, store)
        }
    }

    func triageAcceptAllSuggestions() async {
        for (item, store) in triageSuggestions {
            await triageAssign(item, to: store)
        }
    }

    // MARK: Auto-assign (Pro)

    func autoAssignIfPossible() async {
        guard isPro, autoAssignEnabled else { return }
        var assignments: [ShoppingItem.ID: Store.ID] = [:]
        for item in unsortedItems {
            guard let suggestion = suggestion(for: item), suggestion.allowsAutoAssign,
                  let store = store(suggestion.storeID) else { continue }
            assignments[item.id] = store.id
            await assign(item, to: store, learn: false)
        }
        if !assignments.isEmpty {
            autoAssignReport = AutoAssignReport(assignments: assignments)
        }
    }

    /// "Rückgängig" on the toast: back to unsorted, and the memory learns it was wrong.
    func undoAutoAssign() async {
        guard let report = autoAssignReport else { return }
        autoAssignReport = nil
        for (itemID, storeID) in report.assignments {
            guard let item = items.first(where: { $0.id == itemID }) else { continue }
            let key = ItemKeyNormalizer.matchingKey(for: item.title)
            assignmentMemory.penalize(itemKey: key, storeID: storeID)
            try? learning.penalizeAssignment(itemKey: key, storeID: storeID)
            await assign(item, to: nil, learn: false)
        }
    }
}
