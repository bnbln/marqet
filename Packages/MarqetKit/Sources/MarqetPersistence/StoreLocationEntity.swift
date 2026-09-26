import Foundation
import MarqetCore
import SwiftData

/// A branch of a store (KONZEPT §14.1). CloudKit-compatible like the other entities.
@Model
public final class StoreLocationEntity {
    public var id: UUID = UUID()
    public var storeID: UUID = UUID()
    public var name: String = ""
    public var address: String?
    public var latitude: Double = 0
    public var longitude: Double = 0
    public var mapItemIdentifier: String?
    public var isPreferred: Bool = false
    public var createdAt: Date = Date.now

    public init(_ location: StoreLocation) {
        id = location.id
        update(from: location)
    }

    public func update(from location: StoreLocation) {
        storeID = location.storeID
        name = location.name
        address = location.address
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        mapItemIdentifier = location.mapItemIdentifier
        isPreferred = location.isPreferred
    }

    public var location: StoreLocation {
        StoreLocation(
            id: id,
            storeID: storeID,
            name: name,
            address: address,
            coordinate: GeoPoint(latitude: latitude, longitude: longitude),
            mapItemIdentifier: mapItemIdentifier,
            isPreferred: isPreferred
        )
    }
}

/// Branches per store; at most one preferred branch per store.
@MainActor
public final class LocationRepository {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    public func all() throws -> [StoreLocation] {
        try context.fetch(FetchDescriptor<StoreLocationEntity>(sortBy: [SortDescriptor(\.createdAt)])).map(\.location)
    }

    /// Inserts or updates by ID. A preferred location demotes the store's other branches.
    public func save(_ location: StoreLocation) throws {
        let id = location.id
        let storeID = location.storeID
        if location.isPreferred {
            for other in try context.fetch(FetchDescriptor<StoreLocationEntity>(predicate: #Predicate { $0.storeID == storeID })) where other.id != id {
                other.isPreferred = false
            }
        }
        if let existing = try context.fetch(FetchDescriptor<StoreLocationEntity>(predicate: #Predicate { $0.id == id })).first {
            existing.update(from: location)
        } else {
            context.insert(StoreLocationEntity(location))
        }
        try context.save()
    }

    public func delete(id: UUID) throws {
        try context.delete(model: StoreLocationEntity.self, where: #Predicate { $0.id == id })
        try context.save()
    }

    public func deleteAll(storeID: UUID) throws {
        try context.delete(model: StoreLocationEntity.self, where: #Predicate { $0.storeID == storeID })
        try context.save()
    }
}
