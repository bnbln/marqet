import Foundation
import MarqetCore

/// Branches, map and distance-based card order (KONZEPT §14.1, §14.2 – in v1.0 per decision E2).
extension AppModel {
    var locationAuthorization: LocationAuthorization {
        locationProvider.authorization
    }

    func locations(of storeID: Store.ID) -> [StoreLocation] {
        locations.filter { $0.storeID == storeID }
    }

    /// The branch that counts for this store: preferred, else nearest.
    func relevantLocation(of storeID: Store.ID) -> StoreLocation? {
        PlaceMath.relevantLocation(of: locations(of: storeID), from: userLocation)
    }

    func travelMinutes(to storeID: Store.ID) -> Double? {
        guard let userLocation, let location = relevantLocation(of: storeID) else { return nil }
        return PlaceMath.travelMinutes(meters: location.coordinate.distance(to: userLocation), mode: travelMode)
    }

    /// "1,2 km" / "350 m" for card subtitles and lists.
    func distanceText(to storeID: Store.ID) -> String? {
        guard let userLocation, let location = relevantLocation(of: storeID) else { return nil }
        return Self.distanceText(meters: location.coordinate.distance(to: userLocation))
    }

    func distanceText(to point: GeoPoint) -> String? {
        userLocation.map { Self.distanceText(meters: point.distance(to: $0)) }
    }

    /// "650 m" below a kilometre, "1,2 km" above – more precision would be false accuracy.
    static func distanceText(meters: Double) -> String {
        let rounded = meters < 1_000 ? (meters / 10).rounded() * 10 : meters
        return Measurement(value: rounded, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(meters < 1_000 ? 0...0 : 0...1))))
    }

    // MARK: Order

    /// Recomputes the card order for distance/smart. Called when the app opens and when the mode
    /// or branches change – never while the user swipes, so cards do not jump.
    func refreshStoreOrder() async {
        guard storeSortMode != .manual else {
            storeOrderSnapshot = nil
            return
        }
        if let location = await locationProvider.currentLocation() { userLocation = location }
        var minutes: [Store.ID: Double] = [:]
        for store in stores {
            if let value = travelMinutes(to: store.id) { minutes[store.id] = value }
        }
        var counts: [Store.ID: Int] = [:]
        for item in items where !item.isCompleted {
            if let id = item.storeID { counts[id, default: 0] += 1 }
        }
        storeOrderSnapshot = StoreSorter.order(stores: stores, mode: storeSortMode, openItemCounts: counts, travelMinutes: minutes)
    }

    /// Switching to distance or smart asks for location access first; without it, manual stays.
    func setStoreSortMode(_ mode: StoreSortMode) async {
        if mode != .manual, locationProvider.authorization != .authorized {
            guard await locationProvider.requestAuthorization() == .authorized else {
                storeSortMode = .manual
                return
            }
        }
        storeSortMode = mode
        await refreshStoreOrder()
        pageRequest = activePage
    }

    func updateUserLocation() async -> GeoPoint? {
        if locationProvider.authorization == .notDetermined {
            _ = await locationProvider.requestAuthorization()
        }
        if let location = await locationProvider.currentLocation() { userLocation = location }
        return userLocation
    }

    /// Uses one nearby-shop search to rank catalog chains and their leaflets by distance.
    /// It runs only after location permission was already granted; opening a catalog page
    /// never triggers a new permission prompt.
    func refreshNearbyCatalogDistancesIfNeeded() async {
        guard !isRefreshingNearbyCatalogDistances,
              locationProvider.authorization == .authorized else { return }
        isRefreshingNearbyCatalogDistances = true
        defer { isRefreshingNearbyCatalogDistances = false }
        guard let origin = await updateUserLocation() else { return }
        if let previousOrigin = nearbyCatalogDistanceOrigin,
           nearbyCatalogDistanceRegion == region,
           previousOrigin.distance(to: origin) < 250 {
            return
        }

        let entries = catalog?.entries(for: region) ?? []
        let places = (try? await placeSearch.shops(near: origin)) ?? []
        var distances: [String: Double] = [:]
        for place in places {
            guard let entry = ChainRecognizer.entry(forPlaceNamed: place.name, in: entries) else { continue }
            let distance = place.coordinate.distance(to: origin)
            distances[entry.key] = min(distances[entry.key] ?? .infinity, distance)
        }
        nearbyCatalogDistances = distances
        nearbyCatalogDistanceOrigin = origin
        nearbyCatalogDistanceRegion = region
    }

    // MARK: Branches

    /// Saves a branch for a store. A preferred branch also becomes the address shown on the card.
    func addLocation(_ place: PlaceResult, to storeID: Store.ID, preferred: Bool = true) {
        if let existing = locations.first(where: { $0.storeID == storeID && $0.mapItemIdentifier != nil && $0.mapItemIdentifier == place.mapItemIdentifier }) {
            setPreferredLocation(existing)
            return
        }
        let location = StoreLocation(
            storeID: storeID,
            name: place.name,
            address: place.address,
            coordinate: place.coordinate,
            mapItemIdentifier: place.mapItemIdentifier,
            isPreferred: preferred || locations(of: storeID).isEmpty
        )
        save(location)
    }

    /// A typed-in address gets a point on the map: it is looked up and saved as the preferred
    /// branch, replacing an earlier manual one. Picked branches (with Maps identifier) stay.
    func placeManualAddress(_ address: String, for storeID: Store.ID) {
        guard !address.isEmpty,
              relevantLocation(of: storeID)?.address != address,
              let store = store(storeID) else { return }
        Task {
            guard let place = try? await placeSearch.search(address, near: userLocation).first else { return }
            for manual in locations(of: storeID) where manual.mapItemIdentifier == nil {
                removeLocation(manual)
            }
            save(StoreLocation(storeID: storeID, name: store.name, address: address, coordinate: place.coordinate, isPreferred: true))
        }
    }

    func setPreferredLocation(_ location: StoreLocation) {
        var preferred = location
        preferred.isPreferred = true
        save(preferred)
    }

    func removeLocation(_ location: StoreLocation) {
        locations.removeAll { $0.id == location.id }
        do {
            try locationRepository.delete(id: location.id)
        } catch {
            present(error)
        }
        // Another branch takes over as preferred, so the store keeps a place on the map.
        if location.isPreferred, let next = locations(of: location.storeID).first {
            setPreferredLocation(next)
        }
    }

    private func save(_ location: StoreLocation) {
        if location.isPreferred {
            for index in locations.indices where locations[index].storeID == location.storeID {
                locations[index].isPreferred = false
            }
            if let address = location.address, let index = stores.firstIndex(where: { $0.id == location.storeID }) {
                stores[index].address = address
                persist(stores[index])
            }
        }
        if let index = locations.firstIndex(where: { $0.id == location.id }) {
            locations[index] = location
        } else {
            locations.append(location)
        }
        do {
            try locationRepository.save(location)
        } catch {
            present(error)
        }
    }

    // MARK: Stores from the map

    /// The catalog chain behind a place, if any ("REWE City" → Rewe).
    func chain(of place: PlaceResult) -> StoreCatalog.Entry? {
        ChainRecognizer.entry(forPlaceNamed: place.name, in: catalog?.stores ?? [])
    }

    /// The own store a place belongs to (same chain or same name), if already added.
    func existingStore(for place: PlaceResult) -> Store? {
        if let chain = chain(of: place), let store = stores.first(where: { $0.catalogKey == chain.key }) { return store }
        let key = ItemKeyNormalizer.storeNameKey(place.name)
        return stores.first { ItemKeyNormalizer.storeNameKey($0.name) == key }
    }

    /// "Laden aus der Karte anlegen": chain → catalog store, otherwise an own store named like the place.
    /// The place becomes its preferred branch.
    @discardableResult
    func addStore(from place: PlaceResult) -> Store? {
        let store: Store?
        if let existing = existingStore(for: place) {
            plan(existing.id)
            store = existing
        } else if let chain = chain(of: place) {
            store = addStore(from: chain)
        } else {
            store = addCustomStore(
                name: place.name,
                type: place.suggestedType,
                colorHex: StorePalette.colors[stores.count % StorePalette.colors.count],
                systemImage: place.suggestedType.defaultSymbol
            )
        }
        if let store { addLocation(place, to: store.id) }
        return store
    }
}

// MARK: Map pins

/// One point on the map (KONZEPT §14.1).
struct MapPin: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A branch the user saved for one of their stores.
        case saved(StoreLocation)
        /// A branch of one of the user's stores found on the map, not saved yet.
        case branch(PlaceResult)
        /// A catalog chain the user has not added yet – shown faded with a plus.
        case suggestion(PlaceResult, chainKey: String)
        /// Any other place, e.g. a search result ("Hofladen Maier").
        case place(PlaceResult)
    }

    let kind: Kind
    let store: Store?

    var id: String {
        switch kind {
        case .saved(let location): "saved:\(location.id)"
        case .branch(let place): "branch:\(place.id)"
        case .suggestion(let place, _): "suggestion:\(place.id)"
        case .place(let place): "place:\(place.id)"
        }
    }

    var coordinate: GeoPoint {
        switch kind {
        case .saved(let location): location.coordinate
        case .branch(let place), .suggestion(let place, _), .place(let place): place.coordinate
        }
    }

    var place: PlaceResult? {
        switch kind {
        case .saved: nil
        case .branch(let place), .suggestion(let place, _), .place(let place): place
        }
    }
}

/// One stop on the route through stores with open shopping-list items.
struct ShoppingRouteStop: Identifiable {
    let storeID: Store.ID
    let storeName: String
    let address: String?
    let coordinate: GeoPoint

    var id: Store.ID { storeID }
}

extension AppModel {
    /// Stores whose branches the map looks up: chains with open list items, with `onlyWithItems`
    /// off the other chains after them. MapKit throttles searches, so at most `limit`.
    func storesForBranchSearch(onlyWithItems: Bool = true, limit: Int = 8) -> [Store] {
        let chains = sortedStores.filter { !($0.catalogKey?.hasPrefix("generic-") ?? false) }
        let withItems = chains.filter { openItemCount(of: $0.id) > 0 }
        let others = onlyWithItems ? [] : chains.filter { openItemCount(of: $0.id) == 0 }
        return Array((withItems + others).prefix(limit))
    }

    /// Saved branches, branches of own stores found around the map, and chains not added yet.
    /// A found place that is already saved is shown once, as the saved branch.
    /// The pin for a single place (search result): own branch, chain suggestion or plain place.
    func mapPin(for place: PlaceResult) -> MapPin {
        if let store = existingStore(for: place) {
            if let saved = locations(of: store.id).first(where: { $0.mapItemIdentifier != nil && $0.mapItemIdentifier == place.mapItemIdentifier }) {
                return MapPin(kind: .saved(saved), store: store)
            }
            return MapPin(kind: .branch(place), store: store)
        }
        if let chain = chain(of: place) { return MapPin(kind: .suggestion(place, chainKey: chain.key), store: nil) }
        return MapPin(kind: .place(place), store: nil)
    }

    func mapPins(found: [PlaceResult], includeUnmatched: Bool = false) -> [MapPin] {
        var pins = locations.compactMap { location in
            store(location.storeID).map { MapPin(kind: .saved(location), store: $0) }
        }
        var seen = Set<String>()
        for place in found where seen.insert(place.id).inserted {
            if let store = existingStore(for: place) {
                let isSaved = locations(of: store.id).contains { location in
                    (location.mapItemIdentifier != nil && location.mapItemIdentifier == place.mapItemIdentifier)
                        || location.coordinate.distance(to: place.coordinate) < 40
                }
                if !isSaved { pins.append(MapPin(kind: .branch(place), store: store)) }
            } else if let chain = chain(of: place) {
                pins.append(MapPin(kind: .suggestion(place, chainKey: chain.key), store: nil))
            } else if includeUnmatched {
                pins.append(MapPin(kind: .place(place), store: nil))
            }
        }
        return pins
    }

    /// Picks one known branch per store with open items, then orders the stops with nearest-neighbor
    /// and 2-opt passes from the user's location. Apple Maps computes the actual leg directions.
    func shoppingRouteStops(from pins: [MapPin]) -> [ShoppingRouteStop] {
        let origin = userLocation
        var stops: [ShoppingRouteStop] = []

        for store in sortedStores where openItemCount(of: store.id) > 0 {
            let candidates: [(coordinate: GeoPoint, address: String?, name: String, preferred: Bool)] = pins.compactMap { pin in
                guard pin.store?.id == store.id else { return nil }
                switch pin.kind {
                case .saved(let location):
                    return (location.coordinate, location.address, location.name, location.isPreferred)
                case .branch(let place):
                    return (place.coordinate, place.address, place.name, false)
                case .suggestion, .place:
                    return nil
                }
            }
            guard !candidates.isEmpty else { continue }

            let selected: (coordinate: GeoPoint, address: String?, name: String, preferred: Bool)
            if let origin {
                selected = candidates.min { $0.coordinate.distance(to: origin) < $1.coordinate.distance(to: origin) }!
            } else {
                selected = candidates.first(where: \.preferred) ?? candidates[0]
            }
            stops.append(ShoppingRouteStop(
                storeID: store.id,
                storeName: store.name,
                address: selected.address,
                coordinate: selected.coordinate
            ))
        }

        guard let origin else { return stops }
        var remaining = stops
        var route: [ShoppingRouteStop] = []
        var current = origin
        while !remaining.isEmpty {
            let nearestIndex = remaining.indices.min {
                remaining[$0].coordinate.distance(to: current) < remaining[$1].coordinate.distance(to: current)
            }!
            let next = remaining.remove(at: nearestIndex)
            route.append(next)
            current = next.coordinate
        }
        var improved = true
        while improved, route.count > 2 {
            improved = false
            for start in 0..<(route.count - 2) {
                for end in (start + 1)..<(route.count - 1) {
                    let before = start == 0 ? origin : route[start - 1].coordinate
                    let after = route[end + 1].coordinate
                    let currentDistance = before.distance(to: route[start].coordinate)
                        + route[end].coordinate.distance(to: after)
                    let reversedDistance = before.distance(to: route[end].coordinate)
                        + route[start].coordinate.distance(to: after)
                    if reversedDistance + 1 < currentDistance {
                        let reversedSegment = Array(route[start...end].reversed())
                        route.replaceSubrange(start...end, with: reversedSegment)
                        improved = true
                    }
                }
            }
        }
        return route
    }

    /// Apple Maps directions URL with repeated waypoints; omitting a source starts at the
    /// user's current location. The stop order is proximity-optimized above.
    func mapsRouteURL(for stops: [ShoppingRouteStop]) -> URL? {
        guard let destination = stops.last else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/directions"
        components.queryItems = [
            URLQueryItem(name: "destination", value: "\(destination.coordinate.latitude),\(destination.coordinate.longitude)"),
        ]
        for stop in stops.dropLast() {
            components.queryItems?.append(URLQueryItem(
                name: "waypoint",
                value: "\(stop.coordinate.latitude),\(stop.coordinate.longitude)"
            ))
        }
        components.queryItems?.append(URLQueryItem(name: "mode", value: travelMode.rawValue))
        return components.url
    }
}
