import Foundation
import MarqetCore
import MarqetPersistence
import MarqetReminders
import Observation
import SwiftData

/// App state and the single entry point for all reminder and store mutations (KONZEPT §9.3).
///
/// Mutations are optimistic: the UI state changes first, the EventKit write follows,
/// and a failed write rolls back by reloading from Reminders. Feature areas live in extensions:
/// `+Stores`, `+Categories`, `+Triage`, `+Intelligence`.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case needsPermission(RemindersAuthorization)
        case needsList
        case ready
    }

    /// Checked items stay visible (and undoable) this long before they leave the card.
    static let completionUndoWindow: Duration = .seconds(1.5)
    /// A shopping session ends after this much time without checking anything off (KONZEPT §7.2).
    static let sessionTimeout: TimeInterval = 30 * 60

    private(set) var phase: Phase = .launching
    private(set) var lists: [ReminderList] = []
    var items: [ShoppingItem] = []
    var stores: [Store] = []
    private(set) var recentlyCompleted: [ShoppingItem] = []
    private(set) var lastUndoAction: UndoAction?
    @ObservationIgnored private var isUndoing = false
    var showsCompleted = false
    var hasLoadedItems = false
    /// The row whose title currently owns the keyboard, across pager and detail views.
    var editingItemID: ShoppingItem.ID?
    var errorMessage: String?

    // MARK: Pager state

    /// The card the user works with. Survives folding via the pager's `@SceneStorage`.
    var activePage: PageID = .unsorted
    /// Set to scroll the pager to a page; the pager clears it.
    var pageRequest: PageID?
    /// The card opened full screen with a zoom from the pager (header tap or pull up), else `nil`.
    var focusedPage: PageID?
    /// "Was jetzt wichtig ist" above the inbox, once per launch (KONZEPT #40).
    var briefing: Briefing?
    /// 0 on the inbox, 1 one card further – the briefing follows the swipe away.
    var briefingProgress: Double = 0
    @ObservationIgnored var hasPreparedBriefing = false
    /// Pages currently on screen – they never disappear under the user's finger.
    var visiblePages: Set<PageID> = [] {
        didSet { dismissedPages.formIntersection(visiblePages) }
    }
    /// Hidden on purpose while still on screen: not retained, so the card can leave right away.
    @ObservationIgnored var dismissedPages: Set<PageID> = []

    // MARK: Composer (lives here so it survives folding, KONZEPT-DUO-IPAD §2.5)

    private(set) var composerTarget: PageID?
    var composerText = ""
    /// The item just typed in; its card scrolls it into view (it may land in any category section).
    private(set) var recentlyAddedItemID: ShoppingItem.ID?

    // MARK: Store lifecycle

    var emptiedInSession: Set<Store.ID> {
        didSet { defaults.set(emptiedInSession.map(\.uuidString), forKey: Keys.emptiedInSession) }
    }
    private(set) var pendingCompletions: Set<ShoppingItem.ID> = []

    // MARK: Categories & learning (KONZEPT §6)

    var classifier: CategoryClassifier
    var assignmentMemory = AssignmentMemory()
    /// Lazily loaded caches – filled while views read them, so not observed themselves.
    @ObservationIgnored var categoryPositions: [Store.ID: [ItemCategory: OrderPosition]] = [:]
    @ObservationIgnored var itemPositions: [Store.ID: [String: OrderPosition]] = [:]
    /// Bumped whenever an order changes; views depend on it instead of the caches.
    var orderRevision = 0
    @ObservationIgnored var sessionTracker = ShoppingSessionTracker()
    /// Apple Intelligence store suggestions per item key (Pro), filled before triage.
    var intelligentSuggestions: [String: Store.ID] = [:]

    // MARK: Voice (KONZEPT §3)

    /// Open dictation screen; `nil` when closed.
    var voiceRequest: VoiceRequest?

    // MARK: Triage (KONZEPT §7.4)

    var triage: TriageSession?
    /// Last automatic assignment, for the undo toast (Pro).
    var autoAssignReport: AutoAssignReport?

    // MARK: Settings

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }
    /// Pro bought (or family-shared) according to StoreKit. Cached for offline launches;
    /// `PurchaseManager` keeps it current, including refunds.
    var hasProEntitlement: Bool {
        didSet { defaults.set(hasProEntitlement, forKey: Keys.isPro) }
    }
    /// Developer switch – only honored in Debug builds, never unlocks Pro in Release.
    var developerProOverride: Bool {
        didSet { defaults.set(developerProOverride, forKey: Keys.developerProOverride) }
    }
    /// Opens the paywall from anywhere (locked switches, triage summary, settings).
    var showsPaywall = false

    var isPro: Bool {
        get {
            #if DEBUG
            hasProEntitlement || developerProOverride
            #else
            hasProEntitlement
            #endif
        }
        // Tests, demo and the Debug switch: sets the developer override, never the entitlement.
        set { developerProOverride = newValue }
    }
    var autoAssignEnabled: Bool {
        didSet { defaults.set(autoAssignEnabled, forKey: Keys.autoAssign) }
    }
    var intelligenceEnabled: Bool {
        didSet { defaults.set(intelligenceEnabled, forKey: Keys.intelligence) }
    }
    var routeLearningEnabled: Bool {
        didSet { defaults.set(routeLearningEnabled, forKey: Keys.routeLearning) }
    }
    // MARK: Places (KONZEPT §14, v1.0 "Orte")

    /// Branches of the user's stores.
    var locations: [StoreLocation] = []
    /// Customer cards, shown in the full-screen card of their stores (KONZEPT #42).
    var loyaltyCards: [LoyaltyCard] = []
    var storeSortMode: StoreSortMode {
        didSet { defaults.set(storeSortMode.rawValue, forKey: Keys.storeSortMode) }
    }
    var travelMode: TravelMode {
        didSet { defaults.set(travelMode.rawValue, forKey: Keys.travelMode) }
    }
    /// Last known position (only with location access).
    var userLocation: GeoPoint?
    /// Nearest Apple Maps result by retailer, used to sort catalog tiles and brochures.
    var nearbyCatalogDistances: [String: Double] = [:]
    @ObservationIgnored var nearbyCatalogDistanceOrigin: GeoPoint?
    @ObservationIgnored var nearbyCatalogDistanceRegion: StoreCatalog.Region?
    @ObservationIgnored var isRefreshingNearbyCatalogDistances = false
    /// Card order for distance/smart, computed on open – never while the user looks at the cards.
    var storeOrderSnapshot: [Store.ID]?

    // MARK: Widgets & Live Activity (KONZEPT-WIDGETS)

    /// The model of the running app. Intents from widgets, the Live Activity and controls run in
    /// the app process and act through it – there is only one path for changes.
    static weak var active: AppModel?
    /// The running shopping trip, shown as the Live Activity "Einkauf".
    var trip: ShoppingTrip? {
        didSet { if sharesWithWidgets, trip != oldValue { SharedStore.write(trip) } }
    }
    /// Only the app's own model writes to the App Group – not tests or previews.
    @ObservationIgnored var sharesWithWidgets = false

    // MARK: At the store (KONZEPT-WIDGETS §13)

    /// The store the user is at – its list wins wherever Marqet picks one.
    var presence: StorePresence?
    /// Opening the app at a store shows that store's list.
    var followsPresence: Bool {
        didSet { defaults.set(followsPresence, forKey: Keys.followsPresence) }
    }
    /// Watches branches and reports arrivals (location "Immer" and notifications).
    var arrivalAlertsEnabled: Bool {
        didSet { defaults.set(arrivalAlertsEnabled, forKey: Keys.arrivalAlerts) }
    }
    /// Branches watched right now, for the settings.
    var geofences: [Geofence] = []
    /// Set by the scene phase: jumps and notifications depend on whether the user sees the app.
    @ObservationIgnored var isInForeground = false
    @ObservationIgnored var nearbyBranches: (origin: GeoPoint, branches: [BranchCandidate])?
    @ObservationIgnored var jumpedToPresence: StorePresence?
    @ObservationIgnored var watchedStores: Set<Store.ID> = []
    /// Starts the Live Activity with the first check-off in a store.
    var autoStartsTrip: Bool {
        didSet { defaults.set(autoStartsTrip, forKey: Keys.autoStartsTrip) }
    }
    /// Customer cards opened from a widget, the Live Activity or a control.
    var presentedLoyaltyCards: LoyaltyCardPresentation?
    /// A retailer's leaflet opened from the offers widget.
    var presentedLeaflet: LeafletPresentation?
    /// A deep link that arrived before the list was loaded.
    @ObservationIgnored var pendingLink: MarqetLink?
    @ObservationIgnored var widgetSyncTask: Task<Void, Never>?
    @ObservationIgnored var isSyncingWidgets = false

    var preferredTriageMode: TriageSession.Mode {
        didSet { defaults.set(preferredTriageMode.rawValue, forKey: Keys.triageMode) }
    }

    private(set) var selectedListID: String? {
        didSet { defaults.set(selectedListID, forKey: Keys.selectedListID) }
    }

    let catalog: StoreCatalog?
    var region: StoreCatalog.Region = .current

    @ObservationIgnored let gateway: any ReminderGateway
    @ObservationIgnored let storeRepository: StoreRepository
    @ObservationIgnored let learning: LearningRepository
    @ObservationIgnored let locationRepository: LocationRepository
    @ObservationIgnored let loyaltyRepository: LoyaltyCardRepository
    @ObservationIgnored let locationProvider: any LocationProviding
    @ObservationIgnored let placeSearch: any PlaceSearching
    @ObservationIgnored let intelligence: any IntelligenceService
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored private var changeObservation: Task<Void, Never>?
    @ObservationIgnored private var pendingReload: Task<Void, Never>?
    @ObservationIgnored private var completionTasks: [ShoppingItem.ID: Task<Void, Never>] = [:]

    enum UndoAction {
        case completion(ShoppingItem)
        case assignment(ShoppingItem)
        case rename(ShoppingItem)
        case deletion(ShoppingItem)
        case creation(ShoppingItem)
        /// Several items at once, e.g. from a dictation – undone together.
        case creations([ShoppingItem])
        case stores([Store], PageID)
    }

    init(
        gateway: any ReminderGateway = EventKitGateway(),
        container: ModelContainer,
        intelligence: any IntelligenceService = FoundationModelsService(),
        defaults: UserDefaults = .standard,
        catalog: StoreCatalog? = try? StoreCatalog.bundled(),
        dictionary: CategoryDictionary? = try? CategoryDictionary.bundled(),
        location: (any LocationProviding)? = nil,
        placeSearch: (any PlaceSearching)? = nil
    ) {
        self.gateway = gateway
        self.storeRepository = StoreRepository(container: container)
        self.learning = LearningRepository(container: container)
        self.locationRepository = LocationRepository(container: container)
        self.loyaltyRepository = LoyaltyCardRepository(container: container)
        self.locationProvider = location ?? LocationService()
        self.placeSearch = placeSearch ?? MapKitPlaceSearch()
        self.storeSortMode = StoreSortMode(rawValue: defaults.string(forKey: Keys.storeSortMode) ?? "") ?? .manual
        self.travelMode = TravelMode(rawValue: defaults.string(forKey: Keys.travelMode) ?? "") ?? .driving
        self.intelligence = intelligence
        self.defaults = defaults
        self.catalog = catalog
        self.classifier = CategoryClassifier(dictionary: dictionary ?? CategoryDictionary(categories: [:]))
        self.selectedListID = defaults.string(forKey: Keys.selectedListID)
        self.emptiedInSession = Set((defaults.stringArray(forKey: Keys.emptiedInSession) ?? []).compactMap(UUID.init))
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        self.hasProEntitlement = defaults.bool(forKey: Keys.isPro)
        self.developerProOverride = defaults.bool(forKey: Keys.developerProOverride)
        self.autoAssignEnabled = defaults.object(forKey: Keys.autoAssign) as? Bool ?? true
        self.intelligenceEnabled = defaults.object(forKey: Keys.intelligence) as? Bool ?? true
        self.routeLearningEnabled = defaults.object(forKey: Keys.routeLearning) as? Bool ?? true
        self.preferredTriageMode = TriageSession.Mode(rawValue: defaults.string(forKey: Keys.triageMode) ?? "") ?? .single
        self.autoStartsTrip = defaults.object(forKey: Keys.autoStartsTrip) as? Bool ?? true
        self.followsPresence = defaults.object(forKey: Keys.followsPresence) as? Bool ?? true
        self.arrivalAlertsEnabled = defaults.bool(forKey: Keys.arrivalAlerts)
        if let data = defaults.data(forKey: Keys.sessionTracker),
           let tracker = try? JSONDecoder().decode(ShoppingSessionTracker.self, from: data) {
            self.sessionTracker = tracker
        }
        do {
            stores = try storeRepository.all()
            locations = try locationRepository.all()
            loyaltyCards = try loyaltyRepository.all()
            classifier.learned = try learning.categoryMemory()
            assignmentMemory = try learning.assignmentMemory()
        } catch {
            present(error)
        }
    }

    // MARK: Derived state

    var selectedList: ReminderList? {
        lists.first { $0.id == selectedListID }
    }

    var deck: CardDeck {
        var retained = visiblePages.subtracting(dismissedPages)
        if let composerTarget { retained.insert(composerTarget) }
        return CardBuilder.deck(
            items: items,
            stores: stores,
            context: .init(retainedPages: retained, emptiedInSession: emptiedInSession),
            storeOrder: storeSortMode == .manual ? nil : storeOrderSnapshot
        )
    }

    func store(_ id: Store.ID) -> Store? {
        stores.first { $0.id == id }
    }

    var sortedStores: [Store] {
        stores.sorted { $0.sortIndex < $1.sortIndex }
    }

    var unsortedItems: [ShoppingItem] {
        let known = Set(stores.map(\.id))
        return items.filter { !$0.isCompleted && ($0.storeID.map { !known.contains($0) } ?? true) }
    }

    // MARK: Lifecycle

    func start() async {
        // A trip from an earlier launch continues – unless its store is gone.
        if sharesWithWidgets { trip = SharedStore.trip.flatMap { store($0.storeID) == nil ? nil : $0 } }
        startWidgetSync()
        await refreshPhase()
        observeChanges()
    }

    /// Re-evaluates permission and list selection, ends expired shopping sessions, reloads.
    func refreshPhase() async {
        endShoppingSessionIfExpired()
        endTripIfExpired()
        finishExpiredRouteSessions()
        let status = await gateway.authorizationStatus()
        guard status == .fullAccess else {
            phase = .needsPermission(status)
            return
        }
        do {
            lists = try await gateway.lists()
            guard let selectedListID, lists.contains(where: { $0.id == selectedListID }) else {
                phase = .needsList
                return
            }
            phase = .ready
            await reload()
            await refreshStoreOrder()
        } catch {
            present(error)
        }
    }

    func requestAccess() async {
        do {
            _ = try await gateway.requestAccess()
        } catch {
            present(error)
        }
        await refreshPhase()
    }

    // MARK: List selection

    func selectList(_ id: String) async {
        lastUndoAction = nil
        selectedListID = id
        hasLoadedItems = false
        recentlyCompleted = []
        phase = .ready
        await reload()
    }

    func createShoppingList() async {
        await createShoppingList(named: String(localized: "Einkaufen"))
    }

    func createShoppingList(named name: String) async {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        // A second tap must not create "Einkaufen" twice: reuse a writable list of that name.
        if let existing = lists.first(where: {
            $0.allowsModifications && $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            await selectList(existing.id)
            return
        }
        do {
            let list = try await gateway.createList(named: title)
            lists.append(list)
            await selectList(list.id)
        } catch {
            present(error)
        }
    }

    func showListPicker() {
        phase = .needsList
    }

    // MARK: Items

    func reload() async {
        guard phase == .ready, let selectedListID else { return }
        do {
            apply(try await gateway.openReminders(in: selectedListID))
            await afterReload()
            // Briefing (KONZEPT #40) vorerst deaktiviert – zurück zur alten Startansicht.
            // if !hasLoadedItems { prepareBriefing() }
            hasLoadedItems = true
            openPendingLink()
        } catch {
            present(error)
        }
    }

    func addItem(title: String, to page: PageID) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let selectedListID else { return }
        let store = page.storeID.flatMap(store(_:))
        do {
            let snapshot = try await gateway.createReminder(
                title: title,
                notes: StoreMarker.write(storeName: store?.name, into: nil),
                in: selectedListID
            )
            let item = ShoppingItemMapper.item(from: snapshot, matcher: StoreMatcher(stores: stores))
            items.append(item)
            recentlyAddedItemID = item.id
            if !isUndoing { lastUndoAction = .creation(item) }
            // Typing it into a store's card is an assignment, too.
            if let store { rememberAssignment(of: item, to: store) }
        } catch {
            present(error)
        }
    }

    /// Creates several items with one undo step (dictation, KONZEPT §3.2). Returns the new items.
    @discardableResult
    func addItems(_ entries: [(title: String, page: PageID)]) async -> [ShoppingItem] {
        guard let selectedListID else { return [] }
        let matcher = StoreMatcher(stores: stores)
        var created: [ShoppingItem] = []
        for entry in entries {
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let store = entry.page.storeID.flatMap(store(_:))
            do {
                let snapshot = try await gateway.createReminder(
                    title: title,
                    notes: StoreMarker.write(storeName: store?.name, into: nil),
                    in: selectedListID
                )
                let item = ShoppingItemMapper.item(from: snapshot, matcher: matcher)
                items.append(item)
                created.append(item)
                if let store { rememberAssignment(of: item, to: store) }
            } catch {
                present(error)
            }
        }
        if let last = created.last { recentlyAddedItemID = last.id }
        if !created.isEmpty, !isUndoing { lastUndoAction = .creations(created) }
        return created
    }

    /// Moves an item to a store (or back to unsorted) and learns from it.
    func assign(_ item: ShoppingItem, to store: Store?, learn: Bool = true) async {
        if !isUndoing, item.storeID != store?.id { lastUndoAction = .assignment(item) }
        update(item.id) { $0.storeRef = store.map { .known($0.id) } }
        if learn, let store { rememberAssignment(of: item, to: store) }
        await perform { try await $0.setStore(named: store?.name, forReminder: item.id) }
    }

    func rename(_ item: ShoppingItem, to title: String) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != item.title else { return }
        if !isUndoing { lastUndoAction = .rename(item) }
        update(item.id) { $0.title = title }
        await perform { _ = try await $0.updateTitle(title, ofReminder: item.id) }
    }

    /// Replaces the user's part of the notes; the 🛒 marker line stays as it is in Reminders.
    func setNotes(_ notes: String, for item: ShoppingItem) async {
        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let userNotes = text.isEmpty ? nil : text
        guard userNotes != item.userNotes else { return }
        update(item.id) { $0.userNotes = userNotes }
        await perform {
            _ = try await $0.updateNotes(ofReminder: item.id) { current in
                StoreMarker.write(storeName: StoreMarker.parse(current).storeName, into: userNotes)
            }
        }
    }

    /// Checks an item off – or, within the undo window, back on (KONZEPT §7.2).
    /// The EventKit write happens immediately so household members see it in real time.
    func toggleCompletion(_ item: ShoppingItem) async {
        if !isUndoing { lastUndoAction = .completion(item) }
        if pendingCompletions.contains(item.id) {
            cancelPendingCompletion(of: item.id)
            if let storeID = item.storeID {
                sessionTracker.remove(itemKey: ItemKeyNormalizer.matchingKey(for: item.title), storeID: storeID)
                saveSessionTracker()
            }
            trip?.recordReopening(of: item.id)
            await perform { try await $0.setCompleted(false, reminder: item.id) }
            return
        }

        pendingCompletions.insert(item.id)
        update(item.id) {
            $0.isCompleted = true
            $0.completionDate = .now
        }
        defaults.set(Date.now, forKey: Keys.lastShoppingActivity)
        recordTripCompletion(of: item)
        completionTasks[item.id] = Task { [weak self] in
            try? await Task.sleep(for: Self.completionUndoWindow)
            guard !Task.isCancelled else { return }
            self?.finishCompletion(of: item.id)
        }
        do {
            try await gateway.setCompleted(true, reminder: item.id)
        } catch {
            // Not completed in Reminders: the item must not vanish when the undo window ends.
            cancelPendingCompletion(of: item.id)
            present(error)
            await reload()
        }
    }

    /// "Nochmal kaufen" from the completed section.
    func restore(_ item: ShoppingItem) async {
        recentlyCompleted.removeAll { $0.id == item.id }
        trip?.recordReopening(of: item.id)
        var reopened = item
        reopened.isCompleted = false
        reopened.completionDate = nil
        items.append(reopened)
        await perform { try await $0.setCompleted(false, reminder: item.id) }
    }

    func delete(_ item: ShoppingItem) async {
        if !isUndoing { lastUndoAction = .deletion(item) }
        items.removeAll { $0.id == item.id }
        await perform { try await $0.deleteReminder(id: item.id) }
    }

    func undoLastAction() async {
        guard let action = lastUndoAction else { return }
        lastUndoAction = nil
        isUndoing = true
        defer { isUndoing = false }
        switch action {
        case .completion(let before):
            if let current = items.first(where: { $0.id == before.id }), current.isCompleted != before.isCompleted {
                await toggleCompletion(current)
            } else if let current = recentlyCompleted.first(where: { $0.id == before.id }), !before.isCompleted {
                await restore(current)
            }
        case .assignment(let before):
            if let current = items.first(where: { $0.id == before.id }) {
                await assign(current, to: before.storeID.flatMap(store(_:)), learn: false)
            }
        case .rename(let before):
            if let current = items.first(where: { $0.id == before.id }) {
                await rename(current, to: before.title)
            }
        case .deletion(let before):
            guard let listID = selectedListID else { return }
            let notes = StoreMarker.write(storeName: before.storeID.flatMap(store(_:))?.name, into: before.userNotes)
            await perform { _ = try await $0.createReminder(title: before.title, notes: notes, in: listID) }
            await reload()
        case .creation(let created):
            if let current = items.first(where: { $0.id == created.id }) {
                await delete(current)
            }
        case .creations(let created):
            for item in created {
                if let current = items.first(where: { $0.id == item.id }) { await delete(current) }
            }
        case .stores(let previous, let page):
            for old in previous {
                guard let index = stores.firstIndex(where: { $0.id == old.id }) else { continue }
                let renamed = stores[index].name != old.name
                stores[index] = old
                persist(old)
                if renamed {
                    for item in items where item.storeID == old.id {
                        await perform { try await $0.setStore(named: old.name, forReminder: item.id) }
                    }
                }
            }
            dismissedPages = []
            activePage = page
            pageRequest = page
        }
    }

    func recordStoresUndo() {
        if !isUndoing { lastUndoAction = .stores(stores, activePage) }
    }

    func loadRecentlyCompleted() async {
        guard let listID = selectedListID else { return }
        do {
            let since = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
            let matcher = StoreMatcher(stores: stores)
            let fetched = try await gateway.completedReminders(in: listID, since: since)
                .map { ShoppingItemMapper.item(from: $0, matcher: matcher) }
            guard selectedListID == listID else { return }
            var merged = fetched
            let fetchedIDs = Set(fetched.map(\.id))
            merged += recentlyCompleted.filter {
                !fetchedIDs.contains($0.id) && ($0.completionDate ?? .distantPast) >= since
            }
            recentlyCompleted = merged.sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
        } catch {
            present(error)
        }
    }

    // MARK: Composer

    /// Opens the composer on `page`. A hidden store becomes planned so its card appears.
    /// Opens a card full screen – not while typing, and not the "Weitere Läden" card.
    func focus(_ page: PageID) {
        guard hasLoadedItems, page != .more, composerTarget == nil, editingItemID == nil, focusedPage == nil else { return }
        dismissBriefing()
        activePage = page
        focusedPage = page
    }

    func startComposer(on page: PageID) {
        editingItemID = nil
        dismissBriefing()
        var page = page
        if page == .more { page = .unsorted }
        if let id = page.storeID { plan(id) }
        // Full screen shows the target card, so new items never land on a card out of sight.
        if focusedPage != nil, focusedPage != page { focusedPage = page }
        composerTarget = page
        activePage = page
        pageRequest = page
    }

    func endComposer() {
        let text = composerText
        composerText = ""
        let target = composerTarget
        composerTarget = nil
        if let target, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            Task { await addItem(title: text, to: target) }
        }
    }

    // MARK: Shared helpers (used by the feature extensions)

    var nextSortIndex: Int {
        (stores.map(\.sortIndex).max() ?? -1) + 1
    }

    func persist(_ store: Store) {
        do {
            try storeRepository.save(store)
        } catch {
            present(error)
        }
    }

    func update(_ id: ShoppingItem.ID, _ change: (inout ShoppingItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    /// Runs a write; on failure shows the error and reloads the truth from Reminders.
    func perform(_ write: (any ReminderGateway) async throws -> Void) async {
        do {
            try await write(gateway)
        } catch {
            present(error)
            await reload()
        }
    }

    func present(_ error: any Error) {
        errorMessage = error.localizedDescription
    }

    func saveSessionTracker() {
        defaults.set(try? JSONEncoder().encode(sessionTracker), forKey: Keys.sessionTracker)
    }

    // MARK: Private

    private func apply(_ snapshots: [ReminderSnapshot]) {
        var mapped = snapshots.map { ShoppingItemMapper.item(from: $0, matcher: StoreMatcher(stores: stores)) }

        // Markers naming unknown stores (e.g. from a shared list): catalog chain or neutral store.
        let created = DetectedStoreFactory.makeStores(
            forUnresolved: mapped.compactMap(\.unresolvedStoreName),
            existing: stores,
            catalog: catalog?.stores ?? []
        )
        if !created.isEmpty {
            stores += created
            do {
                try storeRepository.save(created)
            } catch {
                present(error)
            }
            let matcher = StoreMatcher(stores: stores)
            mapped = snapshots.map { ShoppingItemMapper.item(from: $0, matcher: matcher) }
        }

        // Items inside their undo window are already completed in Reminders – keep showing them.
        let fetchedIDs = Set(mapped.map(\.id))
        let pending = items.filter { pendingCompletions.contains($0.id) && !fetchedIDs.contains($0.id) }
        items = mapped + pending
    }

    private func cancelPendingCompletion(of id: ShoppingItem.ID) {
        pendingCompletions.remove(id)
        completionTasks.removeValue(forKey: id)?.cancel()
        update(id) {
            $0.isCompleted = false
            $0.completionDate = nil
        }
    }

    private func finishCompletion(of id: ShoppingItem.ID) {
        completionTasks[id] = nil
        guard pendingCompletions.remove(id) != nil, let item = items.first(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        recentlyCompleted.insert(item, at: 0)
        if let storeID = item.storeID {
            recordCheckOff(of: item, in: storeID)
            if !items.contains(where: { $0.storeID == storeID }) {
                emptiedInSession.insert(storeID)
            }
        }
    }

    /// After 30 minutes without checking anything off, "shopped empty" cards leave (KONZEPT §7.2).
    private func endShoppingSessionIfExpired() {
        guard !emptiedInSession.isEmpty else { return }
        let last = defaults.object(forKey: Keys.lastShoppingActivity) as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(last) > Self.sessionTimeout else { return }
        for id in emptiedInSession {
            guard let index = stores.firstIndex(where: { $0.id == id }) else { continue }
            stores[index].plannedAt = nil
            persist(stores[index])
        }
        emptiedInSession = []
    }

    private func observeChanges() {
        guard changeObservation == nil else { return }
        changeObservation = Task { [weak self, gateway] in
            for await _ in await gateway.changes() {
                self?.scheduleReload()
            }
        }
    }

    /// Debounces bursts of `EKEventStoreChanged` (e.g. our own writes, iCloud sync).
    private func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    enum Keys {
        static let selectedListID = "selectedCalendarID"
        static let emptiedInSession = "emptiedInSession"
        static let lastShoppingActivity = "lastShoppingActivity"
        static let onboarding = "hasCompletedOnboarding"
        static let isPro = "proEntitlementCache"
        static let developerProOverride = "developerProOverride"
        static let autoAssign = "autoAssignEnabled"
        static let intelligence = "intelligenceEnabled"
        static let routeLearning = "routeLearningEnabled"
        static let triageMode = "triageMode"
        static let storeSortMode = "storeSortMode"
        static let travelMode = "travelMode"
        static let sessionTracker = "routeSessionTracker"
        static let autoStartsTrip = "autoStartsTrip"
        static let followsPresence = "followsPresence"
        static let arrivalAlerts = "arrivalAlertsEnabled"
    }
}

extension AppModel {
    /// A realistic weekly shop across several stores.
    static func demo(isPro: Bool = false) -> AppModel {
        let demoItems: [(title: String, notes: String?)] = [
            ("Bananen", "🛒 Aldi Süd"), ("Milch", "laktosefrei\n🛒 Aldi Süd"), ("Vollkornbrot", "🛒 Aldi Süd"),
            ("Butter", "🛒 Aldi Süd"), ("Eier", "🛒 Aldi Süd"), ("Kaffee", "🛒 Aldi Süd"), ("Tiefkühlpizza", "🛒 Aldi Süd"),
            ("Gouda", "🛒 Aldi Süd"), ("Zucchini", "🛒 Aldi Süd"),
            ("Zahnpasta", "🛒 dm"), ("Duschgel", "🛒 dm"), ("Sonnencreme", "LSF 50\n🛒 dm"),
            ("Erdbeeren", "🛒 Markt"), ("Spargel", "🛒 Markt"),
            ("Frischkäse", "🛒 Rewe"), ("Joghurt", "🛒 Rewe"),
            ("Batterien AA", nil), ("Geschenkpapier", nil), ("Hafermilch", nil),
        ]
        let model = preview(
            items: ProcessInfo.processInfo.arguments.contains("-demo-empty-unsorted")
                ? demoItems.filter { $0.notes != nil } : demoItems,
            stores: ["rewe", "aldi-sued", "dm", "generic-market"]
        )
        model.hasCompletedOnboarding = true
        model.isPro = isPro
        // Earlier shops taught Marqet where oat milk goes.
        if let rewe = model.stores.first(where: { $0.catalogKey == "rewe" }) {
            for _ in 0..<2 { model.assignmentMemory.record(itemKey: "hafermilch", storeID: rewe.id) }
        }
        // Branches in Munich's old town, about 900 m apart: for the map and for arrival checks
        // with `xcrun simctl location booted set 48.1321,11.5648` (Aldi Süd).
        let branches: [(key: String, name: String, latitude: Double, longitude: Double)] = [
            ("aldi-sued", "Aldi Süd Sendlinger Tor", 48.13210, 11.56480),
            ("rewe", "REWE Viktualienmarkt", 48.13510, 11.57640),
            ("dm", "dm Karlsplatz", 48.13870, 11.56760),
        ]
        for branch in branches {
            guard let store = model.stores.first(where: { $0.catalogKey == branch.key }) else { continue }
            model.locations.append(StoreLocation(storeID: store.id, name: branch.name,
                                                 coordinate: GeoPoint(latitude: branch.latitude, longitude: branch.longitude),
                                                 isPreferred: true))
        }
        return model
    }

    /// Model with in-memory Reminders, stores and settings, for previews and the demo.
    static func preview(items: [(title: String, notes: String?)] = [], stores storeKeys: [String] = []) -> AppModel {
        let gateway = InMemoryReminderGateway()
        let model = AppModel(
            gateway: gateway,
            // An in-memory container only fails on a broken model definition – a programmer error.
            container: try! PersistenceContainer.make(inMemory: true),
            intelligence: FoundationModelsService(),
            defaults: UserDefaults(suiteName: "preview-\(UUID().uuidString)") ?? .standard
        )
        for key in storeKeys {
            if let entry = model.catalog?.entry(forKey: key) { model.addStore(from: entry) }
        }
        Task {
            let list = await gateway.seed(listTitle: "Einkaufen", reminders: items)
            await model.selectList(list.id)
        }
        return model
    }
}
