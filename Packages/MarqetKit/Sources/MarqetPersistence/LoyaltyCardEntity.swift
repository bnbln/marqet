import Foundation
import MarqetCore
import SwiftData

/// A customer card (KONZEPT #42). CloudKit-compatible like the other entities.
@Model
public final class LoyaltyCardEntity {
    public var id: UUID = UUID()
    public var name: String = ""
    public var payload: String = ""
    public var symbologyRaw: String = BarcodeSymbology.code128.rawValue
    public var colorHex: String = DetectedStoreFactory.neutralColorHex
    public var storeIDs: [UUID] = []
    public var createdAt: Date = Date.now

    public init(_ card: LoyaltyCard) {
        id = card.id
        createdAt = card.createdAt
        update(from: card)
    }

    public func update(from card: LoyaltyCard) {
        name = card.name
        payload = card.payload
        symbologyRaw = card.symbology.rawValue
        colorHex = card.colorHex
        storeIDs = card.storeIDs
    }

    public var card: LoyaltyCard {
        LoyaltyCard(
            id: id,
            name: name,
            payload: payload,
            symbology: BarcodeSymbology(rawValue: symbologyRaw) ?? .code128,
            colorHex: colorHex,
            storeIDs: storeIDs,
            createdAt: createdAt
        )
    }
}

/// Reads and writes customer cards. Values in, values out.
@MainActor
public final class LoyaltyCardRepository {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    /// All cards, oldest first. Duplicate IDs (possible after a CloudKit merge) collapse to one.
    public func all() throws -> [LoyaltyCard] {
        var seen = Set<UUID>()
        return try context.fetch(FetchDescriptor<LoyaltyCardEntity>(sortBy: [SortDescriptor(\.createdAt)]))
            .filter { seen.insert($0.id).inserted }
            .map(\.card)
    }

    /// Inserts or updates by ID.
    public func save(_ card: LoyaltyCard) throws {
        let id = card.id
        if let existing = try context.fetch(FetchDescriptor<LoyaltyCardEntity>(predicate: #Predicate { $0.id == id })).first {
            existing.update(from: card)
        } else {
            context.insert(LoyaltyCardEntity(card))
        }
        try context.save()
    }

    public func delete(id: UUID) throws {
        try context.delete(model: LoyaltyCardEntity.self, where: #Predicate { $0.id == id })
        try context.save()
    }
}
