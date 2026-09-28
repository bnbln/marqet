import Foundation

/// "Du bist bei Aldi Süd": the store the user is at right now (KONZEPT-WIDGETS §13).
///
/// Wherever Marqet picks a list by itself – the widget "Nächster Laden", the automatic customer
/// card, the pager when the app opens – this store wins.
public struct StorePresence: Codable, Sendable, Hashable {
    public enum Source: String, Codable, Sendable {
        /// A monitored circle around a branch reported the arrival (also in the background).
        case geofence
        /// A position fix while the app was open fell inside a branch's circle.
        case location
    }

    public let storeID: Store.ID
    /// The branch the user is at.
    public let branch: GeoPoint
    public let since: Date
    public let source: Source

    /// Without a "left" event a presence ends after this long – nobody shops for three hours.
    public static let lifetime: TimeInterval = 2 * 60 * 60

    public init(storeID: Store.ID, branch: GeoPoint, since: Date = .now, source: Source) {
        self.storeID = storeID
        self.branch = branch
        self.since = since
        self.source = source
    }

    public func isValid(at date: Date) -> Bool {
        date.timeIntervalSince(since) < Self.lifetime
    }
}

/// A branch Marqet could watch: a saved branch or one of the store's chain found nearby.
public struct BranchCandidate: Hashable, Sendable {
    public let storeID: Store.ID
    public let coordinate: GeoPoint

    public init(storeID: Store.ID, coordinate: GeoPoint) {
        self.storeID = storeID
        self.coordinate = coordinate
    }
}

/// One watched circle around a branch. The identifier carries store and position, so an event
/// after a background relaunch can be resolved without any other state.
public struct Geofence: Hashable, Sendable, Identifiable {
    public let storeID: Store.ID
    public let center: GeoPoint
    public let radius: Double

    public init(storeID: Store.ID, center: GeoPoint, radius: Double = GeofencePlanner.radius) {
        self.storeID = storeID
        self.center = center
        self.radius = radius
    }

    /// `"<store UUID>@48.13740,11.57550"` – five decimals are about one metre.
    public var id: String {
        "\(storeID.uuidString)@\(String(format: "%.5f", center.latitude)),\(String(format: "%.5f", center.longitude))"
    }

    public init?(identifier: String, radius: Double = GeofencePlanner.radius) {
        let parts = identifier.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, let storeID = UUID(uuidString: parts[0]) else { return nil }
        let numbers = parts[1].split(separator: ",").compactMap { Double($0) }
        guard numbers.count == 2 else { return nil }
        self.init(storeID: storeID, center: GeoPoint(latitude: numbers[0], longitude: numbers[1]), radius: radius)
    }

    public func contains(_ point: GeoPoint) -> Bool {
        center.distance(to: point) <= radius
    }
}

/// Which branches to watch (KONZEPT-WIDGETS §13.2).
public enum GeofencePlanner {
    /// iOS watches at most 20 conditions per app; two stay free for the system.
    public static let maximumRegions = 18
    /// Large enough for the parking lot and GPS drift in a building, small enough not to fire
    /// for the store across the street.
    public static let radius = 150.0
    /// Two found branches of one store closer than this are the same building.
    static let sameBranchDistance = 40.0

    /// Branches of stores worth a stop (open items or planned), nearest first. Without a position
    /// the saved order is kept and the limit still applies.
    public static func geofences(
        branches: [BranchCandidate],
        relevantStores: Set<Store.ID>,
        near origin: GeoPoint?,
        limit: Int = maximumRegions
    ) -> [Geofence] {
        var unique: [BranchCandidate] = []
        for branch in branches where relevantStores.contains(branch.storeID) {
            let duplicate = unique.contains {
                $0.storeID == branch.storeID && $0.coordinate.distance(to: branch.coordinate) < sameBranchDistance
            }
            if !duplicate { unique.append(branch) }
        }
        let ordered: [BranchCandidate]
        if let origin {
            ordered = unique.enumerated().sorted { lhs, rhs in
                let l = lhs.element.coordinate.distance(to: origin)
                let r = rhs.element.coordinate.distance(to: origin)
                return l == r ? lhs.offset < rhs.offset : l < r
            }.map(\.element)
        } else {
            ordered = unique
        }
        return ordered.prefix(limit).map { Geofence(storeID: $0.storeID, center: $0.coordinate) }
    }

    /// The watched branch a position lies in – the nearest one if circles overlap.
    public static func geofence(containing point: GeoPoint, in geofences: [Geofence]) -> Geofence? {
        geofences
            .filter { $0.contains(point) }
            .min { $0.center.distance(to: point) < $1.center.distance(to: point) }
    }
}
