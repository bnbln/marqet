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
        let meters = location.coordinate.distance(to: userLocation)
        // "650 m" below a kilometre, "1,2 km" above – more precision would be false accuracy.
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
