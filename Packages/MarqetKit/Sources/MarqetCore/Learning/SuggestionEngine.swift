import Foundation

/// A proposed store for an unsorted item (KONZEPT §6.1).
public struct StoreSuggestion: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        /// Same item assigned before.
        case learned
        /// Similar item assigned before ("Bio-Milch" ~ "Milch").
        case similar
        /// Apple Intelligence (Pro).
        case intelligence
        /// Category → store type heuristic (Pro fallback without Apple Intelligence).
        case storeType
        /// Cheapest of the user's stores by Open Prices (docs/OFFENE-DATEN.md §4).
        case price
    }

    public enum Confidence: Int, Comparable, Sendable {
        case low, medium, high
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let storeID: Store.ID
    public let source: Source
    public let confidence: Confidence

    public init(storeID: Store.ID, source: Source, confidence: Confidence) {
        self.storeID = storeID
        self.source = source
        self.confidence = confidence
    }

    /// Only high-confidence memory may assign without asking (Pro auto-assign).
    public var allowsAutoAssign: Bool { source == .learned && confidence == .high }
}

/// "Milch → Aldi (5×)": counts of past assignments per item key (KONZEPT §6.1).
public struct AssignmentMemory: Sendable, Equatable {
    public private(set) var counts: [String: [Store.ID: Int]]

    public init(counts: [String: [Store.ID: Int]] = [:]) {
        self.counts = counts
    }

    public mutating func record(itemKey: String, storeID: Store.ID) {
        guard !itemKey.isEmpty else { return }
        counts[itemKey, default: [:]][storeID, default: 0] += 1
    }

    /// An undone auto-assignment counts against that store.
    public mutating func penalize(itemKey: String, storeID: Store.ID) {
        guard let count = counts[itemKey]?[storeID] else { return }
        counts[itemKey]?[storeID] = count > 1 ? count - 1 : nil
        if counts[itemKey]?.isEmpty == true { counts[itemKey] = nil }
    }

    public mutating func forget(storeID: Store.ID) {
        for key in counts.keys { counts[key]?[storeID] = nil }
        counts = counts.filter { !$0.value.isEmpty }
    }
}

public enum SuggestionEngine {
    public static let autoAssignMinimumCount = 2
    public static let autoAssignMinimumShare = 0.8

    /// Memory-based suggestion (Free and Pro). `validStores` filters out deleted stores.
    public static func suggestion(for title: String, memory: AssignmentMemory, validStores: Set<Store.ID>) -> StoreSuggestion? {
        let key = ItemKeyNormalizer.matchingKey(for: title)
        guard !key.isEmpty else { return nil }

        if let exact = memory.counts[key], let best = best(exact, valid: validStores) {
            let total = exact.filter { validStores.contains($0.key) }.values.reduce(0, +)
            let share = Double(best.count) / Double(max(total, 1))
            let isHigh = best.count >= autoAssignMinimumCount && share >= autoAssignMinimumShare
            return StoreSuggestion(storeID: best.id, source: .learned, confidence: isHigh ? .high : .medium)
        }

        // Similar: a remembered key appears as a whole word or compound part of this item.
        let tokens = key.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        var merged: [Store.ID: Int] = [:]
        for (memoryKey, stores) in memory.counts where memoryKey.count >= 3 {
            let matches = tokens.contains { $0 == memoryKey || ($0.count > memoryKey.count && $0.hasSuffix(memoryKey)) }
                || key.hasPrefix(memoryKey + " ")
            guard matches else { continue }
            for (id, count) in stores { merged[id, default: 0] += count }
        }
        if let best = best(merged, valid: validStores) {
            return StoreSuggestion(storeID: best.id, source: .similar, confidence: .medium)
        }
        return nil
    }

    /// Pro fallback: the category tells the kind of store ("Zahnpasta" → drugstore).
    /// Picks the user's first store of a fitting type; groceries go to supermarkets/discounters.
    public static func storeTypeSuggestion(for category: ItemCategory, stores: [Store]) -> StoreSuggestion? {
        let ordered = stores.sorted { $0.sortIndex < $1.sortIndex }
        for type in preferredStoreTypes(for: category) {
            if let store = ordered.first(where: { $0.type == type }) {
                return StoreSuggestion(storeID: store.id, source: .storeType, confidence: .low)
            }
        }
        return nil
    }

    /// Kinds of store that usually carry a category, best fit first.
    public static func preferredStoreTypes(for category: ItemCategory) -> [StoreType] {
        switch category {
        case .personalCare, .baby: [.drugstore, .pharmacy, .supermarket, .discounter]
        case .household: [.drugstore, .supermarket, .discounter]
        case .pet: [.supermarket, .discounter, .drugstore]
        case .bakery: [.bakery, .supermarket, .discounter]
        case .meat: [.butcher, .supermarket, .discounter]
        case .produce: [.market, .supermarket, .discounter, .organic]
        case .alcohol, .beverages: [.beverage, .supermarket, .discounter]
        case .other: []
        default: [.supermarket, .discounter, .organic]
        }
    }

    private static func best(_ counts: [Store.ID: Int], valid: Set<Store.ID>) -> (id: Store.ID, count: Int)? {
        counts
            .filter { valid.contains($0.key) }
            .max { $0.value == $1.value ? $0.key.uuidString > $1.key.uuidString : $0.value < $1.value }
            .map { ($0.key, $0.value) }
    }
}
