import Foundation

/// A store the user shops at. Rendered as one card in the pager.
///
/// `name` is canonical: it is what Marqet writes into the reminder notes (`🛒 <name>`),
/// so every device – and every household member – resolves the same store.
public struct Store: Identifiable, Hashable, Sendable, Codable {
    public enum Origin: String, Codable, Sendable {
        /// Created from the bundled chain catalog.
        case catalog
        /// Created by the user.
        case custom
        /// Created automatically from a marker Marqet did not know (e.g. from a shared list).
        case detected
    }

    public let id: UUID
    public var catalogKey: String?
    public var name: String
    public var aliases: [String]
    public var colorHex: String
    public var symbol: StoreSymbol
    public var sortIndex: Int
    public var origin: Origin
    public var type: StoreType
    /// Optional branch location shown below the store name.
    public var address: String?
    /// A short personal note, e.g. "Eingang im Hof".
    public var detail: String?
    /// Set when the user explicitly adds the store as a (possibly empty) card.
    public var plannedAt: Date?

    public init(
        id: UUID = UUID(),
        catalogKey: String? = nil,
        name: String,
        aliases: [String] = [],
        colorHex: String,
        symbol: StoreSymbol,
        sortIndex: Int,
        origin: Origin,
        type: StoreType,
        plannedAt: Date? = nil,
        address: String? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.catalogKey = catalogKey
        self.name = name
        self.aliases = aliases
        self.colorHex = colorHex
        self.symbol = symbol
        self.sortIndex = sortIndex
        self.origin = origin
        self.type = type
        self.plannedAt = plannedAt
        self.address = address
        self.detail = detail
    }
}

/// Visual mark of a store. Chains use a monogram (no logos, see KONZEPT §8), generic stores an SF Symbol.
public enum StoreSymbol: Hashable, Sendable, Codable {
    case monogram(String)
    case systemImage(String)
}

public enum StoreType: String, Codable, Sendable, CaseIterable {
    case discounter, supermarket, drugstore, organic, hardware, furniture
    case beverage, bakery, butcher, pharmacy, market, online, other

    /// Grocery-like stores show category sections inside their card (KONZEPT §6.3).
    public var showsCategorySections: Bool {
        switch self {
        case .discounter, .supermarket, .organic, .market: true
        default: false
        }
    }
}
