import Foundation
import MarqetCore
import Testing

@Suite("Am Laden – Geofences, Anwesenheit, Unterwegs (KONZEPT-WIDGETS §13)")
struct StorePresenceTests {
    static func store(_ name: String, sortIndex: Int) -> Store {
        Store(name: name, colorHex: "#C8323C", symbol: .monogram(String(name.prefix(1))), sortIndex: sortIndex,
              origin: .catalog, type: .supermarket)
    }

    let aldi = store("Aldi", sortIndex: 0)
    let dm = store("dm", sortIndex: 1)
    let lidl = store("Lidl", sortIndex: 2)

    let home = GeoPoint(latitude: 48.1351, longitude: 11.5820)
    let aldiBranch = GeoPoint(latitude: 48.1345, longitude: 11.5690)   // ≈ 1 km west
    let aldiFar = GeoPoint(latitude: 48.1800, longitude: 11.5800)      // ≈ 5 km north
    let dmBranch = GeoPoint(latitude: 48.1372, longitude: 11.5738)     // ≈ 650 m

    // MARK: Planner

    @Test func watchesOnlyStoresWorthAStopNearestFirst() {
        let fences = GeofencePlanner.geofences(
            branches: [
                BranchCandidate(storeID: aldi.id, coordinate: aldiFar),
                BranchCandidate(storeID: lidl.id, coordinate: home),
                BranchCandidate(storeID: aldi.id, coordinate: aldiBranch),
                BranchCandidate(storeID: dm.id, coordinate: dmBranch),
            ],
            relevantStores: [aldi.id, dm.id],
            near: home
        )
        #expect(fences.map(\.center) == [dmBranch, aldiBranch, aldiFar])
        #expect(!fences.contains { $0.storeID == lidl.id })
    }

    @Test func respectsTheSystemLimitAndMergesTheSameBuilding() {
        var branches = (0..<30).map { index in
            BranchCandidate(storeID: aldi.id, coordinate: GeoPoint(latitude: 48 + Double(index) * 0.01, longitude: 11.5))
        }
        branches.append(BranchCandidate(storeID: aldi.id, coordinate: GeoPoint(latitude: 48.00005, longitude: 11.5)))
        let fences = GeofencePlanner.geofences(branches: branches, relevantStores: [aldi.id], near: nil)
        #expect(fences.count == GeofencePlanner.maximumRegions)
        #expect(Set(fences.map(\.id)).count == fences.count)
    }

    @Test func identifierSurvivesARelaunch() throws {
        let fence = Geofence(storeID: aldi.id, center: aldiBranch)
        let restored = try #require(Geofence(identifier: fence.id))
        #expect(restored.storeID == aldi.id)
        #expect(restored.center.distance(to: aldiBranch) < 1)
        #expect(Geofence(identifier: "kaputt") == nil)
    }

    @Test func positionInsideACircleFindsTheNearestBranch() {
        let fences = [Geofence(storeID: aldi.id, center: aldiBranch), Geofence(storeID: dm.id, center: dmBranch)]
        let atAldi = GeoPoint(latitude: 48.1350, longitude: 11.5692)
        #expect(GeofencePlanner.geofence(containing: atAldi, in: fences)?.storeID == aldi.id)
        #expect(GeofencePlanner.geofence(containing: home, in: fences) == nil)
    }

    // MARK: The right list

    func snapshot(presence: StorePresence?, trip: ShoppingTrip? = nil, now: Date = .now) -> WidgetSnapshot {
        let items = [
            ShoppingItem(id: "milch", title: "Milch", storeRef: .known(aldi.id)),
            ShoppingItem(id: "zahnpasta", title: "Zahnpasta", storeRef: .known(dm.id)),
        ]
        let registry = WidgetRegistry(status: .ready, listID: "list", listTitle: "Einkaufen", stores: [aldi, dm],
                                      presence: presence)
        return WidgetSnapshotBuilder.snapshot(registry: registry, items: items, recentlyCompleted: [],
                                              classifier: CategoryClassifier(dictionary: CategoryDictionary(categories: [:])),
                                              trip: trip, now: now)
    }

    @Test func theStoreYouAreAtWinsOverCardOrderAndTrip() {
        let presence = StorePresence(storeID: dm.id, branch: dmBranch, source: .geofence)
        #expect(snapshot(presence: nil).automaticPage?.store?.id == aldi.id)
        #expect(snapshot(presence: presence).automaticPage?.store?.id == dm.id)
        #expect(snapshot(presence: presence, trip: ShoppingTrip(storeID: aldi.id)).automaticPage?.store?.id == dm.id)
    }

    @Test func oldPresenceIsIgnored() {
        let presence = StorePresence(storeID: dm.id, branch: dmBranch, since: Date(timeIntervalSince1970: 0), source: .geofence)
        #expect(snapshot(presence: presence).presence == nil)
        #expect(snapshot(presence: presence).automaticPage?.store?.id == aldi.id)
    }

    // MARK: Trip on the way

    @Test func tripStartedAtHomeIsOnTheWayUntilArrival() throws {
        var trip = ShoppingTrip(storeID: aldi.id, arrived: false)
        let before = try #require(TripStatus.make(snapshot: snapshot(presence: nil, trip: trip), trip: trip))
        #expect(before.isOnTheWay)
        trip.arrive(at: aldi.id)
        let after = try #require(TripStatus.make(snapshot: snapshot(presence: nil, trip: trip), trip: trip))
        #expect(!after.isOnTheWay)
    }

    @Test func arrivingAtAnotherStoreMovesTheTrip() {
        var trip = ShoppingTrip(storeID: aldi.id)
        trip.recordCompletion(of: "milch", in: aldi.id)
        trip.arrive(at: dm.id)
        #expect(trip.storeID == dm.id)
        #expect(trip.doneItemIDs.isEmpty)
        #expect(!trip.isOnTheWay)
    }

    @Test func nextStoreIsOnTheWayAndCheckingOffCountsAsArrival() {
        var trip = ShoppingTrip(storeID: aldi.id)
        trip.moveTo(dm.id, arrived: false)
        #expect(trip.isOnTheWay)
        trip.recordCompletion(of: "zahnpasta", in: dm.id)
        #expect(!trip.isOnTheWay)
    }

    @Test func presenceAtTheTripStoreMeansArrived() throws {
        let trip = ShoppingTrip(storeID: dm.id, arrived: false)
        let presence = StorePresence(storeID: dm.id, branch: dmBranch, source: .location)
        let status = try #require(TripStatus.make(snapshot: snapshot(presence: presence, trip: trip), trip: trip))
        #expect(!status.isOnTheWay)
    }
}
