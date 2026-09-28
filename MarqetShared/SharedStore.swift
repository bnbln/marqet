import Foundation
import MarqetCore

/// The App Group container shared by the app and the widget extension (KONZEPT-WIDGETS §9.2).
///
/// Plain JSON files: the app is the only writer, the extension only reads. Files stay readable
/// after the first unlock, so Lock Screen widgets work while the device is locked.
enum SharedStore {
    static let appGroup = "group.app.marqet.Marqet"

    private enum File: String {
        case snapshot = "widget-snapshot.json"
        case registry = "widget-registry.json"
        case trip = "shopping-trip.json"
    }

    /// The group container, or Application Support if the entitlement is missing (unsigned builds):
    /// the app keeps working, only the widgets stay empty.
    static let directory: URL = {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? URL.applicationSupportDirectory
        let directory = base.appending(path: "Widgets", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    // MARK: Values

    static var snapshot: WidgetSnapshot {
        read(WidgetSnapshot.self, from: .snapshot) ?? .empty
    }

    static var registry: WidgetRegistry? {
        read(WidgetRegistry.self, from: .registry)
    }

    static var trip: ShoppingTrip? {
        read(ShoppingTrip.self, from: .trip)
    }

    // MARK: Writing (app only)

    /// Returns `true` if the content changed – only then do widgets need a reload.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        // `generatedAt` alone is no reason to spend the widgets' reload budget.
        var comparable = snapshot
        comparable.generatedAt = self.snapshot.generatedAt
        guard let data = try? encoder.encode(comparable), data != (try? Data(contentsOf: url(.snapshot))) else { return false }
        return write(snapshot, to: .snapshot)
    }

    @discardableResult
    static func write(_ registry: WidgetRegistry) -> Bool {
        guard let data = try? encoder.encode(registry), data != (try? Data(contentsOf: url(.registry))) else { return false }
        return write(registry, to: .registry)
    }

    static func write(_ trip: ShoppingTrip?) {
        guard let trip else {
            try? FileManager.default.removeItem(at: url(.trip))
            return
        }
        write(trip, to: .trip)
    }

    // MARK: Private

    private static func url(_ file: File) -> URL {
        directory.appending(path: file.rawValue)
    }

    private static func read<Value: Decodable>(_ type: Value.Type, from file: File) -> Value? {
        guard let data = try? Data(contentsOf: url(file)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    @discardableResult
    private static func write(_ value: some Encodable, to file: File) -> Bool {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url(file), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        // Stable bytes, so an unchanged value compares equal to the file.
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// Widget kinds – `WidgetCenter.reloadTimelines(ofKind:)` and the widget configurations use them.
enum WidgetKind {
    static let list = "app.marqet.widget.list"
    static let overview = "app.marqet.widget.overview"
    static let loyaltyCard = "app.marqet.widget.loyalty-card"
    static let offers = "app.marqet.widget.offers"

    static let addItemControl = "app.marqet.control.add-item"
    static let loyaltyCardControl = "app.marqet.control.loyalty-card"
    static let tripControl = "app.marqet.control.trip"
}
