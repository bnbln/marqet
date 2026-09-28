import AppIntents
import WidgetKit

// "Widget bearbeiten" and control configuration (KONZEPT-WIDGETS §3, §6).

struct ListWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Liste" }
    static var description: IntentDescription {
        IntentDescription("Eine Liste aus Marqet: ein Laden, die Inbox, der nächste Laden oder zuletzt Erledigtes.")
    }

    @Parameter(title: "Liste")
    var list: ShoppingListEntity?

    @Parameter(title: "Kategorien zeigen", default: true)
    var showsSections: Bool

    init() {}

    init(list: ShoppingListEntity, showsSections: Bool = true) {
        self.list = list
        self.showsSections = showsSections
    }
}

struct OverviewWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Überblick" }
    static var description: IntentDescription {
        IntentDescription("Alle Läden mit offenen Einträgen auf einen Blick.")
    }

    @Parameter(title: "Reihenfolge", default: .app)
    var order: OverviewOrder

    @Parameter(title: "Inbox zeigen", default: true)
    var showsInbox: Bool

    init() {}

    init(order: OverviewOrder, showsInbox: Bool = true) {
        self.order = order
        self.showsInbox = showsInbox
    }
}

struct LoyaltyCardWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Kundenkarte" }
    static var description: IntentDescription {
        IntentDescription("Deine Kundenkarte, ein Tipp bis zum Barcode an der Kasse.")
    }

    @Parameter(title: "Karte")
    var card: LoyaltyCardEntity?

    init() {}
}

struct OffersWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Angebote" }
    static var description: IntentDescription {
        IntentDescription("Die aktuellen Prospekte deiner Läden.")
    }

    /// `nil`: all own stores first, then chains nearby.
    @Parameter(title: "Laden")
    var store: StoreEntity?

    init() {}
}

struct AddItemControlIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource { "Eintrag hinzufügen" }

    @Parameter(title: "Liste")
    var list: ShoppingListEntity?

    init() {}
}

struct LoyaltyCardControlIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource { "Kundenkarte" }

    @Parameter(title: "Karte")
    var card: LoyaltyCardEntity?

    init() {}
}
