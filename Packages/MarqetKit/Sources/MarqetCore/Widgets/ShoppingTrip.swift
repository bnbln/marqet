import Foundation

/// A running shopping trip – the Live Activity "Einkauf" (KONZEPT-WIDGETS §5).
///
/// The store is part of the trip's state, not fixed: the trip follows the user from store to store.
public struct ShoppingTrip: Codable, Sendable, Hashable, Identifiable {
    /// Without checking anything off for this long, the trip is over (same as the shopping session).
    public static let timeout: TimeInterval = 30 * 60

    public let id: UUID
    /// The store the user is shopping at now.
    public var storeID: Store.ID
    public var startedAt: Date
    /// When the current store became the trip's store – progress counts from here.
    public var storeStartedAt: Date
    public var lastActivity: Date
    /// Items checked off at the current store during this trip.
    public var doneItemIDs: [String]
    /// When the user got to the current store; `nil` while still on the way (KONZEPT-WIDGETS §13).
    public var arrivedAt: Date?

    /// - Parameter arrived: `false` when the trip starts before the store is reached – the Live
    ///   Activity then says "Unterwegs zu …" and reports the arrival.
    public init(id: UUID = UUID(), storeID: Store.ID, startedAt: Date = .now, arrived: Bool = true) {
        self.id = id
        self.storeID = storeID
        self.startedAt = startedAt
        self.storeStartedAt = startedAt
        self.lastActivity = startedAt
        self.doneItemIDs = []
        self.arrivedAt = arrived ? startedAt : nil
    }

    public var isOnTheWay: Bool { arrivedAt == nil }

    public func isExpired(at date: Date) -> Bool {
        date.timeIntervalSince(lastActivity) > Self.timeout
    }

    /// When the trip counts as stale (shown dimmed by the system, ended on the next app launch).
    public var staleDate: Date { lastActivity.addingTimeInterval(Self.timeout) }

    /// An item was checked off. Checking off in another store moves the trip there –
    /// whoever checks things off is standing in that store.
    public mutating func recordCompletion(of itemID: String, in storeID: Store.ID, at date: Date = .now) {
        if storeID != self.storeID { moveTo(storeID, at: date) }
        if !doneItemIDs.contains(itemID) { doneItemIDs.append(itemID) }
        if arrivedAt == nil { arrivedAt = date }
        lastActivity = date
    }

    /// The geofence reported the arrival: the trip is at this store now.
    public mutating func arrive(at storeID: Store.ID, at date: Date = .now) {
        if storeID != self.storeID { moveTo(storeID, at: date) }
        if arrivedAt == nil { arrivedAt = date }
        lastActivity = date
    }

    /// Undo within the undo window, or "Nochmal kaufen".
    public mutating func recordReopening(of itemID: String) {
        doneItemIDs.removeAll { $0 == itemID }
    }

    /// - Parameter arrived: `false` for "Weiter zu dm" – the user still has to get there.
    public mutating func moveTo(_ storeID: Store.ID, at date: Date = .now, arrived: Bool = true) {
        guard storeID != self.storeID else { return }
        self.storeID = storeID
        storeStartedAt = date
        lastActivity = date
        doneItemIDs = []
        arrivedAt = arrived ? date : nil
    }
}

/// The Live Activity's dynamic state (ActivityKit `ContentState`, < 4 KB). Built from the snapshot
/// by `TripStatus.make`, so the lock screen shows exactly what the store card shows.
public struct TripStatus: Codable, Sendable, Hashable {
    public struct Line: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let title: String
        public let note: String?

        public init(id: String, title: String, note: String? = nil) {
            self.id = id
            self.title = title
            self.note = note
        }
    }

    /// Another store with open items – where the round goes next.
    public struct Stop: Codable, Sendable, Hashable, Identifiable {
        public let storeID: Store.ID
        public let name: String
        public let colorHex: String
        public let count: Int

        public var id: Store.ID { storeID }

        public init(storeID: Store.ID, name: String, colorHex: String, count: Int) {
            self.storeID = storeID
            self.name = name
            self.colorHex = colorHex
            self.count = count
        }
    }

    /// Trimmed copy of the store (no aliases or address – the payload is small).
    public var store: Store
    /// The next items in walking order.
    public var next: [Line]
    public var openCount: Int
    public var doneCount: Int
    public var stops: [Stop]
    public var hasLoyaltyCard: Bool
    /// "Unterwegs zu Aldi Süd": the trip started before the store was reached.
    public var isOnTheWay: Bool
    /// To the store's branch, if the position is known.
    public var distanceMeters: Double?

    public init(store: Store, next: [Line], openCount: Int, doneCount: Int, stops: [Stop], hasLoyaltyCard: Bool,
                isOnTheWay: Bool = false, distanceMeters: Double? = nil) {
        self.store = store
        self.next = next
        self.openCount = openCount
        self.doneCount = doneCount
        self.stops = stops
        self.hasLoyaltyCard = hasLoyaltyCard
        self.isOnTheWay = isOnTheWay
        self.distanceMeters = distanceMeters
    }

    public var totalCount: Int { openCount + doneCount }
    /// 0…1 for progress bars and rings.
    public var progress: Double { totalCount == 0 ? 1 : Double(doneCount) / Double(totalCount) }
    /// Nothing left here – the Live Activity offers the next store or says it is done.
    public var isStoreDone: Bool { openCount == 0 }
    /// Nothing left anywhere.
    public var isFinished: Bool { openCount == 0 && stops.isEmpty }

    public static let maximumLines = 4

    /// `nil` when the trip's store no longer exists.
    public static func make(snapshot: WidgetSnapshot, trip: ShoppingTrip) -> TripStatus? {
        guard let page = snapshot.page(forStore: trip.storeID), var store = page.store else { return nil }
        store.aliases = []
        store.address = nil
        store.detail = nil
        let stops = snapshot.nextStops(after: store.id).compactMap { page -> Stop? in
            guard let stopStore = page.store else { return nil }
            return Stop(storeID: stopStore.id, name: stopStore.name, colorHex: stopStore.colorHex, count: page.openCount)
        }
        return TripStatus(
            store: store,
            next: page.items.prefix(maximumLines).map { Line(id: $0.id, title: $0.title, note: $0.note) },
            openCount: page.openCount,
            doneCount: trip.doneItemIDs.count,
            stops: stops,
            hasLoyaltyCard: !snapshot.loyaltyCards(for: store.id).isEmpty,
            isOnTheWay: trip.isOnTheWay && snapshot.presence?.storeID != store.id,
            distanceMeters: page.distanceMeters
        )
    }
}
