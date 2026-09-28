import Foundation
import MarqetCore
import Testing

@Suite("Places – distance, sorting, chain recognition (KONZEPT §14)")
struct PlacesTests {
    static func store(_ name: String, _ index: Int) -> Store {
        Store(name: name, colorHex: "#000000", symbol: .monogram("X"), sortIndex: index, origin: .catalog, type: .supermarket)
    }

    let aldi = store("Aldi", 0)
    let rewe = store("Rewe", 1)
    let dm = store("dm", 2)
    let markt = store("Markt", 3)

    // MARK: Distance

    @Test func haversineMatchesKnownDistance() {
        let berlin = GeoPoint(latitude: 52.5200, longitude: 13.4050)
        let munich = GeoPoint(latitude: 48.1351, longitude: 11.5820)
        #expect(abs(berlin.distance(to: munich) / 1000 - 504) < 3)
        #expect(berlin.distance(to: berlin) == 0)
    }

    @Test func travelMinutesDependOnMode() {
        let walk = PlaceMath.travelMinutes(meters: 1000, mode: .walking)
        let drive = PlaceMath.travelMinutes(meters: 1000, mode: .driving)
        #expect(walk > 15 && walk < 18)
        #expect(drive > 2 && drive < 4)
    }

    @Test func preferredBranchWinsOverNearest() {
        let home = GeoPoint(latitude: 48.0, longitude: 11.0)
        let near = StoreLocation(storeID: aldi.id, name: "Aldi Nah", coordinate: GeoPoint(latitude: 48.001, longitude: 11.0))
        let far = StoreLocation(storeID: aldi.id, name: "Aldi Fern", coordinate: GeoPoint(latitude: 48.05, longitude: 11.0))
        #expect(PlaceMath.relevantLocation(of: [far, near], from: home)?.name == "Aldi Nah")
        var preferredFar = far
        preferredFar.isPreferred = true
        #expect(PlaceMath.relevantLocation(of: [preferredFar, near], from: home)?.name == "Aldi Fern")
        #expect(PlaceMath.relevantLocation(of: [], from: home) == nil)
    }

    // MARK: Sorting

    @Test func manualKeepsSortIndex() {
        let order = StoreSorter.order(stores: [dm, aldi, rewe], mode: .manual, openItemCounts: [:], travelMinutes: [dm.id: 1])
        #expect(order == [aldi.id, rewe.id, dm.id])
    }

    @Test func distanceSortsNearestFirstAndUnknownLast() {
        let order = StoreSorter.order(
            stores: [aldi, rewe, dm, markt], mode: .distance, openItemCounts: [:],
            travelMinutes: [aldi.id: 12, rewe.id: 3, dm.id: 7]
        )
        #expect(order == [rewe.id, dm.id, aldi.id, markt.id])
    }

    @Test func smartWeighsItemsAgainstTravelTime() {
        // Aldi: 10 items / (15 + 5) = 0.5 · Rewe: 2 / (1 + 5) = 0.33 · dm: 0 items (planned).
        let order = StoreSorter.order(
            stores: [aldi, rewe, dm], mode: .smart,
            openItemCounts: [aldi.id: 10, rewe.id: 2],
            travelMinutes: [aldi.id: 15, rewe.id: 1, dm.id: 2]
        )
        #expect(order == [aldi.id, rewe.id, dm.id])
    }

    @Test func cardBuilderFollowsGivenOrder() {
        let items = [aldi, rewe, dm].map { ShoppingItem(id: $0.name, title: "x", storeRef: .known($0.id)) }
        let deck = CardBuilder.deck(items: items, stores: [aldi, rewe, dm], storeOrder: [dm.id, aldi.id])
        #expect(deck.pages == [.brochures, .unsorted, .store(dm.id), .store(aldi.id), .store(rewe.id), .more])
    }

    // MARK: Chain recognition

    @Test(arguments: [
        ("ALDI SÜD", "aldi-sued"),
        ("Aldi Süd Filiale München", "aldi-sued"),
        ("REWE City", "rewe"),
        ("REWE", "rewe"),
        ("Lidl", "lidl"),
        ("dm-drogerie markt", "dm"),
        ("EDEKA Center Huber", "edeka"),
        ("Müller Drogerie", "mueller"),
        ("BILLA PLUS", "billa-plus"),   // longest match beats "Billa"
        ("BUDNI", "budni"),
        ("Budnikowsky Eppendorf", "budni"),
        ("EDEKA Ernst", "edeka"),
        ("E center Singer", "edeka"),
        ("REWE Markt GmbH", "rewe"),
        ("HIT Ullrich", "hit"),
    ])
    func recognizesChains(_ place: String, _ key: String) throws {
        let catalog = try StoreCatalog.bundled().stores
        #expect(ChainRecognizer.entry(forPlaceNamed: place, in: catalog)?.key == key)
    }

    @Test(arguments: ["Bäckerei Müller", "Café Lidl-Eck", "Wochenmarkt Viktualienmarkt", "Metzgerei Huber", "",
                      "Hitzler Bäckerei", "Normann Optik", "Reweler Kiosk", "Combina Pizza"])
    func doesNotGuess(_ place: String) throws {
        let catalog = try StoreCatalog.bundled().stores
        #expect(ChainRecognizer.entry(forPlaceNamed: place, in: catalog) == nil)
    }
}
