import Foundation
import MarqetCore
import MarqetPersistence
import MarqetReminders
import SwiftData
import Testing
@testable import Marqet

@MainActor
final class FakeLocation: LocationProviding {
    var authorization: LocationAuthorization
    var grantsOnRequest: Bool
    var location: GeoPoint?

    init(authorization: LocationAuthorization = .authorized, grantsOnRequest: Bool = true, location: GeoPoint? = nil) {
        self.authorization = authorization
        self.grantsOnRequest = grantsOnRequest
        self.location = location
    }

    func requestAuthorization() async -> LocationAuthorization {
        if authorization == .notDetermined { authorization = grantsOnRequest ? .authorized : .denied }
        return authorization
    }

    func currentLocation() async -> GeoPoint? {
        authorization == .authorized ? location : nil
    }
}

@MainActor
final class FakePlaceSearch: PlaceSearching {
    var places: [PlaceResult] = []
    func branches(of store: Store, chain: StoreCatalog.Entry?, near origin: GeoPoint, radius: Double) async throws -> [PlaceResult] { places }
    func shops(near origin: GeoPoint) async throws -> [PlaceResult] { places }
    func search(_ query: String, near origin: GeoPoint?) async throws -> [PlaceResult] { places }
}

/// Marienplatz, Munich.
private let home = GeoPoint(latitude: 48.1374, longitude: 11.5755)

private func place(_ name: String, metersNorth: Double, id: String? = nil, type: StoreType = .supermarket) -> PlaceResult {
    PlaceResult(
        name: name,
        address: "\(name)straße 1",
        coordinate: GeoPoint(latitude: home.latitude + metersNorth / 111_320, longitude: home.longitude),
        mapItemIdentifier: id ?? "\(name)-\(metersNorth)",
        suggestedType: type
    )
}

@Suite("Orte", .serialized)
@MainActor
struct PlacesModelTests {
    let gateway = InMemoryReminderGateway()

    func makeModel(
        items: [(String, String?)] = [],
        location: FakeLocation = FakeLocation(location: home),
        container: ModelContainerBox? = nil
    ) async throws -> AppModel {
        let modelContainer = try container?.container ?? PersistenceContainer.make(inMemory: true)
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
        let model = AppModel(
            gateway: gateway,
            container: modelContainer,
            intelligence: UnavailableIntelligence(),
            defaults: defaults,
            location: location,
            placeSearch: FakePlaceSearch()
        )
        model.hasCompletedOnboarding = true
        let list = await gateway.seed(listTitle: "Einkaufen", reminders: items.map { ($0.0, $0.1) })
        await model.selectList(list.id)
        return model
    }

    @Test func placeOfChainBecomesCatalogStoreWithPreferredBranch() async throws {
        let model = try await makeModel()
        let store = try #require(model.addStore(from: place("REWE City", metersNorth: 300)))
        #expect(store.catalogKey == "rewe")
        #expect(model.locations(of: store.id).count == 1)
        #expect(model.relevantLocation(of: store.id)?.isPreferred == true)
        #expect(model.store(store.id)?.address == "REWE Citystraße 1")
    }

    @Test func secondBranchOfSameChainJoinsExistingStore() async throws {
        let model = try await makeModel()
        let first = try #require(model.addStore(from: place("REWE", metersNorth: 300)))
        let second = try #require(model.addStore(from: place("REWE Center", metersNorth: 900)))
        #expect(first.id == second.id)
        #expect(model.stores.count(where: { $0.catalogKey == "rewe" }) == 1)
        let branches = model.locations(of: first.id)
        #expect(branches.count == 2)
        // The newest choice becomes preferred, only one at a time.
        #expect(branches.count(where: \.isPreferred) == 1)
        #expect(branches.first(where: \.isPreferred)?.name == "REWE Center")
    }

    @Test func unknownPlaceBecomesOwnStore() async throws {
        let model = try await makeModel()
        let store = try #require(model.addStore(from: place("Hofladen Maier", metersNorth: 500, type: .bakery)))
        #expect(store.catalogKey == nil)
        #expect(store.name == "Hofladen Maier")
        #expect(store.type == .bakery)
    }

    @Test func sameMapItemTwiceIsNotDuplicated() async throws {
        let model = try await makeModel()
        let store = try #require(model.addStore(from: place("Edeka", metersNorth: 200, id: "edeka-1")))
        model.addLocation(place("Edeka", metersNorth: 200, id: "edeka-1"), to: store.id)
        #expect(model.locations(of: store.id).count == 1)
    }

    @Test func distanceOrderPutsNearestStoreFirstButUnsortedStaysFirst() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Rewe"), ("Brot", "🛒 Edeka"), ("Apfel", nil)])
        let rewe = try #require(model.stores.first { $0.catalogKey == "rewe" })
        let edeka = try #require(model.stores.first { $0.catalogKey == "edeka" })
        model.addLocation(place("REWE", metersNorth: 3_000), to: rewe.id)
        model.addLocation(place("EDEKA", metersNorth: 400), to: edeka.id)

        await model.setStoreSortMode(.distance)
        #expect(model.storeSortMode == .distance)
        let stores = model.deck.pages.compactMap { if case .store(let id) = $0 { id } else { nil } }
        #expect(Array(model.deck.pages.prefix(2)) == [.brochures, .unsorted])
        #expect(Array(stores.prefix(2)) == [edeka.id, rewe.id])
        #expect(model.distanceText(to: edeka.id) != nil)

        await model.setStoreSortMode(.manual)
        #expect(model.storeOrderSnapshot == nil)
    }

    @Test func smartOrderWeighsOpenItemsAgainstTravelTime() async throws {
        let model = try await makeModel(items: [
            ("Milch", "🛒 Rewe"), ("Butter", "🛒 Rewe"), ("Käse", "🛒 Rewe"), ("Eier", "🛒 Rewe"),
            ("Brot", "🛒 Edeka"),
        ])
        let rewe = try #require(model.stores.first { $0.catalogKey == "rewe" })
        let edeka = try #require(model.stores.first { $0.catalogKey == "edeka" })
        // Rewe a bit further away, but four items instead of one.
        model.addLocation(place("REWE", metersNorth: 1_500), to: rewe.id)
        model.addLocation(place("EDEKA", metersNorth: 800), to: edeka.id)

        await model.setStoreSortMode(.smart)
        let stores = model.deck.pages.compactMap { if case .store(let id) = $0 { id } else { nil } }
        #expect(Array(stores.prefix(2)) == [rewe.id, edeka.id])
    }

    @Test func deniedLocationKeepsManualOrder() async throws {
        let model = try await makeModel(location: FakeLocation(authorization: .notDetermined, grantsOnRequest: false))
        await model.setStoreSortMode(.distance)
        #expect(model.storeSortMode == .manual)
        #expect(model.storeOrderSnapshot == nil)
    }

    @Test func removingPreferredBranchPromotesAnother() async throws {
        let model = try await makeModel()
        let store = try #require(model.addStore(from: place("Aldi Süd", metersNorth: 300)))
        model.addLocation(place("ALDI SÜD", metersNorth: 700), to: store.id)
        let preferred = try #require(model.locations(of: store.id).first { $0.isPreferred })
        model.removeLocation(preferred)
        #expect(model.locations(of: store.id).count == 1)
        #expect(model.locations(of: store.id).first?.isPreferred == true)
    }

    @Test func deletingStoreDeletesItsBranches() async throws {
        let model = try await makeModel()
        let store = try #require(model.addStore(from: place("dm", metersNorth: 300, type: .pharmacy)))
        await model.deleteStore(store.id)
        #expect(model.locations.isEmpty)
        #expect(try model.locationRepository.all().isEmpty)
    }

    @Test func branchesOfOwnStoresShowWithoutBeingSaved() async throws {
        // The bug from the device: Rewe was an own store without a saved branch – the map showed nothing.
        let model = try await makeModel(items: [("Milch", "🛒 Rewe")])
        let rewe = try #require(model.stores.first { $0.catalogKey == "rewe" })
        let pins = model.mapPins(found: [
            place("REWE City", metersNorth: 300),
            place("REWE", metersNorth: 900),
            place("EDEKA Ernst", metersNorth: 500),
            place("Bäckerei Hofpfisterei", metersNorth: 200),
        ])
        let branches = pins.filter { if case .branch = $0.kind { true } else { false } }
        #expect(branches.count == 2)
        #expect(branches.allSatisfy { $0.store?.id == rewe.id })
        #expect(pins.contains { if case .suggestion(_, "edeka") = $0.kind { true } else { false } })
        #expect(pins.count == 3)   // no pin for the bakery
    }

    @Test func savedBranchIsShownOnce() async throws {
        let model = try await makeModel()
        let rewe = place("REWE", metersNorth: 300, id: "rewe-1")
        let store = try #require(model.addStore(from: rewe))
        let pins = model.mapPins(found: [rewe, place("REWE", metersNorth: 310, id: "rewe-1-duplicate")])
        #expect(pins.count == 1)
        #expect(pins.first?.store?.id == store.id)
        #expect(pins.first.map { if case .saved = $0.kind { true } else { false } } == true)
    }

    @Test func branchSearchSkipsGenericKindsAndStoresWithoutItems() async throws {
        let model = try await makeModel(items: [("Brot", "🛒 Edeka")])
        _ = model.addStore(from: try #require(model.catalog?.entry(forKey: "generic-bakery")), planned: false)
        _ = model.addStore(from: try #require(model.catalog?.entry(forKey: "rewe")), planned: false)
        let stores = model.storesForBranchSearch()
        #expect(stores.first?.catalogKey == "edeka")
        #expect(!stores.contains { $0.catalogKey == "generic-bakery" })
        // Only stores with open items: an empty Rewe card needs no branch right now.
        #expect(!stores.contains { $0.catalogKey == "rewe" })
    }

    @Test func budniIsRecognizedAsChain() async throws {
        let model = try await makeModel()
        let store = try #require(model.addStore(from: place("BUDNI", metersNorth: 300, type: .other)))
        #expect(store.catalogKey == "budni")
        #expect(model.catalog?.entry(forKey: "budni")?.leafletURL != nil)
    }

    @Test func focusOpensStoreCardsButNotWhileTyping() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Rewe")])
        let rewe = try #require(model.stores.first { $0.catalogKey == "rewe" })
        model.focus(.more)
        #expect(model.focusedPage == nil)
        model.startComposer(on: .store(rewe.id))
        model.focus(.store(rewe.id))
        #expect(model.focusedPage == nil)
        model.endComposer()
        model.focus(.store(rewe.id))
        #expect(model.focusedPage == .store(rewe.id))
        #expect(model.activePage == .store(rewe.id))
    }

    @Test func branchesSurviveRelaunch() async throws {
        let box = ModelContainerBox(container: try PersistenceContainer.make(inMemory: true))
        let first = try await makeModel(container: box)
        let store = try #require(first.addStore(from: place("Lidl", metersNorth: 300)))
        let second = try await makeModel(container: box)
        #expect(second.locations(of: store.id).count == 1)
    }
}

struct ModelContainerBox {
    let container: ModelContainer
}
