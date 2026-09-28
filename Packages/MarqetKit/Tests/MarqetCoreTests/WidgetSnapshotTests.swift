import Foundation
import MarqetCore
import Testing

@Suite("Widgets – snapshot, trip and deep links (KONZEPT-WIDGETS)")
struct WidgetSnapshotTests {
    static func store(_ name: String, sortIndex: Int, type: StoreType = .supermarket, planned: Bool = false, key: String? = nil) -> Store {
        Store(catalogKey: key, name: name, colorHex: "#C8323C", symbol: .monogram(String(name.prefix(1))), sortIndex: sortIndex,
              origin: .catalog, type: type, plannedAt: planned ? Date(timeIntervalSince1970: 0) : nil)
    }

    static func item(_ title: String, _ store: Store?, created seconds: TimeInterval = 0, notes: String? = nil) -> ShoppingItem {
        ShoppingItem(id: title, title: title, userNotes: notes, storeRef: store.map { .known($0.id) },
                     creationDate: Date(timeIntervalSince1970: seconds))
    }

    let aldi = store("Aldi", sortIndex: 0, type: .discounter, key: "aldi-sued")
    let dm = store("dm", sortIndex: 1, type: .drugstore, key: "dm")
    let rewe = store("Rewe", sortIndex: 2, planned: true, key: "rewe")
    let lidl = store("Lidl", sortIndex: 3, key: "lidl")

    let classifier = CategoryClassifier(dictionary: CategoryDictionary(categories: [
        .produce: ["Bananen", "Zucchini"],
        .dairyEggs: ["Milch", "Eier"],
        .frozen: ["Pizza"],
        .personalCare: ["Zahnpasta"],
    ]))

    func registry(storeOrder: [Store.ID]? = nil, assignments: [String: [String: Int]] = [:]) -> WidgetRegistry {
        WidgetRegistry(
            status: .ready,
            listID: "list",
            listTitle: "Einkaufen",
            stores: [lidl, rewe, dm, aldi],
            storeOrder: storeOrder,
            assignmentCounts: assignments,
            loyaltyCards: [
                LoyaltyCard(name: "Payback", payload: "4006381333931", symbology: .ean13, colorHex: "#0046AA",
                            storeIDs: [dm.id, rewe.id], createdAt: Date(timeIntervalSince1970: 1)),
            ],
            brochureSources: [
                .init(key: "lidl", name: "Lidl", colorHex: "#0050AA", symbol: .monogram("L"), url: URL(string: "https://lidl.de")!),
                .init(key: "dm", name: "dm", colorHex: "#E4003A", symbol: .monogram("dm"), url: URL(string: "https://dm.de")!),
                .init(key: "aldi-sued", name: "Aldi Süd", colorHex: "#00005F", symbol: .monogram("A"), url: URL(string: "https://aldi-sued.de")!),
                .init(key: "penny", name: "Penny", colorHex: "#CD1414", symbol: .monogram("P"), url: URL(string: "https://penny.de")!,
                      distanceMeters: 400),
            ]
        )
    }

    var items: [ShoppingItem] {
        [
            Self.item("Pizza", aldi, created: 1),
            Self.item("Milch", aldi, created: 2, notes: "laktosefrei"),
            Self.item("Bananen", aldi, created: 3),
            Self.item("Zahnpasta", dm, created: 4),
            Self.item("Hafermilch", nil, created: 5),
        ]
    }

    func snapshot(registry: WidgetRegistry? = nil, items: [ShoppingItem]? = nil, trip: ShoppingTrip? = nil) -> WidgetSnapshot {
        WidgetSnapshotBuilder.snapshot(registry: registry ?? self.registry(), items: items ?? self.items,
                                       recentlyCompleted: [], classifier: classifier, trip: trip,
                                       now: Date(timeIntervalSince1970: 100))
    }

    // MARK: Snapshot

    @Test func pagesAreInboxThenCardsInCardOrder() {
        let snapshot = snapshot()
        #expect(snapshot.pages.map { $0.store?.name ?? "Inbox" } == ["Inbox", "Aldi", "dm", "Rewe"])
        #expect(snapshot.totalOpenCount == 5)
        #expect(snapshot.storeOpenCount == 4)
    }

    @Test func groceryItemsFollowTheWalkingOrderWithSections() {
        let aldiPage = snapshot().page(forStore: aldi.id)
        #expect(aldiPage?.sections.map(\.category) == [.produce, .dairyEggs, .frozen])
        #expect(aldiPage?.items.map(\.title) == ["Bananen", "Milch", "Pizza"])
        #expect(aldiPage?.items.first { $0.title == "Milch" }?.note == "laktosefrei")
    }

    @Test func nonGroceryStoresStayFlat() {
        #expect(snapshot().page(forStore: dm.id)?.sections.map(\.category) == [nil])
    }

    @Test func storeOrderFromDistanceSortingIsKept() {
        let snapshot = snapshot(registry: registry(storeOrder: [dm.id, aldi.id]))
        #expect(snapshot.storePages.map(\.store?.name) == ["dm", "Aldi", "Rewe"])
    }

    @Test func inboxItemsCarryLearnedSuggestions() {
        let snapshot = snapshot(registry: registry(assignments: ["hafermilch": [rewe.id.uuidString: 2]]))
        let suggestion = snapshot.inbox?.items.first?.suggestion
        #expect(suggestion?.storeID == rewe.id)
        #expect(suggestion?.storeName == "Rewe")
    }

    @Test func hiddenStoresGetAnEmptyPageForWidgets() {
        let snapshot = snapshot()
        #expect(snapshot.storePages.contains { $0.store?.id == lidl.id } == false)
        #expect(snapshot.page(forStore: lidl.id)?.openCount == 0)
        #expect(snapshot.stores.map(\.name) == ["Aldi", "dm", "Rewe", "Lidl"])
    }

    @Test func notReadyGivesSetupSnapshot() {
        var registry = registry()
        registry.status = .needsSetup
        #expect(snapshot(registry: registry).status == .needsSetup)
        #expect(snapshot(registry: registry).pages.isEmpty)
    }

    @Test func snapshotRoundTripsThroughJSON() throws {
        let original = snapshot(trip: ShoppingTrip(storeID: aldi.id, startedAt: Date(timeIntervalSince1970: 50)))
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: data) == original)
    }

    @Test func brochuresPutOwnStoresWithItemsFirst() {
        let keys = snapshot().brochures.map(\.key)
        #expect(keys == ["aldi-sued", "dm", "lidl", "penny"])
    }

    // MARK: Automatic choices

    @Test func automaticPageIsFirstStoreWithItems() {
        #expect(snapshot().automaticPage?.store?.id == aldi.id)
    }

    @Test func automaticPagePrefersTheRunningTrip() {
        let snapshot = snapshot(trip: ShoppingTrip(storeID: dm.id))
        #expect(snapshot.automaticPage?.store?.id == dm.id)
    }

    @Test func automaticPageFallsBackToInboxThenPlannedStore() {
        #expect(snapshot(items: [Self.item("Batterien", nil)]).automaticPage?.isInbox == true)
        #expect(snapshot(items: []).automaticPage?.store?.id == rewe.id)
    }

    @Test func automaticLoyaltyCardFollowsTheTripStore() {
        #expect(snapshot().automaticLoyaltyCard?.name == "Payback")
        #expect(snapshot(trip: ShoppingTrip(storeID: dm.id)).automaticLoyaltyCard?.storeIDs.contains(dm.id) == true)
    }

    // MARK: Trip

    @Test func tripStatusShowsNextItemsAndStops() throws {
        var trip = ShoppingTrip(storeID: aldi.id)
        trip.recordCompletion(of: "Eier", in: aldi.id)
        let status = try #require(TripStatus.make(snapshot: snapshot(trip: trip), trip: trip))
        #expect(status.next.map(\.title) == ["Bananen", "Milch", "Pizza"])
        #expect(status.openCount == 3)
        #expect(status.doneCount == 1)
        #expect(status.progress == 0.25)
        #expect(status.stops.map(\.name) == ["dm"])
        #expect(status.hasLoyaltyCard == false)
        #expect(!status.isFinished)
    }

    @Test func checkingOffElsewhereMovesTheTrip() {
        var trip = ShoppingTrip(storeID: aldi.id, startedAt: Date(timeIntervalSince1970: 0))
        trip.recordCompletion(of: "Milch", in: aldi.id, at: Date(timeIntervalSince1970: 10))
        trip.recordCompletion(of: "Zahnpasta", in: dm.id, at: Date(timeIntervalSince1970: 20))
        #expect(trip.storeID == dm.id)
        #expect(trip.doneItemIDs == ["Zahnpasta"])
        #expect(trip.storeStartedAt == Date(timeIntervalSince1970: 20))
        trip.recordReopening(of: "Zahnpasta")
        #expect(trip.doneItemIDs.isEmpty)
    }

    @Test func tripExpiresAfterThirtyMinutesWithoutCheckingOff() {
        let trip = ShoppingTrip(storeID: aldi.id, startedAt: Date(timeIntervalSince1970: 0))
        #expect(!trip.isExpired(at: Date(timeIntervalSince1970: 29 * 60)))
        #expect(trip.isExpired(at: Date(timeIntervalSince1970: 31 * 60)))
    }

    @Test func tripIsFinishedWhenNothingIsLeft() throws {
        let trip = ShoppingTrip(storeID: aldi.id)
        let status = try #require(TripStatus.make(snapshot: snapshot(items: [], trip: trip), trip: trip))
        #expect(status.isStoreDone)
        #expect(status.isFinished)
    }

    @Test func tripStatusStaysSmall() throws {
        let many = (0..<60).map { Self.item("Eintrag mit einem recht langen Namen \($0)", aldi, created: Double($0)) }
        let trip = ShoppingTrip(storeID: aldi.id)
        let status = try #require(TripStatus.make(snapshot: snapshot(items: many, trip: trip), trip: trip))
        #expect(try JSONEncoder().encode(status).count < 4096)
    }

    // MARK: Deep links

    @Test(arguments: [
        MarqetLink.home, .page(.unsorted), .page(.store(UUID())), .compose(.store(UUID())), .compose(.unsorted),
        .triage, .completed, .loyaltyCard(UUID()), .storeLoyaltyCards(UUID()), .offers, .offer(catalogKey: "aldi-sued"), .trip,
    ])
    func deepLinksRoundTrip(link: MarqetLink) {
        #expect(MarqetLink(url: link.url) == link)
    }

    @Test func foreignURLsAreIgnored() {
        #expect(MarqetLink(url: URL(string: "https://marqet.app/page/unsorted")!) == nil)
        #expect(MarqetLink(url: URL(string: "marqet://page/nonsense")!) == nil)
        #expect(MarqetLink(url: URL(string: "marqet://unknown")!) == nil)
    }
}
