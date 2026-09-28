import AppIntents
import Foundation
import MarqetCore

// Buttons in widgets, the Live Activity and controls (KONZEPT-WIDGETS §8).
//
// Every change runs in the app process: `LiveActivityIntent` makes the system launch the app in the
// background if needed. That keeps one path for all changes – the AppModel, with learning, the
// shopping session, the Live Activity and the widget reload. The widget extension compiles these
// types too (it shows the buttons), but never performs them, hence `#if MARQET_APP`.

struct CheckItemIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Eintrag abhaken" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Eintrag")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        #if MARQET_APP
        await IntentActions.checkOff(itemID: itemID)
        #endif
        return .result()
    }
}

/// "Nochmal kaufen" in the widget "Zuletzt erledigt".
struct RestoreItemIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Nochmal kaufen" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Eintrag")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        #if MARQET_APP
        await IntentActions.restore(itemID: itemID)
        #endif
        return .result()
    }
}

/// The suggestion chip in the inbox widget ("→ Rewe"): assigns and learns.
struct AssignItemIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Laden zuordnen" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Eintrag")
    var itemID: String

    @Parameter(title: "Laden")
    var storeID: String

    init() {}

    init(itemID: String, storeID: Store.ID) {
        self.itemID = itemID
        self.storeID = storeID.uuidString
    }

    func perform() async throws -> some IntentResult {
        #if MARQET_APP
        if let id = UUID(uuidString: storeID) {
            await IntentActions.assign(itemID: itemID, to: id)
        }
        #endif
        return .result()
    }
}

struct StartTripIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Einkauf starten" }
    static var description: IntentDescription {
        IntentDescription("Zeigt den Einkauf als Live-Aktivität: nächste Einträge, Fortschritt und Kundenkarte auf dem Sperrbildschirm.")
    }

    /// `nil`: the next store (first card with items).
    @Parameter(title: "Laden")
    var store: StoreEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Einkauf bei \(\.$store) starten")
    }

    init() {}

    init(storeID: Store.ID?) {
        if let storeID, let store = SharedStore.snapshot.store(storeID) {
            self.store = StoreEntity(store: store, snapshot: SharedStore.snapshot)
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if MARQET_APP
        let message = await IntentActions.startTrip(at: store?.id)
        #else
        let message = ""
        #endif
        return .result(dialog: "\(message)")
    }
}

struct EndTripIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Einkauf beenden" }

    init() {}

    func perform() async throws -> some IntentResult {
        #if MARQET_APP
        await IntentActions.endTrip()
        #endif
        return .result()
    }
}

/// "Weiter zu dm" when the current store is done.
struct NextStoreIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Weiter zum nächsten Laden" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Laden")
    var storeID: String

    init() {}

    init(storeID: Store.ID) {
        self.storeID = storeID.uuidString
    }

    func perform() async throws -> some IntentResult {
        #if MARQET_APP
        if let id = UUID(uuidString: storeID) {
            await IntentActions.moveTrip(to: id)
        }
        #endif
        return .result()
    }
}

/// The "Einkauf" switch in Control Center.
struct TripToggleIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Einkauf an- oder ausschalten" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Einkauf läuft")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        #if MARQET_APP
        if value {
            _ = await IntentActions.startTrip(at: nil)
        } else {
            await IntentActions.endTrip()
        }
        #endif
        return .result()
    }
}

// MARK: - Opening the app

/// Opens the composer on a list – widgets have no text input (KONZEPT-WIDGETS §2.7).
struct AddItemIntent: AppIntent {
    static var title: LocalizedStringResource { "Eintrag hinzufügen" }
    static var description: IntentDescription {
        IntentDescription("Öffnet Marqet mit der Tastatur auf der gewählten Liste.")
    }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Liste")
    var list: ShoppingListEntity?

    init() {}

    init(list: ShoppingListEntity?) {
        self.list = list
    }

    func perform() async throws -> some IntentResult {
        #if MARQET_APP
        await IntentActions.open(list?.kind ?? .automatic, composing: true)
        #endif
        return .result()
    }
}

struct OpenListIntent: AppIntent {
    static var title: LocalizedStringResource { "Liste öffnen" }
    static var description: IntentDescription {
        IntentDescription("Öffnet einen Laden, die Inbox oder zuletzt Erledigtes in Marqet.")
    }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Liste")
    var list: ShoppingListEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$list) öffnen")
    }

    init() {}

    func perform() async throws -> some IntentResult {
        #if MARQET_APP
        await IntentActions.open(list.kind, composing: false)
        #endif
        return .result()
    }
}

struct ShowLoyaltyCardIntent: AppIntent {
    static var title: LocalizedStringResource { "Kundenkarte zeigen" }
    static var description: IntentDescription {
        IntentDescription("Zeigt den Barcode deiner Kundenkarte im Vollbild mit voller Helligkeit.")
    }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Karte")
    var card: LoyaltyCardEntity?

    init() {}

    init(card: LoyaltyCardEntity?) {
        self.card = card
    }

    func perform() async throws -> some IntentResult {
        #if MARQET_APP
        await IntentActions.showLoyaltyCard(card?.cardID)
        #endif
        return .result()
    }
}
