import Foundation
import MarqetCore
import SwiftData

/// Reads and writes the user's stores. Values in, values out – `StoreEntity` stays inside.
@MainActor
public final class StoreRepository {
    // The context does not keep its container alive – hold it, or the context dangles.
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    /// On-disk store for the app, or an in-memory one for tests and previews.
    /// CloudKit sync is off until the app has an iCloud container (needs the developer team).
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try PersistenceContainer.make(inMemory: inMemory)
    }

    public static func inMemory() -> StoreRepository {
        // An in-memory container only fails on a broken model definition – a programmer error.
        StoreRepository(container: try! makeContainer(inMemory: true))
    }

    /// All stores in the user's order. Duplicate IDs (possible after a CloudKit merge) collapse to one.
    public func all() throws -> [Store] {
        let descriptor = FetchDescriptor<StoreEntity>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)])
        var seen = Set<UUID>()
        return try context.fetch(descriptor)
            .filter { seen.insert($0.id).inserted }
            .map(\.store)
    }

    /// Inserts or updates by ID.
    public func save(_ stores: [Store]) throws {
        guard !stores.isEmpty else { return }
        let ids = stores.map(\.id)
        let existing = try context.fetch(FetchDescriptor<StoreEntity>(predicate: #Predicate { ids.contains($0.id) }))
        let entitiesByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for store in stores {
            if let entity = entitiesByID[store.id] {
                entity.update(from: store)
            } else {
                context.insert(StoreEntity(store))
            }
        }
        try context.save()
    }

    public func save(_ store: Store) throws {
        try save([store])
    }

    public func delete(id: UUID) throws {
        try context.delete(model: StoreEntity.self, where: #Predicate { $0.id == id })
        try context.save()
    }
}
