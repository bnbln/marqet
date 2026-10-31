import Foundation
import MarqetCore
import MarqetPersistence
import MarqetReminders
import Testing
@testable import Marqet

/// At the store (KONZEPT-WIDGETS §13): the right list, arrivals and the trip on the way.
@Suite("Am Laden", .serialized)
@MainActor
struct PresenceModelTests {
    let gateway = InMemoryReminderGateway()
    let places = FakePlaceSearch()

    static let aldiBranch = GeoPoint(latitude: 48.13210, longitude: 11.56480)
    static let dmBranch = GeoPoint(latitude: 48.13870, longitude: 11.56760)
    /// Inside the Aldi circle, about 30 m from the entrance.
    static let atAldi = GeoPoint(latitude: 48.13235, longitude: 11.56490)
    static let home = GeoPoint(latitude: 48.1374, longitude: 11.5755)

    func makeModel(at position: GeoPoint = home) async throws -> AppModel {
        let model = AppModel(
            gateway: gateway,
            container: try PersistenceContainer.make(inMemory: true),
            intelligence: UnavailableIntelligence(),
            defaults: try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)")),
            location: FakeLocation(location: position),
            placeSearch: places
        )
        model.hasCompletedOnboarding = true
        model.isInForeground = true
        let list = await gateway.seed(listTitle: "Einkaufen", reminders: [
            ("Milch", "🛒 Aldi Süd"), ("Bananen", "🛒 Aldi Süd"), ("Zahnpasta", "🛒 dm"),
        ])
        await model.selectList(list.id)
        for (name, point) in [("Aldi Süd", Self.aldiBranch), ("dm", Self.dmBranch)] {
            let store = try #require(model.stores.first { $0.name == name })
            model.locations.append(StoreLocation(storeID: store.id, name: name, coordinate: point, isPreferred: true))
        }
        return model
    }

    func store(_ model: AppModel, _ name: String) throws -> Store {
        try #require(model.stores.first { $0.name == name })
    }

    @Test func openingTheAppAtAStoreShowsItsList() async throws {
        let model = try await makeModel(at: Self.atAldi)
        let aldi = try store(model, "Aldi Süd")
        await model.detectPresence()
        #expect(model.presence?.storeID == aldi.id)
        #expect(model.presence?.source == .location)
        #expect(model.pageRequest == .store(aldi.id))
        #expect(model.makeWidgetSnapshot().automaticPage?.store?.id == aldi.id)
    }

    @Test func atHomeNothingJumps() async throws {
        let model = try await makeModel()
        await model.detectPresence()
        #expect(model.presence == nil)
        #expect(model.pageRequest == nil)
    }

    @Test func switchedOffTheListStaysWhereItWas() async throws {
        let model = try await makeModel(at: Self.atAldi)
        model.followsPresence = false
        await model.detectPresence()
        #expect(model.presence == nil)
    }

    @Test func aBranchFoundOnTheMapCountsToo() async throws {
        let model = try await makeModel(at: GeoPoint(latitude: 48.1500, longitude: 11.5800))
        model.locations = []
        places.places = [PlaceResult(name: "ALDI SÜD", address: nil, coordinate: GeoPoint(latitude: 48.1501, longitude: 11.5801),
                                     mapItemIdentifier: "aldi-nord-branch", suggestedType: .discounter)]
        await model.detectPresence()
        #expect(model.presence?.storeID == (try store(model, "Aldi Süd")).id)
    }

    @Test func theJumpNeverInterruptsTyping() async throws {
        let model = try await makeModel(at: Self.atAldi)
        model.startComposer(on: .unsorted)
        model.pageRequest = nil
        await model.detectPresence()
        #expect(model.presence != nil)
        #expect(model.composerTarget == .unsorted)
        #expect(model.pageRequest == nil)
    }

    @Test func arrivalMovesTheRunningTripAndMarksItArrived() async throws {
        let model = try await makeModel()
        let aldi = try store(model, "Aldi Süd")
        let dm = try store(model, "dm")
        model.arrivalAlertsEnabled = true
        await model.startTrip(at: dm.id)
        #expect(model.trip?.isOnTheWay == true)
        await model.arrive(at: Geofence(storeID: aldi.id, center: Self.aldiBranch), source: .geofence)
        #expect(model.trip?.storeID == aldi.id)
        #expect(model.trip?.isOnTheWay == false)
        #expect(model.presence?.source == .geofence)
    }

    @Test func withoutArrivalAlertsAStartedTripIsAtTheStore() async throws {
        let model = try await makeModel()
        await model.startTrip(at: try store(model, "dm").id)
        #expect(model.trip?.isOnTheWay == false)
    }

    @Test func leavingEndsThePresence() async throws {
        let model = try await makeModel()
        let aldi = try store(model, "Aldi Süd")
        let fence = Geofence(storeID: aldi.id, center: Self.aldiBranch)
        await model.arrive(at: fence, source: .geofence)
        await model.leave(Geofence(storeID: try store(model, "dm").id, center: Self.dmBranch))
        #expect(model.presence?.storeID == aldi.id)
        await model.leave(fence)
        #expect(model.presence == nil)
    }

    @Test func arrivalSummaryListsTheFirstItemsInWalkingOrder() async throws {
        let model = try await makeModel()
        let summary = model.arrivalSummary(for: try store(model, "Aldi Süd"))
        #expect(summary.hasPrefix("2 Einträge: "))
        #expect(summary.contains("Milch") && summary.contains("Bananen"))
    }

    @Test func onlyStoresWorthAStopAreWatched() async throws {
        let model = try await makeModel()
        let lidl = model.addStore(from: try #require(model.catalog?.entry(forKey: "lidl")), planned: false)
        #expect(!model.storesWorthAStop.contains(lidl.id))
        model.pin(lidl.id)
        #expect(model.storesWorthAStop.contains(lidl.id))
        #expect(model.storesWorthAStop.contains(try store(model, "dm").id))
    }
}
