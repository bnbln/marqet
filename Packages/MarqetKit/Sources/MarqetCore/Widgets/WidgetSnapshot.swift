import Foundation

/// Everything widgets, controls and the Live Activity show (KONZEPT-WIDGETS §9.2).
///
/// Written by the app after every change and rebuilt by the widget extension from Reminders,
/// both through `WidgetSnapshotBuilder` – so the numbers on the Home Screen are the app's numbers.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case ready
        /// No Reminders access, no list or onboarding not finished – widgets ask to open Marqet.
        case needsSetup
    }

    /// Why a store card is on screen – mirrors `StoreCardState`.
    public enum CardState: String, Codable, Sendable {
        case active, planned, shoppedEmpty, clearedEmpty

        init(_ state: StoreCardState) {
            switch state {
            case .active: self = .active
            case .planned: self = .planned
            case .shoppedEmpty: self = .shoppedEmpty
            case .clearedEmpty: self = .clearedEmpty
            }
        }
    }

    public struct Item: Codable, Sendable, Hashable, Identifiable {
        /// `EKReminder.calendarItemIdentifier`
        public let id: String
        public var title: String
        public var note: String?
        public var category: ItemCategory?
        /// Learned store for an inbox item ("→ Rewe"), tap to assign.
        public var suggestion: Suggestion?
        public var storeID: Store.ID?
        public var completedAt: Date?

        public init(id: String, title: String, note: String? = nil, category: ItemCategory? = nil,
                    suggestion: Suggestion? = nil, storeID: Store.ID? = nil, completedAt: Date? = nil) {
            self.id = id
            self.title = title
            self.note = note
            self.category = category
            self.suggestion = suggestion
            self.storeID = storeID
            self.completedAt = completedAt
        }
    }

    public struct Suggestion: Codable, Sendable, Hashable {
        public let storeID: Store.ID
        public let storeName: String
        public let colorHex: String

        public init(storeID: Store.ID, storeName: String, colorHex: String) {
            self.storeID = storeID
            self.storeName = storeName
            self.colorHex = colorHex
        }
    }

    public struct Section: Codable, Sendable, Hashable, Identifiable {
        /// `nil`: flat list (inbox, non-grocery stores).
        public let category: ItemCategory?
        public let items: [Item]

        public var id: String { category?.rawValue ?? "all" }

        public init(category: ItemCategory?, items: [Item]) {
            self.category = category
            self.items = items
        }
    }

    /// One card: the inbox (`store == nil`) or a store.
    public struct Page: Codable, Sendable, Hashable, Identifiable {
        /// `PageID.rawValue`
        public let id: String
        public let store: Store?
        public let state: CardState?
        public let sections: [Section]
        /// Straight-line distance to the store's relevant branch, if location is known.
        public let distanceMeters: Double?

        public init(id: String, store: Store?, state: CardState?, sections: [Section], distanceMeters: Double? = nil) {
            self.id = id
            self.store = store
            self.state = state
            self.sections = sections
            self.distanceMeters = distanceMeters
        }

        public var pageID: PageID? { PageID(rawValue: id) }
        public var isInbox: Bool { store == nil }
        /// Items in walking order (sections flattened).
        public var items: [Item] { sections.flatMap(\.items) }
        public var openCount: Int { sections.reduce(0) { $0 + $1.items.count } }

        /// An empty page for a store that has no card right now (hidden) – widgets still show it.
        public static func empty(for store: Store) -> Page {
            Page(id: PageID.store(store.id).rawValue, store: store, state: nil, sections: [])
        }
    }

    /// A retailer's official leaflet (Angebote card).
    public struct Brochure: Codable, Sendable, Hashable, Identifiable {
        public let key: String
        public let name: String
        public let colorHex: String
        public let symbol: StoreSymbol
        public let url: URL
        /// The user's store of this chain, if added.
        public var storeID: Store.ID?
        public var openCount: Int
        public var distanceMeters: Double?

        public var id: String { key }

        public init(key: String, name: String, colorHex: String, symbol: StoreSymbol, url: URL,
                    storeID: Store.ID? = nil, openCount: Int = 0, distanceMeters: Double? = nil) {
            self.key = key
            self.name = name
            self.colorHex = colorHex
            self.symbol = symbol
            self.url = url
            self.storeID = storeID
            self.openCount = openCount
            self.distanceMeters = distanceMeters
        }

        /// A store value for badges and colors (catalog chains carry their logo by key).
        public var store: Store {
            Store(id: storeID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, catalogKey: key, name: name,
                  colorHex: colorHex, symbol: symbol, sortIndex: 0, origin: .catalog, type: .supermarket)
        }
    }

    public var generatedAt: Date
    public var status: Status
    public var listTitle: String
    /// Inbox first, then the store cards in card order (manual, distance or smart).
    public var pages: [Page]
    /// Every store in manual order, including hidden ones – for configuration.
    public var stores: [Store]
    /// Checked off in the last 7 days, newest first ("Nochmal kaufen").
    public var recentlyCompleted: [Item]
    public var loyaltyCards: [LoyaltyCard]
    public var brochures: [Brochure]
    public var trip: ShoppingTrip?
    /// The app's accent color (Einstellungen › Erscheinungsbild) for neutral elements.
    public var accentHex: String

    public static let defaultAccentHex = "#238A5D"

    public init(
        generatedAt: Date = .now,
        status: Status,
        listTitle: String,
        pages: [Page] = [],
        stores: [Store] = [],
        recentlyCompleted: [Item] = [],
        loyaltyCards: [LoyaltyCard] = [],
        brochures: [Brochure] = [],
        trip: ShoppingTrip? = nil,
        accentHex: String = WidgetSnapshot.defaultAccentHex
    ) {
        self.generatedAt = generatedAt
        self.status = status
        self.listTitle = listTitle
        self.pages = pages
        self.stores = stores
        self.recentlyCompleted = recentlyCompleted
        self.loyaltyCards = loyaltyCards
        self.brochures = brochures
        self.trip = trip
        self.accentHex = accentHex
    }

    /// Shown until the app wrote its first snapshot.
    public static let empty = WidgetSnapshot(status: .needsSetup, listTitle: "")
}

// MARK: - Queries used by widgets, controls and the Live Activity

extension WidgetSnapshot {
    public var inbox: Page? { pages.first(where: \.isInbox) }
    public var storePages: [Page] { pages.filter { !$0.isInbox } }
    /// Store cards with open items, in card order.
    public var activeStorePages: [Page] { storePages.filter { $0.openCount > 0 } }

    public var totalOpenCount: Int { pages.reduce(0) { $0 + $1.openCount } }
    public var storeOpenCount: Int { storePages.reduce(0) { $0 + $1.openCount } }

    public func store(_ id: Store.ID) -> Store? {
        stores.first { $0.id == id }
    }

    /// The card of a store – visible or not (hidden stores get an empty page).
    public func page(forStore id: Store.ID) -> Page? {
        if let page = storePages.first(where: { $0.store?.id == id }) { return page }
        return store(id).map(Page.empty(for:))
    }

    public func page(for pageID: PageID) -> Page? {
        switch pageID {
        case .unsorted: inbox
        case .store(let id): page(forStore: id)
        case .brochures, .more: nil
        }
    }

    /// "Nächster Laden": the running trip's store while it has items, else the first store card
    /// with items (card order already reflects distance or smart sorting), else the inbox with items,
    /// else the first planned store, else the inbox.
    public var automaticPage: Page? {
        if let trip, let page = page(forStore: trip.storeID), page.openCount > 0 { return page }
        if let first = activeStorePages.first { return first }
        if let inbox, inbox.openCount > 0 { return inbox }
        if let planned = storePages.first(where: { $0.state == .planned }) { return planned }
        return inbox
    }

    /// Store cards with items after `storeID`, in card order – the rest of the shopping round.
    public func nextStops(after storeID: Store.ID?, limit: Int = 3) -> [Page] {
        Array(activeStorePages.filter { $0.store?.id != storeID }.prefix(limit))
    }

    public func loyaltyCards(for storeID: Store.ID) -> [LoyaltyCard] {
        loyaltyCards.cards(for: storeID)
    }

    /// "Automatisch": the card of the trip's store, else of the next store, else the first card.
    public var automaticLoyaltyCard: LoyaltyCard? {
        let candidates = [trip?.storeID] + activeStorePages.map(\.store?.id) + storePages.map(\.store?.id)
        for id in candidates.compactMap({ $0 }) {
            if let card = loyaltyCards(for: id).first { return card }
        }
        return loyaltyCards.sorted { $0.createdAt < $1.createdAt }.first
    }

    public func loyaltyCard(_ id: LoyaltyCard.ID) -> LoyaltyCard? {
        loyaltyCards.first { $0.id == id }
    }
}
