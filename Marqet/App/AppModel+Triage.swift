import Foundation
import MarqetCore

/// A running "Zuordnen" session (KONZEPT §7.4). Survives folding because it lives in the model.
struct TriageSession: Equatable {
    enum Mode: String, CaseIterable {
        case single, board
    }

    /// Items the session started with, in list order.
    let itemIDs: [ShoppingItem.ID]
    var mode: Mode
    var skipped: Set<ShoppingItem.ID> = []
    /// Assignments made in this session, newest last – for "Rückgängig".
    var history: [(itemID: ShoppingItem.ID, storeID: Store.ID)] = []
    /// How many of the assigned items Pro would have assigned automatically (upsell line).
    var autoAssignable = 0
    /// Board mode: items selected for tap-to-assign.
    var selection: Set<ShoppingItem.ID> = []

    static func == (lhs: TriageSession, rhs: TriageSession) -> Bool {
        lhs.itemIDs == rhs.itemIDs && lhs.mode == rhs.mode && lhs.skipped == rhs.skipped
            && lhs.history.map(\.itemID) == rhs.history.map(\.itemID) && lhs.selection == rhs.selection
    }
}

/// Pro auto-assignment, shown as a toast with undo.
struct AutoAssignReport: Equatable {
    let assignments: [ShoppingItem.ID: Store.ID]
}

extension AppModel {
    // MARK: Suggestions (KONZEPT §6.1)

    /// Memory first (Free and Pro); Apple Intelligence and the store-type heuristic only with Pro.
    func suggestion(for item: ShoppingItem) -> StoreSuggestion? {
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
        triage = TriageSession(itemIDs: ids, mode: preferredTriageMode)
        Task { await prepareIntelligentSuggestions(for: unsortedItems) }
    }

    /// End of onboarding: existing unsorted items go straight into triage (KONZEPT §7.4).
    func completeOnboarding() {
        hasCompletedOnboarding = true
        startTriage()
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

    func triageAssign(_ item: ShoppingItem, to store: Store) async {
        if suggestion(for: item)?.allowsAutoAssign == true { triage?.autoAssignable += 1 }
        triage?.history.append((item.id, store.id))
        triage?.selection.remove(item.id)
        await assign(item, to: store)
    }

    func triageAssignSelection(to store: Store) async {
        guard let selection = triage?.selection else { return }
        for item in triageQueue where selection.contains(item.id) {
            await triageAssign(item, to: store)
        }
    }

    func triageSkip(_ item: ShoppingItem) {
        triage?.skipped.insert(item.id)
    }

    /// Undoes the last assignment of this session; the item returns to the queue.
    func triageUndo() async {
        guard let last = triage?.history.popLast(), let item = items.first(where: { $0.id == last.itemID }) else { return }
        let key = ItemKeyNormalizer.matchingKey(for: item.title)
        assignmentMemory.penalize(itemKey: key, storeID: last.storeID)
        try? learning.penalizeAssignment(itemKey: key, storeID: last.storeID)
        await assign(item, to: nil, learn: false)
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
