import Foundation

/// What the widget extension needs to rebuild the snapshot from Reminders on its own
/// (KONZEPT-WIDGETS §9.2): stores, card order, walking order and what Marqet learned.
/// The app writes it whenever one of these changes.
public struct WidgetRegistry: Codable, Sendable, Equatable {
    /// A chain with an official leaflet in the user's region.
    public struct BrochureSource: Codable, Sendable, Equatable {
        public let key: String
        public let name: String
        public let colorHex: String
        public let symbol: StoreSymbol
        public let url: URL
        /// Nearest branch found on the map, if known.
        public var distanceMeters: Double?

        public init(key: String, name: String, colorHex: String, symbol: StoreSymbol, url: URL, distanceMeters: Double? = nil) {
            self.key = key
            self.name = name
            self.colorHex = colorHex
            self.symbol = symbol
            self.url = url
            self.distanceMeters = distanceMeters
        }
    }

    public var status: WidgetSnapshot.Status
    public var listID: String?
    public var listTitle: String
    public var stores: [Store]
    /// Card order for distance/smart; `nil` = manual order.
    public var storeOrder: [Store.ID]?
    public var emptiedInSession: [Store.ID]
    /// Store ID → category raw value → position (string keys keep the JSON small and readable).
    public var categoryPositions: [String: [String: OrderPosition]]
    /// Store ID → item key → position. Only with Pro route learning, like in the app.
    public var itemPositions: [String: [String: OrderPosition]]?
    /// Item key → category the user or Apple Intelligence chose.
    public var learnedCategories: [String: ItemCategory]
    /// Item key → store ID → how often it was assigned there (AssignmentMemory).
    public var assignmentCounts: [String: [String: Int]]
    public var loyaltyCards: [LoyaltyCard]
    public var brochureSources: [BrochureSource]
    /// Store ID → relevant branch.
    public var branchCoordinates: [String: GeoPoint]
    public var userLocation: GeoPoint?
    /// The store the user is at, from the geofences or the last position fix.
    public var presence: StorePresence?
    public var accentHex: String

    public init(
        status: WidgetSnapshot.Status,
        listID: String? = nil,
        listTitle: String = "",
        stores: [Store] = [],
        storeOrder: [Store.ID]? = nil,
        emptiedInSession: [Store.ID] = [],
        categoryPositions: [String: [String: OrderPosition]] = [:],
        itemPositions: [String: [String: OrderPosition]]? = nil,
        learnedCategories: [String: ItemCategory] = [:],
        assignmentCounts: [String: [String: Int]] = [:],
        loyaltyCards: [LoyaltyCard] = [],
        brochureSources: [BrochureSource] = [],
        branchCoordinates: [String: GeoPoint] = [:],
        userLocation: GeoPoint? = nil,
        presence: StorePresence? = nil,
        accentHex: String = WidgetSnapshot.defaultAccentHex
    ) {
        self.status = status
        self.listID = listID
        self.listTitle = listTitle
        self.stores = stores
        self.storeOrder = storeOrder
        self.emptiedInSession = emptiedInSession
        self.categoryPositions = categoryPositions
        self.itemPositions = itemPositions
        self.learnedCategories = learnedCategories
        self.assignmentCounts = assignmentCounts
        self.loyaltyCards = loyaltyCards
        self.brochureSources = brochureSources
        self.branchCoordinates = branchCoordinates
        self.userLocation = userLocation
        self.presence = presence
        self.accentHex = accentHex
    }

    public var assignmentMemory: AssignmentMemory {
        var counts: [String: [Store.ID: Int]] = [:]
        for (key, stores) in assignmentCounts {
            for (id, count) in stores {
                if let id = UUID(uuidString: id) { counts[key, default: [:]][id] = count }
            }
        }
        return AssignmentMemory(counts: counts)
    }

    public static func encode(assignments memory: AssignmentMemory) -> [String: [String: Int]] {
        memory.counts.mapValues { stores in
            Dictionary(uniqueKeysWithValues: stores.map { ($0.key.uuidString, $0.value) })
        }
    }

    public func ordering(for storeID: Store.ID) -> SectionBuilder.Ordering {
        let categories = categoryPositions[storeID.uuidString] ?? [:]
        var positions: [ItemCategory: OrderPosition] = [:]
        for (raw, position) in categories {
            if let category = ItemCategory(rawValue: raw) { positions[category] = position }
        }
        return SectionBuilder.Ordering(
            categoryPositions: positions,
            itemPositions: itemPositions.map { $0[storeID.uuidString] ?? [:] }
        )
    }

    public static func encode(categoryPositions positions: [ItemCategory: OrderPosition]) -> [String: OrderPosition] {
        Dictionary(uniqueKeysWithValues: positions.map { ($0.key.rawValue, $0.value) })
    }
}

/// Builds the snapshot the same way in the app and in the widget extension (KONZEPT-WIDGETS §9.2).
public enum WidgetSnapshotBuilder {
    /// Enough for the largest widget (XL, three columns); keeps the file and the timeline small.
    public static let maximumItemsPerPage = 40
    public static let maximumCompleted = 30
    public static let maximumBrochures = 12

    public static func snapshot(
        registry: WidgetRegistry,
        items: [ShoppingItem],
        recentlyCompleted: [ShoppingItem],
        classifier: CategoryClassifier,
        trip: ShoppingTrip?,
        now: Date = .now
    ) -> WidgetSnapshot {
        guard registry.status == .ready else {
            return WidgetSnapshot(generatedAt: now, status: .needsSetup, listTitle: registry.listTitle,
                                  stores: registry.stores, loyaltyCards: registry.loyaltyCards, accentHex: registry.accentHex)
        }

        let open = items.filter { !$0.isCompleted }
        let deck = CardBuilder.deck(
            items: open,
            stores: registry.stores,
            context: .init(emptiedInSession: Set(registry.emptiedInSession)),
            storeOrder: registry.storeOrder
        )
        let storesByID = Dictionary(registry.stores.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let memory = registry.assignmentMemory
        let validStores = Set(registry.stores.map(\.id))

        func item(_ item: ShoppingItem, category: ItemCategory?, suggests: Bool) -> WidgetSnapshot.Item {
            var suggestion: WidgetSnapshot.Suggestion?
            if suggests,
               let suggested = SuggestionEngine.suggestion(for: item.title, memory: memory, validStores: validStores),
               let store = storesByID[suggested.storeID] {
                suggestion = WidgetSnapshot.Suggestion(storeID: store.id, storeName: store.name, colorHex: store.colorHex)
            }
            return WidgetSnapshot.Item(
                id: item.id,
                title: item.title,
                note: item.userNotes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                category: category,
                suggestion: suggestion,
                storeID: item.storeID,
                completedAt: item.completionDate
            )
        }

        var pages: [WidgetSnapshot.Page] = []
        for pageID in deck.pages {
            switch pageID {
            case .unsorted:
                let inboxItems = Array(deck.items(on: .unsorted).prefix(maximumItemsPerPage))
                pages.append(WidgetSnapshot.Page(
                    id: pageID.rawValue,
                    store: nil,
                    state: nil,
                    sections: inboxItems.isEmpty ? [] : [.init(category: nil, items: inboxItems.map {
                        item($0, category: nil, suggests: true)
                    })]
                ))
            case .store(let id):
                guard let store = storesByID[id] else { continue }
                let sections = SectionBuilder.sections(
                    items: deck.items(on: pageID),
                    storeType: store.type,
                    category: { classifier.classify($0.title).category },
                    ordering: registry.ordering(for: id)
                )
                var remaining = maximumItemsPerPage
                var trimmed: [WidgetSnapshot.Section] = []
                for section in sections where remaining > 0 {
                    let kept = section.items.prefix(remaining).map { item($0, category: section.category, suggests: false) }
                    remaining -= kept.count
                    trimmed.append(.init(category: section.category, items: kept))
                }
                pages.append(WidgetSnapshot.Page(
                    id: pageID.rawValue,
                    store: store,
                    state: deck.state(of: id).map(WidgetSnapshot.CardState.init),
                    sections: trimmed,
                    distanceMeters: distance(to: id, registry: registry)
                ))
            case .map, .brochures, .more:
                continue
            }
        }

        let completed = recentlyCompleted
            .filter(\.isCompleted)
            .sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
            .prefix(maximumCompleted)
            .map { item($0, category: nil, suggests: false) }

        return WidgetSnapshot(
            generatedAt: now,
            status: .ready,
            listTitle: registry.listTitle,
            pages: pages,
            stores: registry.stores.sorted { $0.sortIndex < $1.sortIndex },
            recentlyCompleted: Array(completed),
            loyaltyCards: registry.loyaltyCards,
            brochures: brochures(registry: registry, pages: pages),
            trip: trip.flatMap { storesByID[$0.storeID] == nil ? nil : $0 },
            presence: registry.presence.flatMap { storesByID[$0.storeID] != nil && $0.isValid(at: now) ? $0 : nil },
            accentHex: registry.accentHex
        )
    }

    static func distance(to storeID: Store.ID, registry: WidgetRegistry) -> Double? {
        guard let user = registry.userLocation, let branch = registry.branchCoordinates[storeID.uuidString] else { return nil }
        return branch.distance(to: user)
    }

    /// Own stores with open items first (most items first), then other own stores, then chains
    /// nearby, then the rest alphabetically.
    static func brochures(registry: WidgetRegistry, pages: [WidgetSnapshot.Page]) -> [WidgetSnapshot.Brochure] {
        let storesByKey = Dictionary(
            registry.stores.compactMap { store in store.catalogKey.map { ($0, store) } },
            uniquingKeysWith: { first, _ in first }
        )
        let counts = Dictionary(pages.compactMap { page in page.store.map { ($0.id, page.openCount) } }, uniquingKeysWith: +)
        let brochures = registry.brochureSources.map { source in
            let store = storesByKey[source.key]
            return WidgetSnapshot.Brochure(
                key: source.key,
                name: source.name,
                colorHex: source.colorHex,
                symbol: source.symbol,
                url: source.url,
                storeID: store?.id,
                openCount: store.flatMap { counts[$0.id] } ?? 0,
                distanceMeters: store.flatMap { distance(to: $0.id, registry: registry) } ?? source.distanceMeters
            )
        }
        func rank(_ brochure: WidgetSnapshot.Brochure) -> Int {
            if brochure.storeID != nil { return brochure.openCount > 0 ? 0 : 1 }
            return brochure.distanceMeters != nil ? 2 : 3
        }
        let sorted = brochures.sorted { lhs, rhs in
            let (l, r) = (rank(lhs), rank(rhs))
            if l != r { return l < r }
            if lhs.openCount != rhs.openCount { return lhs.openCount > rhs.openCount }
            switch (lhs.distanceMeters, rhs.distanceMeters) {
            case let (l?, r?) where l != r: return l < r
            default: return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
        return Array(sorted.prefix(maximumBrochures))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
