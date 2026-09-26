import Foundation
import MarqetCore

/// Pro intelligence: Apple Intelligence suggestions and categories, walking-order learning (KONZEPT §6).
extension AppModel {
    var isIntelligenceAvailable: Bool {
        intelligence.isAvailable
    }

    /// Asks Apple Intelligence for stores of items memory does not know (Pro, batch, on-device).
    func prepareIntelligentSuggestions(for candidates: [ShoppingItem]) async {
        guard isPro, intelligenceEnabled, intelligence.isAvailable, !stores.isEmpty else { return }
        let valid = Set(stores.map(\.id))
        let unknown = candidates.filter {
            SuggestionEngine.suggestion(for: $0.title, memory: assignmentMemory, validStores: valid) == nil
                && intelligentSuggestions[ItemKeyNormalizer.matchingKey(for: $0.title)] == nil
        }
        guard !unknown.isEmpty else { return }
        do {
            let answers = try await intelligence.suggestStores(
                for: unknown.map(\.title),
                stores: sortedStores.map { IntelligenceStore(name: $0.name, kind: $0.type.displayName) }
            )
            let matcher = StoreMatcher(stores: stores)
            for (title, storeName) in answers {
                guard let store = matcher.store(named: storeName) else { continue }
                intelligentSuggestions[ItemKeyNormalizer.matchingKey(for: title)] = store.id
            }
        } catch {
            // Suggestions are a bonus; the store-type heuristic covers failures silently.
        }
    }

    /// Items the dictionary cannot place get a category from Apple Intelligence (Pro).
    func learnMissingCategories() async {
        guard isPro, intelligenceEnabled, intelligence.isAvailable else { return }
        let unknown = Array(Set(items.filter { classifier.classify($0.title).source == .fallback }.map(\.title)))
        guard !unknown.isEmpty else { return }
        do {
            for (title, category) in try await intelligence.categorize(unknown) where category != .other {
                learnCategory(category, forKey: ItemKeyNormalizer.matchingKey(for: title))
            }
        } catch {
            // Items simply stay in "Sonstiges".
        }
    }

    // MARK: Walking order (KONZEPT §6.4)

    /// Recorded for everyone, applied only with Pro: after upgrading, the order is already there.
    func recordCheckOff(of item: ShoppingItem, in storeID: Store.ID) {
        let checkOff = CheckOff(
            storeID: storeID,
            itemKey: ItemKeyNormalizer.matchingKey(for: item.title),
            category: category(of: item),
            date: .now
        )
        let finished = sessionTracker.record(checkOff)
        saveSessionTracker()
        finished.forEach(learnRoute(from:))
    }

    func finishExpiredRouteSessions() {
        let finished = sessionTracker.flushExpired(now: .now)
        guard !finished.isEmpty else { return }
        saveSessionTracker()
        finished.forEach(learnRoute(from:))
    }

    private func learnRoute(from session: [CheckOff]) {
        guard let storeID = session.first?.storeID, store(storeID) != nil else { return }
        let categories = RouteLearner.learn(RouteLearner.categorySequence(of: session), into: categoryPositionsLoaded(for: storeID))
        let itemOrder = RouteLearner.learn(session.map(\.itemKey), into: itemPositionsLoaded(for: storeID))
        categoryPositions[storeID] = categories
        itemPositions[storeID] = itemOrder
        orderRevision += 1
        do {
            try learning.saveCategoryPositions(categories, storeID: storeID)
            try learning.saveItemPositions(itemOrder, storeID: storeID)
        } catch {
            present(error)
        }
    }

    /// "Gelerntes zurücksetzen" – corrections and manual section orders stay.
    func resetLearning() {
        do {
            try learning.resetLearning()
            assignmentMemory = try learning.assignmentMemory()
            classifier.learned = try learning.categoryMemory()
        } catch {
            present(error)
        }
        categoryPositions = [:]
        itemPositions = [:]
        intelligentSuggestions = [:]
        sessionTracker = ShoppingSessionTracker()
        saveSessionTracker()
        orderRevision += 1
    }
}
