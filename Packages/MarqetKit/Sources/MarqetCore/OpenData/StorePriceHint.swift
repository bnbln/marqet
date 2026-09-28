import Foundation

/// Open Prices for one list item, mapped onto the user's stores (docs/OFFENE-DATEN.md §4).
///
/// Only catalog chains have prices; custom stores and generic kinds ("Markt") never do.
public struct StorePriceHint: Hashable, Sendable {
    public let categoryTag: String
    public let category: PriceIndex.Category
    public let unit: PriceIndex.Unit
    /// Prices of the user's stores, cheapest first.
    public let storePrices: [StorePrice]

    public struct StorePrice: Hashable, Sendable {
        public let storeID: Store.ID
        public let price: PriceIndex.ChainPrice
    }

    /// Observations a chain needs before its price may steer a suggestion.
    public static let minimumReliableCount = 2
    /// How much cheaper (share) the cheapest store must be to replace a weaker suggestion.
    public static let minimumSavingsShare = 0.05

    public init?(match: PriceIndex.Match, stores: [Store]) {
        var seen = Set<Store.ID>()
        var ranked: [(sortIndex: Int, price: StorePrice)] = []
        for price in match.prices {
            for store in stores where store.catalogKey == price.store && seen.insert(store.id).inserted {
                ranked.append((store.sortIndex, StorePrice(storeID: store.id, price: price)))
            }
        }
        // Equal prices: the user's own store order decides, not the chain's name.
        ranked.sort { lhs, rhs in
            let (l, r) = (lhs.price.price.typical, rhs.price.price.typical)
            return l != r ? l < r : lhs.sortIndex < rhs.sortIndex
        }
        let prices = ranked.map(\.price)
        guard !prices.isEmpty else { return nil }
        categoryTag = match.categoryTag
        category = match.category
        unit = match.unit
        storePrices = prices
    }

    public init?(title: String, stores: [Store], index: PriceIndex?, region: StoreCatalog.Region) {
        guard let match = index?.match(for: title, region: region) else { return nil }
        self.init(match: match, stores: stores)
    }

    public func price(of storeID: Store.ID) -> PriceIndex.ChainPrice? {
        storePrices.first { $0.storeID == storeID }?.price
    }

    /// Stores taking part in the comparison: those with enough observations as soon as two such
    /// stores exist, so a single price-tag photo does not beat a well-known price.
    private var comparable: [StorePrice] {
        let reliable = storePrices.filter { $0.price.count >= Self.minimumReliableCount }
        return reliable.count >= 2 ? reliable : storePrices
    }

    /// The cheapest store – only when at least two of the user's stores can be compared.
    public var cheapest: StorePrice? {
        let comparable = comparable
        return comparable.count >= 2 ? comparable.first : nil
    }

    /// Whether the cheapest price is backed by enough observations to steer a suggestion.
    public var isReliable: Bool {
        let comparable = comparable
        return comparable.count >= 2 && comparable.prefix(2).allSatisfy { $0.price.count >= Self.minimumReliableCount }
    }

    /// Whether `storeID` is as cheap as the cheapest store (ties share the tag).
    public func isCheapest(_ storeID: Store.ID) -> Bool {
        guard let cheapest, let entry = comparable.first(where: { $0.storeID == storeID }) else { return false }
        return entry.price.typical <= cheapest.price.typical
    }

    /// Share saved at the cheapest store compared with `storeID` (0.1 = 10 % cheaper);
    /// `nil` if the store has no price.
    public func savingsShare(comparedTo storeID: Store.ID) -> Double? {
        guard let cheapest, let other = price(of: storeID), other.typical > 0 else { return nil }
        return (other.typical - cheapest.price.typical) / other.typical
    }
}

extension SuggestionEngine {
    /// Lets the cheapest store steer the suggestion (docs/OFFENE-DATEN.md §4).
    ///
    /// - A confident habit (`allowsAutoAssign`) always stays: people shop where they shop.
    /// - Without any other suggestion, the cheapest store is suggested.
    /// - A weaker suggestion (similar item, Apple Intelligence, store type, a habit that is not
    ///   yet clear) gives way when the cheapest store is at least 5 % cheaper than the suggested
    ///   one, or when only the store-type guess stood against it.
    /// Prices never assign by themselves: a price suggestion never allows auto-assign.
    public static func applyingPrice(_ suggestion: StoreSuggestion?, hint: StorePriceHint?) -> StoreSuggestion? {
        guard let hint, let cheapest = hint.cheapest else { return suggestion }
        let priceSuggestion = StoreSuggestion(
            storeID: cheapest.storeID,
            source: .price,
            confidence: hint.isReliable ? .medium : .low
        )
        guard let suggestion else { return priceSuggestion }
        if suggestion.allowsAutoAssign || suggestion.storeID == cheapest.storeID { return suggestion }
        guard hint.isReliable else { return suggestion }
        if let savings = hint.savingsShare(comparedTo: suggestion.storeID) {
            return savings >= StorePriceHint.minimumSavingsShare ? priceSuggestion : suggestion
        }
        return suggestion.source == .storeType ? priceSuggestion : suggestion
    }
}
