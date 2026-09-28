import AppIntents
import Foundation
import MarqetCore
import Observation
import WidgetKit

/// Customer cards shown full screen from outside the app (widget, Live Activity, control).
struct LoyaltyCardPresentation: Identifiable {
    let cards: [LoyaltyCard]
    let initialCardID: LoyaltyCard.ID?
    var id: String { cards.map(\.id.uuidString).joined() }
}

struct LeafletPresentation: Identifiable {
    let url: URL
    var id: URL { url }
}

// MARK: - Snapshot for widgets (KONZEPT-WIDGETS §9.2)

extension AppModel {
    /// What the widget extension needs to rebuild the snapshot from Reminders on its own.
    func makeWidgetRegistry() -> WidgetRegistry {
        let isReady = hasCompletedOnboarding && phase == .ready && selectedListID != nil
        let usesRouteLearning = isPro && routeLearningEnabled
        let ordered = sortedStores
        var categoryPositions: [String: [String: OrderPosition]] = [:]
        var itemPositions: [String: [String: OrderPosition]] = [:]
        var branches: [String: GeoPoint] = [:]
        for store in ordered {
            let key = store.id.uuidString
            let positions = categoryPositionsLoaded(for: store.id)
            if !positions.isEmpty { categoryPositions[key] = WidgetRegistry.encode(categoryPositions: positions) }
            if usesRouteLearning {
                let items = itemPositionsLoaded(for: store.id)
                if !items.isEmpty { itemPositions[key] = items }
            }
            if let location = relevantLocation(of: store.id) { branches[key] = location.coordinate }
        }
        let brochures = (catalog?.entries(for: region) ?? []).compactMap { entry -> WidgetRegistry.BrochureSource? in
            guard let url = entry.leafletURL else { return nil }
            return .init(key: entry.key, name: entry.name, colorHex: entry.color, symbol: entry.storeSymbol, url: url,
                         distanceMeters: nearbyCatalogDistances[entry.key])
        }
        let accent = AppAccentPalette(rawValue: defaults.string(forKey: AppAccentPalette.storageKey) ?? "") ?? .leaf
        return WidgetRegistry(
            status: isReady ? .ready : .needsSetup,
            listID: selectedListID,
            listTitle: selectedList?.title ?? "",
            stores: ordered,
            storeOrder: storeSortMode == .manual ? nil : storeOrderSnapshot,
            emptiedInSession: emptiedInSession.sorted { $0.uuidString < $1.uuidString },
            categoryPositions: categoryPositions,
            itemPositions: usesRouteLearning ? itemPositions : nil,
            learnedCategories: classifier.learned.mapValues { $0.category },
            assignmentCounts: WidgetRegistry.encode(assignments: assignmentMemory),
            loyaltyCards: loyaltyCards.sorted { $0.createdAt < $1.createdAt },
            brochureSources: brochures,
            branchCoordinates: branches,
            userLocation: userLocation,
            accentHex: accent.hex
        )
    }

    /// The snapshot the widgets show – the same builder the widget extension uses.
    func makeWidgetSnapshot(registry: WidgetRegistry? = nil, completed: [ShoppingItem]? = nil) -> WidgetSnapshot {
        WidgetSnapshotBuilder.snapshot(
            registry: registry ?? makeWidgetRegistry(),
            items: items,
            recentlyCompleted: completed ?? recentlyCompleted,
            classifier: classifier,
            trip: trip
        )
    }

    /// Observes everything widgets show and writes the snapshot shortly after each change.
    func startWidgetSync() {
        guard !isSyncingWidgets else { return }
        isSyncingWidgets = true
        observeWidgetInputs()
    }

    private func observeWidgetInputs() {
        withObservationTracking {
            _ = (items, stores, loyaltyCards, locations, trip, phase, lists, selectedListID, hasCompletedOnboarding)
            _ = (storeSortMode, storeOrderSnapshot, emptiedInSession, orderRevision, userLocation, recentlyCompleted)
            _ = (hasProEntitlement, developerProOverride, routeLearningEnabled, nearbyCatalogDistances, region)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.scheduleWidgetSync()
                self.observeWidgetInputs()
            }
        }
    }

    /// Debounced: checking off five items quickly writes once.
    func scheduleWidgetSync() {
        widgetSyncTask?.cancel()
        widgetSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.syncWidgetsNow()
        }
    }

    /// Writes registry and snapshot, reloads widgets if something changed and updates the
    /// Live Activity. Intents call it directly before they return.
    func syncWidgetsNow() async {
        guard sharesWithWidgets, phase != .launching else { return }
        let registry = makeWidgetRegistry()
        let completed = await completedForWidgets()
        let snapshot = makeWidgetSnapshot(registry: registry, completed: completed)
        let registryChanged = SharedStore.write(registry)
        let snapshotChanged = SharedStore.write(snapshot)
        if registryChanged || snapshotChanged {
            WidgetCenter.shared.reloadAllTimelines()
            // The "Einkauf" switch in Control Center follows the trip.
            ControlCenter.shared.reloadAllControls()
        }
        if registryChanged {
            // Siri phrases with store names ("Einkauf bei Aldi starten").
            MarqetShortcuts.updateAppShortcutParameters()
        }
        let finished = await TripActivityController.sync(snapshot: snapshot, trip: trip) { [weak self] tripID in
            await self?.tripActivityDismissed(tripID: tripID)
        }
        if finished { trip = nil }
    }

    /// Checked off in the last 7 days, from Reminders (also by others) plus this session.
    private func completedForWidgets() async -> [ShoppingItem] {
        guard phase == .ready, let listID = selectedListID else { return recentlyCompleted }
        let since = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        guard let fetched = try? await gateway.completedReminders(in: listID, since: since) else { return recentlyCompleted }
        let matcher = StoreMatcher(stores: stores)
        var merged = fetched.map { ShoppingItemMapper.item(from: $0, matcher: matcher) }
        let ids = Set(merged.map(\.id))
        merged += recentlyCompleted.filter { !ids.contains($0.id) }
        return merged
    }
}

// MARK: - Shopping trip (KONZEPT-WIDGETS §5)

extension AppModel {
    /// Starts the trip at a store – `nil` picks the next store with items. Returns the store.
    @discardableResult
    func startTrip(at storeID: Store.ID?) async -> Store? {
        let target = storeID
            ?? trip?.storeID
            ?? deck.pages.compactMap(\.storeID).first { openItemCount(of: $0) > 0 }
        guard let target, let store = store(target) else { return nil }
        if var current = trip {
            current.moveTo(target)
            trip = current
        } else {
            trip = ShoppingTrip(storeID: target)
        }
        await syncWidgetsNow()
        return store
    }

    func moveTrip(to storeID: Store.ID) async {
        guard store(storeID) != nil else { return }
        trip?.moveTo(storeID)
        await syncWidgetsNow()
    }

    func endTrip() async {
        trip = nil
        await syncWidgetsNow()
    }

    /// Whoever checks something off in a store is shopping there: the trip starts (setting) or moves.
    func recordTripCompletion(of item: ShoppingItem) {
        guard let storeID = item.storeID, store(storeID) != nil else { return }
        if trip == nil {
            guard autoStartsTrip else { return }
            trip = ShoppingTrip(storeID: storeID)
        }
        trip?.recordCompletion(of: item.id, in: storeID)
    }

    /// 30 minutes without checking anything off end the trip, like the shopping session.
    func endTripIfExpired(now: Date = .now) {
        guard let trip, trip.isExpired(at: now) else { return }
        self.trip = nil
    }

    /// The user swiped the Live Activity away: the trip is over.
    func tripActivityDismissed(tripID: UUID) {
        if trip?.id == tripID { trip = nil }
    }

    /// "Nochmal kaufen" for an item that may only be known to Reminders (widget "Zuletzt erledigt").
    func reopen(itemID: ShoppingItem.ID) async {
        if let item = recentlyCompleted.first(where: { $0.id == itemID }) {
            await restore(item)
            return
        }
        trip?.recordReopening(of: itemID)
        await perform { try await $0.setCompleted(false, reminder: itemID) }
        await reload()
    }
}

// MARK: - Deep links (KONZEPT-WIDGETS §8)

extension AppModel {
    func open(_ url: URL) {
        guard let link = MarqetLink(url: url) else { return }
        open(link)
    }

    /// Opens a card, the composer, triage, a customer card or a leaflet. Before the list is
    /// loaded (cold start from a widget) the link waits.
    func open(_ link: MarqetLink) {
        guard phase == .ready, hasLoadedItems else {
            pendingLink = link
            return
        }
        pendingLink = nil
        switch link {
        case .page(let page):
            show(page)
        case .compose(let page):
            closeOverlays()
            startComposer(on: page)
        case .triage:
            closeOverlays()
            if unsortedItems.isEmpty { show(.unsorted) } else { startTriage() }
        case .completed:
            closeOverlays()
            focusedPage = nil
            showsCompleted = true
            Task { await loadRecentlyCompleted() }
        case .loyaltyCard(let id):
            guard let card = loyaltyCards.first(where: { $0.id == id }) else { return }
            presentAfterClosingOverlays { $0.presentedLoyaltyCards = LoyaltyCardPresentation(cards: [card], initialCardID: id) }
        case .storeLoyaltyCards(let storeID):
            let cards = loyaltyCards(for: storeID)
            if cards.isEmpty {
                show(.store(storeID))
            } else {
                presentAfterClosingOverlays { $0.presentedLoyaltyCards = LoyaltyCardPresentation(cards: cards, initialCardID: nil) }
            }
        case .offers:
            show(.brochures)
        case .offer(let key):
            guard let url = catalog?.entry(forKey: key)?.leafletURL else { return show(.brochures) }
            presentAfterClosingOverlays { $0.presentedLeaflet = LeafletPresentation(url: url) }
        case .trip:
            if let trip { show(.store(trip.storeID)) }
        }
    }

    func openPendingLink() {
        guard let link = pendingLink else { return }
        open(link)
    }

    /// A card full screen; a hidden store gets planned so its card exists.
    private func show(_ page: PageID) {
        closeOverlays()
        switch page {
        case .brochures, .more:
            focusedPage = nil
            activePage = page
            pageRequest = page
        case .unsorted, .store:
            if let id = page.storeID, !deck.pages.contains(page) { plan(id) }
            activePage = page
            pageRequest = page
            focusedPage = page
        }
    }

    private func closeOverlays() {
        dismissBriefing()
        if composerTarget != nil { endComposer() }
        if triage != nil { endTriage() }
    }

    /// Full-screen covers cannot stack: close the card or triage first, then present.
    private func presentAfterClosingOverlays(_ present: @escaping @MainActor (AppModel) -> Void) {
        let needsDismissal = focusedPage != nil || triage != nil
        closeOverlays()
        focusedPage = nil
        guard needsDismissal else { return present(self) }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            if let self { present(self) }
        }
    }
}
