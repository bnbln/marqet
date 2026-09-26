import Foundation
import MarqetCore
import SwiftData

/// Persisted store configuration (KONZEPT §5.2).
///
/// Kept CloudKit-compatible for the planned private-database sync: every attribute has a default
/// or is optional, and there are no unique constraints (duplicates are resolved in code).
@Model
public final class StoreEntity {
    public var id: UUID = UUID()
    public var catalogKey: String?
    public var name: String = ""
    public var aliases: [String] = []
    public var colorHex: String = DetectedStoreFactory.neutralColorHex
    public var monogram: String?
    public var systemImage: String?
    public var sortIndex: Int = 0
    public var originRaw: String = Store.Origin.custom.rawValue
    public var typeRaw: String = StoreType.other.rawValue
    public var plannedAt: Date?
    public var createdAt: Date = Date.now

    public init(_ store: Store) {
        id = store.id
        update(from: store)
    }

    public func update(from store: Store) {
        catalogKey = store.catalogKey
        name = store.name
        aliases = store.aliases
        colorHex = store.colorHex
        switch store.symbol {
        case .monogram(let text):
            monogram = text
            systemImage = nil
        case .systemImage(let name):
            monogram = nil
            systemImage = name
        }
        sortIndex = store.sortIndex
        originRaw = store.origin.rawValue
        typeRaw = store.type.rawValue
        plannedAt = store.plannedAt
    }

    public var store: Store {
        Store(
            id: id,
            catalogKey: catalogKey,
            name: name,
            aliases: aliases,
            colorHex: colorHex,
            symbol: monogram.map(StoreSymbol.monogram) ?? .systemImage(systemImage ?? "cart.fill"),
            sortIndex: sortIndex,
            origin: Store.Origin(rawValue: originRaw) ?? .custom,
            type: StoreType(rawValue: typeRaw) ?? .other,
            plannedAt: plannedAt
        )
    }
}
