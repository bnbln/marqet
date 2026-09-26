import Foundation
import MarqetCore
import SwiftData

// Learned data (KONZEPT §5.2). Keyed by the normalized item title, never by reminder ID.
// CloudKit-compatible like `StoreEntity`: defaults everywhere, no unique constraints.

/// "Milch → Milchprodukte", from a user correction or Apple Intelligence.
@Model
public final class CategoryMemoryEntity {
    public var itemKey: String = ""
    public var categoryRaw: String = ItemCategory.other.rawValue
    public var isUserCorrection: Bool = false
    public var updatedAt: Date = Date.now

    public init(itemKey: String, category: ItemCategory, isUserCorrection: Bool) {
        self.itemKey = itemKey
        self.categoryRaw = category.rawValue
        self.isUserCorrection = isUserCorrection
    }
}

/// "Milch → Aldi Süd (5×)".
@Model
public final class AssignmentMemoryEntity {
    public var itemKey: String = ""
    public var storeID: UUID = UUID()
    public var count: Int = 0
    public var lastAssignedAt: Date = Date.now

    public init(itemKey: String, storeID: UUID, count: Int) {
        self.itemKey = itemKey
        self.storeID = storeID
        self.count = count
    }
}

/// Position of a category or an item inside one store (walking order).
@Model
public final class OrderEntity {
    public enum Kind: String { case category, item }

    public var storeID: UUID = UUID()
    public var kindRaw: String = Kind.category.rawValue
    public var key: String = ""
    public var value: Double = 0
    public var samples: Int = 0
    public var isManual: Bool = false

    public init(storeID: UUID, kind: Kind, key: String, position: OrderPosition) {
        self.storeID = storeID
        self.kindRaw = kind.rawValue
        self.key = key
        self.value = position.value
        self.samples = position.samples
        self.isManual = position.isManual
    }

    var position: OrderPosition {
        OrderPosition(value: value, samples: samples, isManual: isManual)
    }
}

/// One container for everything Marqet stores itself.
public enum PersistenceContainer {
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Marqet",
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: StoreEntity.self, CategoryMemoryEntity.self, AssignmentMemoryEntity.self, OrderEntity.self,
            configurations: configuration
        )
    }
}
