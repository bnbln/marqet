import Foundation

/// Why a store card is on screen (KONZEPT §7.2, lifecycle table).
public enum StoreCardState: Hashable, Sendable {
    /// At least one open item.
    case active
    /// Empty, but the user added it on purpose. Stays until shopped there or removed manually.
    case planned
    /// Emptied by checking items off. Stays until the shopping session ends or the user hides it.
    case shoppedEmpty
    /// Emptied by deleting or moving items. Stays only while it is on screen.
    case clearedEmpty
}

/// The pages of the pager plus the items on each page.
public struct CardDeck: Equatable, Sendable {
    public let pages: [PageID]
    public let itemsByPage: [PageID: [ShoppingItem]]
    public let storeStates: [Store.ID: StoreCardState]

    public func items(on page: PageID) -> [ShoppingItem] {
        itemsByPage[page] ?? []
    }

    public func state(of storeID: Store.ID) -> StoreCardState? {
        storeStates[storeID]
    }
}

/// Builds the deck: `[Unsortiert] [Läden …] [Weitere Läden]` with the card lifecycle rules.
public enum CardBuilder {
    public struct Context: Sendable {
        /// Pages that must not disappear: currently on screen, or the target of the open composer.
        public var retainedPages: Set<PageID>
        /// Stores emptied by checking items off during the current shopping session.
        public var emptiedInSession: Set<Store.ID>

        public init(retainedPages: Set<PageID> = [], emptiedInSession: Set<Store.ID> = []) {
            self.retainedPages = retainedPages
            self.emptiedInSession = emptiedInSession
        }
    }

    public static func deck(items: [ShoppingItem], stores: [Store], context: Context = Context()) -> CardDeck {
        let knownIDs = Set(stores.map(\.id))
        var itemsByPage: [PageID: [ShoppingItem]] = [:]
        for item in items {
            let page: PageID = if let id = item.storeID, knownIDs.contains(id) { .store(id) } else { .unsorted }
            itemsByPage[page, default: []].append(item)
        }
        for (page, pageItems) in itemsByPage {
            itemsByPage[page] = sorted(pageItems)
        }

        // Keep the inbox mounted when its first item arrives, including on Duo.
        var pages: [PageID] = [.unsorted]

        var states: [Store.ID: StoreCardState] = [:]
        for store in stores.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            guard let state = state(of: store, hasItems: itemsByPage[.store(store.id)] != nil, context: context) else {
                continue
            }
            states[store.id] = state
            pages.append(.store(store.id))
        }
        pages.append(.more)

        return CardDeck(pages: pages, itemsByPage: itemsByPage, storeStates: states)
    }

    /// `nil` means the store is hidden and listed on the "Weitere Läden" card.
    public static func state(of store: Store, hasItems: Bool, context: Context) -> StoreCardState? {
        if hasItems { return .active }
        if context.emptiedInSession.contains(store.id) { return .shoppedEmpty }
        if store.plannedAt != nil { return .planned }
        if context.retainedPages.contains(.store(store.id)) { return .clearedEmpty }
        return nil
    }

    /// Oldest first, so the list reads in the order things were added.
    private static func sorted(_ items: [ShoppingItem]) -> [ShoppingItem] {
        items.sorted {
            switch ($0.creationDate, $1.creationDate) {
            case let (lhs?, rhs?) where lhs != rhs: lhs < rhs
            case (nil, _?): false
            case (_?, nil): true
            default: $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }
}
