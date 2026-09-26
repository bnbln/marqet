import Foundation

/// Sendable value copy of an `EKReminder`. `EKReminder` itself never leaves the gateway actor.
public struct ReminderSnapshot: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var notes: String?
    public var isCompleted: Bool
    public var completionDate: Date?
    public var creationDate: Date?
    public var lastModifiedDate: Date?

    public init(
        id: String,
        title: String,
        notes: String? = nil,
        isCompleted: Bool = false,
        completionDate: Date? = nil,
        creationDate: Date? = nil,
        lastModifiedDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.creationDate = creationDate
        self.lastModifiedDate = lastModifiedDate
    }
}

/// A Reminders list (`EKCalendar` of type reminder).
public struct ReminderList: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var colorHex: String?
    public var sourceTitle: String
    public var allowsModifications: Bool

    public init(id: String, title: String, colorHex: String? = nil, sourceTitle: String, allowsModifications: Bool = true) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
        self.sourceTitle = sourceTitle
        self.allowsModifications = allowsModifications
    }
}

public enum ShoppingItemMapper {
    public static func item(from snapshot: ReminderSnapshot, matcher: StoreMatcher) -> ShoppingItem {
        let parsed = StoreMarker.parse(snapshot.notes)
        let storeRef: StoreRef? = parsed.storeName.map { name in
            matcher.store(named: name).map { .known($0.id) } ?? .unresolved(name: name)
        }
        return ShoppingItem(
            id: snapshot.id,
            title: snapshot.title,
            userNotes: parsed.userNotes,
            storeRef: storeRef,
            isCompleted: snapshot.isCompleted,
            completionDate: snapshot.completionDate,
            creationDate: snapshot.creationDate
        )
    }
}

/// Picks likely shopping lists for the list picker (KONZEPT §7.5).
public enum ShoppingListHeuristics {
    private static let keywords = [
        "einkauf", "einkaeufe", "lebensmittel", "supermarkt", "besorgungen",
        "shopping", "groceries", "grocery",
    ]

    public static func isLikelyShoppingList(_ title: String) -> Bool {
        let folded = ItemKeyNormalizer.fold(title)
        return keywords.contains { folded.contains($0) }
    }
}
