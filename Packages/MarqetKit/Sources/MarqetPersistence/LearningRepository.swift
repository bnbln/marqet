import Foundation
import MarqetCore
import SwiftData

/// Reads and writes learned categories, assignments and walking orders.
@MainActor
public final class LearningRepository {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Categories

    public func categoryMemory() throws -> [String: (category: ItemCategory, isCorrection: Bool)] {
        var result: [String: (ItemCategory, Bool)] = [:]
        for entity in try context.fetch(FetchDescriptor<CategoryMemoryEntity>(sortBy: [SortDescriptor(\.updatedAt)])) {
            guard let category = ItemCategory(rawValue: entity.categoryRaw) else { continue }
            // Duplicates after a sync: a correction wins, otherwise the newest.
            if let existing = result[entity.itemKey], existing.1, !entity.isUserCorrection { continue }
            result[entity.itemKey] = (category, entity.isUserCorrection)
        }
        return result.mapValues { (category: $0.0, isCorrection: $0.1) }
    }

    /// Learned (non-correction) values never overwrite a user correction.
    public func setCategory(_ category: ItemCategory, for itemKey: String, isUserCorrection: Bool) throws {
        guard !itemKey.isEmpty else { return }
        let existing = try context.fetch(FetchDescriptor<CategoryMemoryEntity>(predicate: #Predicate { $0.itemKey == itemKey }))
        if let entity = existing.first {
            if entity.isUserCorrection, !isUserCorrection { return }
            entity.categoryRaw = category.rawValue
            entity.isUserCorrection = isUserCorrection
            entity.updatedAt = .now
        } else {
            context.insert(CategoryMemoryEntity(itemKey: itemKey, category: category, isUserCorrection: isUserCorrection))
        }
        try context.save()
    }

    // MARK: Assignments

    public func assignmentMemory() throws -> AssignmentMemory {
        var counts: [String: [UUID: Int]] = [:]
        for entity in try context.fetch(FetchDescriptor<AssignmentMemoryEntity>()) where entity.count > 0 {
            counts[entity.itemKey, default: [:]][entity.storeID, default: 0] += entity.count
        }
        return AssignmentMemory(counts: counts)
    }

    public func recordAssignment(itemKey: String, storeID: UUID) throws {
        try adjustAssignment(itemKey: itemKey, storeID: storeID, by: 1)
    }

    public func penalizeAssignment(itemKey: String, storeID: UUID) throws {
        try adjustAssignment(itemKey: itemKey, storeID: storeID, by: -1)
    }

    private func adjustAssignment(itemKey: String, storeID: UUID, by delta: Int) throws {
        guard !itemKey.isEmpty else { return }
        let existing = try context.fetch(FetchDescriptor<AssignmentMemoryEntity>(
            predicate: #Predicate { $0.itemKey == itemKey && $0.storeID == storeID }
        ))
        if let entity = existing.first {
            entity.count = max(entity.count + delta, 0)
            entity.lastAssignedAt = .now
            if entity.count == 0 { context.delete(entity) }
        } else if delta > 0 {
            context.insert(AssignmentMemoryEntity(itemKey: itemKey, storeID: storeID, count: delta))
        }
        try context.save()
    }

    // MARK: Walking order

    public func categoryPositions(storeID: UUID) throws -> [ItemCategory: OrderPosition] {
        var result: [ItemCategory: OrderPosition] = [:]
        for entity in try orders(storeID: storeID, kind: .category) {
            if let category = ItemCategory(rawValue: entity.key) { result[category] = entity.position }
        }
        return result
    }

    public func itemPositions(storeID: UUID) throws -> [String: OrderPosition] {
        Dictionary(try orders(storeID: storeID, kind: .item).map { ($0.key, $0.position) }, uniquingKeysWith: { first, _ in first })
    }

    public func saveCategoryPositions(_ positions: [ItemCategory: OrderPosition], storeID: UUID) throws {
        try replaceOrders(storeID: storeID, kind: .category, with: Dictionary(uniqueKeysWithValues: positions.map { ($0.key.rawValue, $0.value) }))
    }

    public func saveItemPositions(_ positions: [String: OrderPosition], storeID: UUID) throws {
        try replaceOrders(storeID: storeID, kind: .item, with: positions)
    }

    private func orders(storeID: UUID, kind: OrderEntity.Kind) throws -> [OrderEntity] {
        let raw = kind.rawValue
        return try context.fetch(FetchDescriptor<OrderEntity>(predicate: #Predicate { $0.storeID == storeID && $0.kindRaw == raw }))
    }

    private func replaceOrders(storeID: UUID, kind: OrderEntity.Kind, with positions: [String: OrderPosition]) throws {
        for entity in try orders(storeID: storeID, kind: kind) { context.delete(entity) }
        for (key, position) in positions {
            context.insert(OrderEntity(storeID: storeID, kind: kind, key: key, position: position))
        }
        try context.save()
    }

    // MARK: Maintenance

    /// A deleted store takes its assignments and walking order with it.
    public func forget(storeID: UUID) throws {
        try context.delete(model: AssignmentMemoryEntity.self, where: #Predicate { $0.storeID == storeID })
        try context.delete(model: OrderEntity.self, where: #Predicate { $0.storeID == storeID })
        try context.save()
    }

    /// "Gelerntes zurücksetzen": assignments and learned orders go; corrections and manual orders stay.
    public func resetLearning() throws {
        try context.delete(model: AssignmentMemoryEntity.self)
        try context.delete(model: OrderEntity.self, where: #Predicate { !$0.isManual })
        try context.delete(model: CategoryMemoryEntity.self, where: #Predicate { !$0.isUserCorrection })
        try context.save()
    }
}
