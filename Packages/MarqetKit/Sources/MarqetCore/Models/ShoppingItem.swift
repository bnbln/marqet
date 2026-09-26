import Foundation

/// One entry of the shopping list. Backed 1:1 by an `EKReminder`.
public struct ShoppingItem: Identifiable, Hashable, Sendable {
    /// `EKReminder.calendarItemIdentifier`
    public let id: String
    public var title: String
    /// Reminder notes without the Marqet marker line.
    public var userNotes: String?
    /// `nil` means unsorted.
    public var storeRef: StoreRef?
    public var isCompleted: Bool
    public var completionDate: Date?
    public var creationDate: Date?

    public init(
        id: String,
        title: String,
        userNotes: String? = nil,
        storeRef: StoreRef? = nil,
        isCompleted: Bool = false,
        completionDate: Date? = nil,
        creationDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.userNotes = userNotes
        self.storeRef = storeRef
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.creationDate = creationDate
    }

    public var storeID: Store.ID? {
        if case .known(let id) = storeRef { id } else { nil }
    }

    public var unresolvedStoreName: String? {
        if case .unresolved(let name) = storeRef { name } else { nil }
    }
}

public enum StoreRef: Hashable, Sendable {
    case known(Store.ID)
    /// Marker names a store Marqet does not know yet – resolved by auto-creating a `.detected` store.
    case unresolved(name: String)
}
