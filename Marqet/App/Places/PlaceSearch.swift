import Foundation
import MapKit
import MarqetCore

/// A place found in Apple Maps, reduced to what Marqet needs.
struct PlaceResult: Identifiable, Hashable, Sendable {
    var id: String { mapItemIdentifier ?? "\(name)@\(coordinate.latitude),\(coordinate.longitude)" }
    let name: String
    let address: String?
    let coordinate: GeoPoint
    let mapItemIdentifier: String?
    /// Store kind guessed from the Apple Maps category, for stores created from the map.
    let suggestedType: StoreType
}

@MainActor
protocol PlaceSearching: AnyObject {
    /// Branches of one store within `radius` meters of `origin` (chain stores: only that chain).
    func branches(of store: Store, chain: StoreCatalog.Entry?, near origin: GeoPoint, radius: Double) async throws -> [PlaceResult]
    /// Shops around `origin` – for "Läden in der Nähe" on the map.
    func shops(near origin: GeoPoint) async throws -> [PlaceResult]
    /// Free-text search ("Hofladen Maier").
    func search(_ query: String, near origin: GeoPoint?) async throws -> [PlaceResult]
}

/// MapKit-backed search. Results are cached per query and area for a day, because MapKit
/// throttles searches (KONZEPT §14.1).
@MainActor
final class MapKitPlaceSearch: PlaceSearching {
    static let branchRadius: CLLocationDistance = 5_000
    static let shopsRadius: CLLocationDistance = 2_500
    /// `.store` is left out on purpose: in city centres it returns dozens of boutiques and pushes
    /// the supermarkets out of MapKit's result limit. Chains come from the text queries instead.
    private static let shopCategories: [MKPointOfInterestCategory] = [.foodMarket, .pharmacy, .bakery]
    private static let shopQueries = ["Supermarkt", "Discounter", "Drogerie"]

    private var cache: [String: (results: [PlaceResult], date: Date)] = [:]

    func branches(of store: Store, chain: StoreCatalog.Entry?, near origin: GeoPoint, radius: Double) async throws -> [PlaceResult] {
        // MapKit returns at most ~25 results per request – every search term ("EDEKA", "E center")
        // gets its own request, and a smaller radius (zoomed-in map) finds the rest.
        let terms = chain?.mapSearchTerms ?? [chain?.name ?? store.name]
        var results: [PlaceResult] = []
        for term in terms {
            let found = try await cached("branch:\(term):\(Int(radius / 500))", near: origin) {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = term
                request.resultTypes = .pointOfInterest
                request.region = MKCoordinateRegion(center: origin.clCoordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
                return try await Self.run(request)
            }
            results += found
        }
        var seen = Set<String>()
        results = results.filter { seen.insert($0.id).inserted }
        if let chain {
            // Apple Maps also returns look-alikes ("Aldi Nord" for "Aldi Süd") – keep only the chain.
            return results.filter { ChainRecognizer.entry(forPlaceNamed: $0.name, in: [chain])?.key == chain.key }
        }
        let key = ItemKeyNormalizer.storeNameKey(store.name)
        return results.filter { ItemKeyNormalizer.storeNameKey($0.name).hasPrefix(key) }
    }

    func shops(near origin: GeoPoint) async throws -> [PlaceResult] {
        try await cached("shops", near: origin) {
            let request = MKLocalPointsOfInterestRequest(center: origin.clCoordinate, radius: Self.shopsRadius)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: Self.shopCategories)
            var results = try await MKLocalSearch(request: request).start().mapItems.map(PlaceResult.init)
            for query in Self.shopQueries {
                let search = MKLocalSearch.Request()
                search.naturalLanguageQuery = query
                search.resultTypes = .pointOfInterest
                search.region = MKCoordinateRegion(center: origin.clCoordinate, latitudinalMeters: Self.shopsRadius * 2, longitudinalMeters: Self.shopsRadius * 2)
                // One failing query (throttling) should not hide the others.
                if let items = try? await Self.run(search) { results += items }
            }
            var seen = Set<String>()
            return results.filter { seen.insert($0.id).inserted }
        }
    }

    func search(_ query: String, near origin: GeoPoint?) async throws -> [PlaceResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        if let origin {
            request.region = MKCoordinateRegion(center: origin.clCoordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        }
        return try await Self.run(request)
    }

    private static func run(_ request: MKLocalSearch.Request) async throws -> [PlaceResult] {
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map(PlaceResult.init)
    }

    /// Same query within ~2 km of the last origin and younger than a day → cached result.
    private func cached(_ key: String, near origin: GeoPoint, fetch: () async throws -> [PlaceResult]) async throws -> [PlaceResult] {
        let area = "\(key)@\((origin.latitude * 50).rounded()),\((origin.longitude * 50).rounded())"
        if let hit = cache[area], Date.now.timeIntervalSince(hit.date) < 24 * 60 * 60 { return hit.results }
        let results = try await fetch()
        cache[area] = (results, .now)
        return results
    }
}

extension PlaceResult {
    init(_ item: MKMapItem) {
        let coordinate = item.location.coordinate
        self.init(
            name: item.name ?? "",
            address: item.address?.shortAddress ?? item.address?.fullAddress,
            coordinate: GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude),
            mapItemIdentifier: item.identifier?.rawValue,
            suggestedType: StoreType(category: item.pointOfInterestCategory)
        )
    }
}

extension StoreType {
    init(category: MKPointOfInterestCategory?) {
        switch category {
        case .foodMarket?: self = .supermarket
        case .pharmacy?: self = .pharmacy
        case .bakery?: self = .bakery
        case .store?: self = .other
        default: self = .other
        }
    }
}

extension GeoPoint {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
