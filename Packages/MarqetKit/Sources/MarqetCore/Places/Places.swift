import Foundation

/// WGS84 coordinate, independent of CoreLocation so the core stays Foundation-only.
public struct GeoPoint: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in meters (haversine).
    public func distance(to other: GeoPoint) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// A branch of a store (KONZEPT §14.1). One can be preferred per store.
public struct StoreLocation: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var storeID: Store.ID
    public var name: String
    public var address: String?
    public var coordinate: GeoPoint
    /// `MKMapItem.identifier` for reloading details from Apple Maps.
    public var mapItemIdentifier: String?
    public var isPreferred: Bool

    public init(
        id: UUID = UUID(),
        storeID: Store.ID,
        name: String,
        address: String? = nil,
        coordinate: GeoPoint,
        mapItemIdentifier: String? = nil,
        isPreferred: Bool = false
    ) {
        self.id = id
        self.storeID = storeID
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.mapItemIdentifier = mapItemIdentifier
        self.isPreferred = isPreferred
    }
}

/// How the store cards are ordered (KONZEPT §14.2).
public enum StoreSortMode: String, CaseIterable, Sendable, Codable {
    /// The user's order from "Läden sortieren".
    case manual
    /// Nearest (preferred or closest) branch first.
    case distance
    /// Most items per minute of travel first: `open items / (minutes + 5)`.
    case smart
}

public enum TravelMode: String, CaseIterable, Sendable, Codable {
    case walking, driving

    /// Average door-to-door speed in m/s for the estimate (no routing request needed).
    var metersPerSecond: Double {
        switch self {
        case .walking: 1.3        // ≈ 4.7 km/h
        case .driving: 7.5        // ≈ 27 km/h city average incl. lights
        }
    }

    /// Straight-line distances underestimate real routes; this detour factor corrects for it.
    static let detourFactor = 1.3
}

public enum PlaceMath {
    /// Estimated travel time in minutes from a straight-line distance.
    public static func travelMinutes(meters: Double, mode: TravelMode) -> Double {
        meters * TravelMode.detourFactor / mode.metersPerSecond / 60
    }

    /// The branch that counts for a store: the preferred one, otherwise the nearest one.
    public static func relevantLocation(of locations: [StoreLocation], from origin: GeoPoint?) -> StoreLocation? {
        if let preferred = locations.first(where: \.isPreferred) { return preferred }
        guard let origin else { return locations.first }
        return locations.min { $0.coordinate.distance(to: origin) < $1.coordinate.distance(to: origin) }
    }
}

/// Orders stores for the pager (KONZEPT §14.2). Pure; the caller snapshots the result so cards
/// never reorder under the user's finger.
public enum StoreSorter {
    /// Fixed cost per stop (parking, checkout) in the smart score.
    public static let stopOverheadMinutes = 5.0

    public static func order(
        stores: [Store],
        mode: StoreSortMode,
        openItemCounts: [Store.ID: Int],
        travelMinutes: [Store.ID: Double]
    ) -> [Store.ID] {
        let manual = stores.sorted { $0.sortIndex < $1.sortIndex }
        guard mode != .manual else { return manual.map(\.id) }

        let known = manual.filter { travelMinutes[$0.id] != nil }
        let unknown = manual.filter { travelMinutes[$0.id] == nil }

        let sortedKnown: [Store]
        switch mode {
        case .distance:
            sortedKnown = known.sorted { travelMinutes[$0.id]! < travelMinutes[$1.id]! }
        case .smart:
            // Stores with items by score; empty (planned) stores after them, nearest first.
            func score(_ store: Store) -> Double {
                Double(openItemCounts[store.id] ?? 0) / (travelMinutes[store.id]! + stopOverheadMinutes)
            }
            sortedKnown = known.sorted { lhs, rhs in
                let (l, r) = (score(lhs), score(rhs))
                if l != r { return l > r }
                return travelMinutes[lhs.id]! < travelMinutes[rhs.id]!
            }
        case .manual:
            sortedKnown = known
        }
        // Stores without a branch keep their manual order at the end.
        return (sortedKnown + unknown).map(\.id)
    }
}

/// Recognizes a catalog chain in an Apple Maps point of interest ("ALDI SÜD", "REWE City").
public enum ChainRecognizer {
    /// Generic kinds ("Markt", "Bäcker") are never recognized from a POI name – every bakery
    /// would otherwise become "Bäcker".
    public static func entry(forPlaceNamed placeName: String, in catalog: [StoreCatalog.Entry]) -> StoreCatalog.Entry? {
        let placeWords = words(placeName)
        let placeKey = placeWords.joined()
        guard !placeKey.isEmpty else { return nil }
        var best: (entry: StoreCatalog.Entry, length: Int)?
        for entry in catalog where !entry.key.hasPrefix("generic-") {
            let names = [entry.name] + entry.aliases + (entry.mapSearchTerms ?? [])
            for name in names {
                let nameWords = words(name)
                let key = nameWords.joined()
                // The chain must lead the place name as whole words ("REWE City", "EDEKA-Center"),
                // so "HIT" does not match "Hitzler" and "Norma" not "Normann".
                guard key.count >= 2, placeKey == key || placeWords.starts(with: nameWords) else { continue }
                if key.count > (best?.length ?? 0) { best = (entry, key.count) }
            }
        }
        return best?.entry
    }

    private static func words(_ name: String) -> [String] {
        ItemKeyNormalizer.fold(name)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
