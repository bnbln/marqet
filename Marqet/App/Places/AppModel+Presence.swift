import Foundation
import MarqetCore

/// At the store (KONZEPT-WIDGETS §13): Marqet knows which store the user is at, shows its list
/// everywhere and lets the Live Activity report the arrival.
extension AppModel {
    /// Stores worth a stop: open items or planned.
    var storesWorthAStop: Set<Store.ID> {
        Set(stores.filter { openItemCount(of: $0.id) > 0 || $0.plannedAt != nil }.map(\.id))
    }

    /// Saved branches plus branches of the user's stores found around `origin`. MapKit is asked
    /// again only after moving 250 m, like for the brochure distances.
    func branchCandidates(near origin: GeoPoint?) async -> [BranchCandidate] {
        let saved = locations.map { BranchCandidate(storeID: $0.storeID, coordinate: $0.coordinate) }
        guard let origin else { return saved }
        if let cached = nearbyBranches, cached.origin.distance(to: origin) < 250 {
            return saved + cached.branches
        }
        let places = (try? await placeSearch.shops(near: origin)) ?? []
        let found = places.compactMap { place in
            existingStore(for: place).map { BranchCandidate(storeID: $0.id, coordinate: place.coordinate) }
        }
        nearbyBranches = (origin, found)
        return saved + found
    }

    /// When the app opens: detect the store the user is at, then keep the watched branches current.
    func updatePresence() async {
        await detectPresence()
        await refreshGeofences()
    }

    /// With location access already given (never asks): is the user inside a branch's circle?
    func detectPresence() async {
        guard followsPresence, isInForeground, phase == .ready,
              locationProvider.authorization == .authorized,
              let origin = await locationProvider.currentLocation() else { return }
        userLocation = origin
        let fences = GeofencePlanner.geofences(
            branches: await branchCandidates(near: origin),
            relevantStores: storesWorthAStop,
            near: origin,
            limit: 60
        )
        if let fence = GeofencePlanner.geofence(containing: origin, in: fences) {
            await arrive(at: fence, source: .location)
        } else if presence?.source == .location {
            // Walked away since the last check.
            presence = nil
        }
    }

    /// Arrived at a branch – from a geofence (possibly in the background) or a position fix.
    func arrive(at fence: Geofence, source: StorePresence.Source, date: Date = .now) async {
        guard let store = store(fence.storeID) else { return }
        let isNew = presence?.storeID != store.id || presence?.isValid(at: date) != true
        guard isNew else { return }
        presence = StorePresence(storeID: store.id, branch: fence.center, since: date, source: source)
        showPresentStoreIfNeeded()
        // Only a real arrival reports itself; opening the app at the store just shows the list.
        guard source == .geofence, openItemCount(of: store.id) > 0 else {
            if let trip, trip.storeID == store.id { self.trip?.arrive(at: store.id, at: date) }
            await syncWidgetsNow()
            return
        }
        await announceArrival(at: store, date: date)
    }

    /// The Live Activity reports: a running trip moves here with an alert (lights up the Lock
    /// Screen, expands the Dynamic Island). Without a trip Marqet tries to start one – iOS allows
    /// that only in the foreground – and otherwise sends a notification with "Einkauf starten".
    private func announceArrival(at store: Store, date: Date) async {
        let alert = TripAlert(title: String(localized: "Du bist bei \(store.name)"), body: arrivalSummary(for: store))
        if trip != nil {
            trip?.arrive(at: store.id, at: date)
            await syncWidgetsNow(alert: alert)
            return
        }
        trip = ShoppingTrip(storeID: store.id, startedAt: date)
        let result = await syncWidgetsNow(alert: alert)
        guard !result.isRunning else { return }
        // No Live Activity: no trip either, the notification offers it.
        trip = nil
        await syncWidgetsNow()
        if !isInForeground {
            await ArrivalNotifier.notifyArrival(at: store, body: alert.body)
        }
    }

    /// "9 Einträge: Bananen, Zucchini, Vollkornbrot …" – in walking order, like the card.
    func arrivalSummary(for store: Store) -> String {
        let page = PageID.store(store.id)
        let titles = sections(for: page, items: deck.items(on: page)).flatMap(\.items).map(\.title)
        let count = titles.count
        let preview = titles.prefix(3).joined(separator: ", ") + (count > 3 ? " …" : "")
        return count == 1 ? String(localized: "1 Eintrag: \(preview)") : String(localized: "\(count) Einträge: \(preview)")
    }

    func leave(_ fence: Geofence) async {
        guard presence?.storeID == fence.storeID else { return }
        presence = nil
        ArrivalNotifier.withdraw(for: fence.storeID)
        await syncWidgetsNow()
    }

    /// The pager jumps to the store once per arrival – never while the user types, assigns or
    /// looks at a card full screen.
    func showPresentStoreIfNeeded() {
        guard followsPresence, isInForeground, let presence, jumpedToPresence != presence,
              composerTarget == nil, triage == nil, focusedPage == nil else { return }
        let page = PageID.store(presence.storeID)
        guard deck.pages.contains(page), openItemCount(of: presence.storeID) > 0 else { return }
        jumpedToPresence = presence
        dismissBriefing()
        activePage = page
        pageRequest = page
    }

    // MARK: Watching branches

    /// Keeps the watched circles on the nearest branches of stores worth a stop.
    func refreshGeofences() async {
        guard sharesWithWidgets, phase == .ready else { return }
        guard arrivalAlertsEnabled, locationProvider.isAlwaysAuthorized else {
            if PresenceMonitor.shared.isRunning {
                await PresenceMonitor.shared.stop()
                geofences = []
            }
            return
        }
        await startPresenceMonitor()
        watchedStores = storesWorthAStop
        let origin = await locationProvider.currentLocation() ?? userLocation
        let fences = GeofencePlanner.geofences(
            branches: await branchCandidates(near: origin),
            relevantStores: watchedStores,
            near: origin
        )
        guard fences != geofences else { return }
        geofences = fences
        await PresenceMonitor.shared.update(fences)
    }

    /// Also right at launch: after a background relaunch the waiting arrival arrives here.
    func startPresenceMonitor() async {
        PresenceMonitor.shared.handler = { [weak self] fence, entered, date in
            guard let self, await self.prepareInBackground() else { return }
            if entered {
                await self.arrive(at: fence, source: .geofence, date: date)
            } else {
                await self.leave(fence)
            }
        }
        await PresenceMonitor.shared.start()
    }

    /// Switching arrival alerts on asks for location "Immer" and notifications. Returns whether
    /// both are there; without "Immer" the list still follows the store whenever the app opens.
    @discardableResult
    func setArrivalAlerts(_ enabled: Bool) async -> Bool {
        guard enabled else {
            arrivalAlertsEnabled = false
            await refreshGeofences()
            return true
        }
        let hasLocation = await locationProvider.requestAlwaysAuthorization()
        let hasNotifications = await ArrivalNotifier.requestAuthorization()
        ArrivalNotifier.registerCategory()
        arrivalAlertsEnabled = hasLocation
        await refreshGeofences()
        return hasLocation && hasNotifications
    }

    /// Loads the list if the system launched Marqet in the background (widget button, arrival).
    func prepareInBackground() async -> Bool {
        startWidgetSync()
        if !hasLoadedItems || phase != .ready {
            if trip == nil, sharesWithWidgets { trip = SharedStore.trip.flatMap { store($0.storeID) == nil ? nil : $0 } }
            await refreshPhase()
        }
        return phase == .ready
    }
}
