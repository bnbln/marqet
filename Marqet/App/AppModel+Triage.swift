import Foundation
import MarqetCore

/// A running "Zuordnen" session (KONZEPT §7.4). Survives folding because it lives in the model.
struct TriageSession: Equatable {
    /// `single` = "Nacheinander", `board` = "Übersicht" (raw values stay for the stored preference).
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

    var assignedCount: Int {
        history.count { if case .assigned = $0 { true } else { false } }
    }
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
        let prefix = "\(region.rawValue):\(priceArea.key):"
        return priceUpdates.entries.filter { $0.key.hasPrefix(prefix) }.values.map(\.checkedAt).max()
    }

    var offerPriceFinds: [PriceUpdateService.PriceFind] {
        _ = priceRevision
        guard openPricesEnabled, priceArea.center != nil else { return [] }
        let prefix = "\(region.rawValue):\(priceArea.key):"
        let recent = priceUpdates.entries.filter {
            $0.key.hasPrefix(prefix) && $0.value.checkedAt > Date().addingTimeInterval(-2 * 24 * 60 * 60)
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
        guard openPricesEnabled else { return nil }
        _ = priceRevision
        guard let category = PriceIndex.bundled?.category(for: item.title) else { return nil }
        let key = PriceUpdateService.Cache.key(region: region, area: priceArea, tag: category.tag)
        guard let update = priceUpdates.entries[key],
              update.checkedAt > Date().addingTimeInterval(-7 * 24 * 60 * 60),
              let match = PriceIndex.bundled?.match(categoryTag: category.tag, rows: update.prices) else { return nil }
        return StorePriceHint(match: match, stores: stores)
    }

    /// Load categories needed by visible list prices and, when requested, the offers card.
    /// Reopening the surface reuses the local cache for a day.
    func refreshPrices(for visibleItems: [ShoppingItem]? = nil, force: Bool = false,
                       includeOffers: Bool = false) async {
        guard openPricesEnabled,
              let catalog, let index = PriceIndex.bundled else { return }
        if locationAuthorization == .authorized, userLocation == nil {
            userLocation = await locationProvider.currentLocation()
        }
        let area = priceArea
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
        isRefreshingPrices = true
        priceRefreshError = nil
        defer { isRefreshingPrices = false }
        var failed = false
        while !tags.isEmpty {
            guard let tag = tags.popFirst() else { break }
            guard openPricesEnabled else { break }
            let key = PriceUpdateService.Cache.key(region: region, area: area, tag: tag)
            if !force, let checked = priceUpdates.entries[key]?.checkedAt,
               checked > Date().addingTimeInterval(-24 * 60 * 60) {
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

    /// Switching in the triage toolbar also becomes the start mode next time.
    func setTriageMode(_ mode: TriageSession.Mode) {
        triage?.mode = mode
        preferredTriageMode = mode
    }

    func triageAssign(_ item: ShoppingItem, to store: Store) async {
        if suggestion(for: item)?.allowsAutoAssign == true { triage?.autoAssignable += 1 }
        triage?.history.append(.assigned(item.id, store.id))
        await assign(item, to: store)
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
