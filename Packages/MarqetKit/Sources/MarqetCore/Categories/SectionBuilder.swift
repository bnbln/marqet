import Foundation

/// One category section inside a store card. `category == nil` means a flat, unsectioned list.
public struct CardSection: Identifiable, Hashable, Sendable {
    public let category: ItemCategory?
    public let items: [ShoppingItem]

    public var id: String { category?.rawValue ?? "all" }
}

/// Learned or manual position of a category or an item inside one store (KONZEPT §6.4).
public struct OrderPosition: Hashable, Sendable, Codable {
    /// 0 = entrance, 1 = checkout.
    public var value: Double
    public var samples: Int
    public var isManual: Bool

    public init(value: Double, samples: Int = 0, isManual: Bool = false) {
        self.value = value
        self.samples = samples
        self.isManual = isManual
    }
}

/// Groups a card's items into category sections in walking order (KONZEPT §6.3, §6.4).
public enum SectionBuilder {
    public struct Ordering: Sendable {
        /// Category positions for this store (manual or learned). Missing categories use the default order.
        public var categoryPositions: [ItemCategory: OrderPosition]
        /// Item positions (matching keys) – only with route learning (Pro). `nil` sorts alphabetically.
        public var itemPositions: [String: OrderPosition]?

        public init(categoryPositions: [ItemCategory: OrderPosition] = [:], itemPositions: [String: OrderPosition]? = nil) {
            self.categoryPositions = categoryPositions
            self.itemPositions = itemPositions
        }
    }

    public static func sections(
        items: [ShoppingItem],
        storeType: StoreType?,
        category: (ShoppingItem) -> ItemCategory,
        ordering: Ordering = Ordering()
    ) -> [CardSection] {
        guard !items.isEmpty else { return [] }
        // Unsorted card and non-grocery stores (drugstore, hardware …): one flat list, oldest first.
        guard let storeType, storeType.showsCategorySections else {
            return [CardSection(category: nil, items: items)]
        }

        var grouped: [ItemCategory: [ShoppingItem]] = [:]
        for item in items { grouped[category(item), default: []].append(item) }

        return categoryOrder(ordering.categoryPositions)
            .compactMap { category in
                grouped[category].map { CardSection(category: category, items: sortedItems($0, ordering.itemPositions)) }
            }
    }

    /// Categories sorted by position; categories without a position keep their default slot.
    public static func categoryOrder(_ positions: [ItemCategory: OrderPosition]) -> [ItemCategory] {
        let defaults = ItemCategory.defaultOrder
        let count = Double(max(defaults.count - 1, 1))
        func position(_ category: ItemCategory) -> Double {
            if let known = positions[category] { return known.value }
            return Double(defaults.firstIndex(of: category) ?? 0) / count
        }
        return defaults.enumerated()
            .sorted { lhs, rhs in
                let (l, r) = (position(lhs.element), position(rhs.element))
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    /// With positions: unknown items first (so their place gets learned), then by position.
    /// Without: alphabetical.
    static func sortedItems(_ items: [ShoppingItem], _ positions: [String: OrderPosition]?) -> [ShoppingItem] {
        guard let positions else {
            return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        return items.sorted { lhs, rhs in
            let l = positions[ItemKeyNormalizer.matchingKey(for: lhs.title)]?.value
            let r = positions[ItemKeyNormalizer.matchingKey(for: rhs.title)]?.value
            switch (l, r) {
            case (nil, nil): return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            case (nil, _): return true
            case (_, nil): return false
            case let (l?, r?): return l == r ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending : l < r
            }
        }
    }
}
