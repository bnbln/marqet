import Foundation

/// Resolves a store name from a marker line to one of the user's stores (KONZEPT §4.2).
///
/// Matching order:
/// 1. Exact match on name or alias (case, diacritics, spaces and punctuation ignored).
/// 2. Unique prefix of at least 3 characters – so "🛒 Aldi" typed by hand in Reminders
///    finds "Aldi Süd" as long as the user has only one Aldi.
public struct StoreMatcher: Sendable {
    private static let minimumPrefixLength = 3

    private let idsByKey: [String: Store.ID]
    private let storesByID: [Store.ID: Store]

    public init(stores: [Store]) {
        var idsByKey: [String: Store.ID] = [:]
        // Names first so they win over another store's alias.
        for store in stores {
            let key = ItemKeyNormalizer.storeNameKey(store.name)
            if !key.isEmpty, idsByKey[key] == nil { idsByKey[key] = store.id }
        }
        for store in stores {
            for alias in store.aliases {
                let key = ItemKeyNormalizer.storeNameKey(alias)
                if !key.isEmpty, idsByKey[key] == nil { idsByKey[key] = store.id }
            }
        }
        self.idsByKey = idsByKey
        self.storesByID = Dictionary(stores.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func store(named name: String) -> Store? {
        let key = ItemKeyNormalizer.storeNameKey(name)
        guard !key.isEmpty else { return nil }
        if let id = idsByKey[key] { return storesByID[id] }

        guard key.count >= Self.minimumPrefixLength else { return nil }
        let candidates = Set(idsByKey.filter { $0.key.hasPrefix(key) }.values)
        guard candidates.count == 1, let id = candidates.first else { return nil }
        return storesByID[id]
    }
}

/// Creates stores for marker names that none of the user's stores match – e.g. stores a
/// household member added on another device (KONZEPT §4.2.3).
///
/// A name matching a catalog chain exactly becomes that chain (brand color, monogram); anything
/// else becomes a neutral `.detected` store.
public enum DetectedStoreFactory {
    public static let neutralColorHex = "#8E8E93"

    public static func makeStores(
        forUnresolved names: [String],
        existing: [Store],
        catalog: [StoreCatalog.Entry] = []
    ) -> [Store] {
        var nextSortIndex = (existing.map(\.sortIndex).max() ?? -1) + 1
        var seenKeys = Set(existing.map { ItemKeyNormalizer.storeNameKey($0.name) })
        var createdCatalogKeys = Set(existing.compactMap(\.catalogKey))
        var created: [Store] = []

        for name in names {
            let key = ItemKeyNormalizer.storeNameKey(name)
            guard !key.isEmpty, seenKeys.insert(key).inserted else { continue }

            if let entry = catalogEntry(exactlyMatching: key, in: catalog) {
                guard createdCatalogKeys.insert(entry.key).inserted else { continue }
                seenKeys.insert(ItemKeyNormalizer.storeNameKey(entry.name))
                created.append(entry.makeStore(sortIndex: nextSortIndex))
            } else {
                created.append(Store(
                    name: name,
                    colorHex: neutralColorHex,
                    symbol: .systemImage("cart.fill"),
                    sortIndex: nextSortIndex,
                    origin: .detected,
                    type: .other
                ))
            }
            nextSortIndex += 1
        }
        return created
    }

    /// Exact name or alias match only – a prefix like "Aldi" must not silently pick Nord or Süd.
    private static func catalogEntry(exactlyMatching key: String, in catalog: [StoreCatalog.Entry]) -> StoreCatalog.Entry? {
        catalog.first { entry in
            ([entry.name] + entry.aliases).contains { ItemKeyNormalizer.storeNameKey($0) == key }
        }
    }
}
