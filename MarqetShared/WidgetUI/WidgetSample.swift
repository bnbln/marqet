import Foundation
import MarqetCore

/// Demo data for the widget gallery, placeholders and previews – the same weekly shop as
/// `AppModel.demo`, built through the real `WidgetSnapshotBuilder`.
extension WidgetSnapshot {
    static let sample: WidgetSnapshot = {
        let catalog = try? StoreCatalog.bundled()
        func store(_ key: String, _ index: Int) -> Store? {
            catalog?.entry(forKey: key)?.makeStore(sortIndex: index, id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index + 1)")!)
        }
        let stores = [store("aldi-sued", 0), store("dm", 1), store("generic-market", 2), store("rewe", 3)].compactMap { $0 }
        guard stores.count == 4 else { return .empty }
        let (aldi, dm, market, rewe) = (stores[0], stores[1], stores[2], stores[3])

        let entries: [(String, Store?, String?)] = [
            ("Bananen", aldi, nil), ("Milch", aldi, "laktosefrei"), ("Vollkornbrot", aldi, nil), ("Butter", aldi, nil),
            ("Eier", aldi, nil), ("Kaffee", aldi, nil), ("Tiefkühlpizza", aldi, nil), ("Gouda", aldi, nil), ("Zucchini", aldi, nil),
            ("Zahnpasta", dm, nil), ("Duschgel", dm, nil), ("Sonnencreme", dm, "LSF 50"),
            ("Erdbeeren", market, nil), ("Spargel", market, nil),
            ("Frischkäse", rewe, nil), ("Joghurt", rewe, nil),
            ("Batterien AA", nil, nil), ("Geschenkpapier", nil, nil), ("Hafermilch", nil, nil),
        ]
        let items = entries.enumerated().map { index, entry in
            ShoppingItem(id: "sample-\(index)", title: entry.0, userNotes: entry.2, storeRef: entry.1.map { .known($0.id) },
                         creationDate: Date(timeIntervalSince1970: Double(index)))
        }
        let completed = ["Olivenöl", "Spülmittel", "Äpfel"].enumerated().map { index, title in
            ShoppingItem(id: "done-\(index)", title: title, storeRef: .known(aldi.id), isCompleted: true,
                         completionDate: Date(timeIntervalSinceNow: -Double(index + 1) * 3_600))
        }
        let brochures = (catalog?.entries(for: .germany) ?? []).compactMap { entry -> WidgetRegistry.BrochureSource? in
            guard let url = entry.leafletURL else { return nil }
            return .init(key: entry.key, name: entry.name, colorHex: entry.color, symbol: entry.storeSymbol, url: url)
        }
        let registry = WidgetRegistry(
            status: .ready,
            listID: "sample",
            listTitle: String(localized: "Einkaufen"),
            stores: stores,
            assignmentCounts: ["hafermilch": [rewe.id.uuidString: 2]],
            loyaltyCards: [
                LoyaltyCard(name: "Payback", payload: "4006381333931", symbology: .ean13, colorHex: "#0046AA",
                            storeIDs: [dm.id, rewe.id], createdAt: Date(timeIntervalSince1970: 0)),
            ],
            brochureSources: brochures,
            branchCoordinates: [
                aldi.id.uuidString: GeoPoint(latitude: 48.1374, longitude: 11.5755),
                dm.id.uuidString: GeoPoint(latitude: 48.1402, longitude: 11.5601),
                rewe.id.uuidString: GeoPoint(latitude: 48.1300, longitude: 11.5900),
            ],
            userLocation: GeoPoint(latitude: 48.1351, longitude: 11.5820)
        )
        let classifier = CategoryClassifier(dictionary: (try? CategoryDictionary.bundled()) ?? CategoryDictionary(categories: [:]))
        var trip = ShoppingTrip(storeID: aldi.id, startedAt: Date(timeIntervalSinceNow: -600))
        trip.recordCompletion(of: "done-0", in: aldi.id)
        trip.recordCompletion(of: "done-2", in: aldi.id)
        return WidgetSnapshotBuilder.snapshot(registry: registry, items: items, recentlyCompleted: completed,
                                              classifier: classifier, trip: trip)
    }()

    /// The sample without a running trip.
    static let sampleWithoutTrip: WidgetSnapshot = {
        var snapshot = sample
        snapshot.trip = nil
        return snapshot
    }()

    var sampleTripStatus: TripStatus? {
        trip.flatMap { TripStatus.make(snapshot: self, trip: $0) }
    }
}
