import Foundation
import MarqetCore
import MarqetPersistence
import SwiftData
import Testing

/// Stores written before the versioned schema (builds up to M6) must open without data loss –
/// otherwise the app falls back to an in-memory store and the user's own stores disappear.
@Suite("Migration")
@MainActor
struct MigrationTests {
    @Test func unversionedStoreOpensWithSchemaV1() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "marqet-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Marqet.store")
        let storeID = UUID()

        do {
            // The pre-V1 layout: four entities, no StoreLocationEntity, no version.
            let legacy = Schema([StoreEntity.self, CategoryMemoryEntity.self, AssignmentMemoryEntity.self, OrderEntity.self])
            let container = try ModelContainer(for: legacy, configurations: ModelConfiguration("Marqet", schema: legacy, url: url, cloudKitDatabase: .none))
            try StoreRepository(container: container).save(Store(id: storeID, name: "Hofladen", colorHex: "#336699", symbol: .monogram("H"), sortIndex: 0, origin: .custom, type: .other))
        }

        let container = try PersistenceContainer.make(url: url)
        #expect(try StoreRepository(container: container).all().map(\.id) == [storeID])
        #expect(try LocationRepository(container: container).all().isEmpty)
    }

    @Test func schemaV1StoreOpensWithCustomerCards() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "marqet-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Marqet.store")
        let storeID = UUID()

        do {
            let v1 = Schema(versionedSchema: MarqetSchemaV1.self)
            let container = try ModelContainer(for: v1, configurations: ModelConfiguration("Marqet", schema: v1, url: url, cloudKitDatabase: .none))
            try StoreRepository(container: container).save(Store(id: storeID, name: "Rewe", colorHex: "#CC071E", symbol: .monogram("R"), sortIndex: 0, origin: .catalog, type: .supermarket))
        }

        let container = try PersistenceContainer.make(url: url)
        #expect(try StoreRepository(container: container).all().map(\.id) == [storeID])
        let cards = LoyaltyCardRepository(container: container)
        let card = LoyaltyCard(name: "Payback", payload: "4006381333931", symbology: .ean13, colorHex: "#003EAA", storeIDs: [storeID])
        try cards.save(card)
        #expect(try cards.all() == [card])
    }
}
