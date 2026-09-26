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

/// Schema version 1 – the first released model (PLAN B6). Every later model change adds a new
/// `VersionedSchema` and a stage in `MarqetMigrationPlan`, never an unversioned edit.
public enum MarqetSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [StoreEntity.self, CategoryMemoryEntity.self, AssignmentMemoryEntity.self, OrderEntity.self, StoreLocationEntity.self]
    }
}

public enum MarqetMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [MarqetSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

/// One container for everything Marqet stores itself.
public enum PersistenceContainer {
    /// `url` is for tests only; the app uses the default location in Application Support.
    public static func make(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: MarqetSchemaV1.self)
        let configuration = if let url {
            ModelConfiguration("Marqet", schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            ModelConfiguration("Marqet", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        return try ModelContainer(
            for: Schema(versionedSchema: MarqetSchemaV1.self),
            migrationPlan: MarqetMigrationPlan.self,
            configurations: configuration
        )
    }
}
