import AppIntents
import Foundation
import MarqetCore

// Entities for widget configuration, controls, Siri and Shortcuts (KONZEPT-WIDGETS §3, §7).
// They read the snapshot the app wrote to the App Group, so they work in both processes.

/// A list of Marqet: "Nächster Laden" (automatic), the inbox, one store, or recently completed.
struct ShoppingListEntity: AppEntity {
    enum Kind: Hashable, Sendable {
        case automatic, inbox, completed
        case store(Store.ID)
    }

    static let automaticID = "auto"
    static let inboxID = PageID.unsorted.rawValue
    static let completedID = "completed"

    let id: String
    let name: String
    let detail: String?

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Liste", numericFormat: "\(placeholder: .int) Listen")
    }

    static var defaultQuery: ShoppingListQuery { ShoppingListQuery() }

    var kind: Kind {
        switch id {
        case Self.automaticID: .automatic
        case Self.inboxID: .inbox
        case Self.completedID: .completed
        default: PageID(rawValue: id)?.storeID.map(Kind.store) ?? .automatic
        }
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: detail.map { "\($0)" },
            image: .init(systemName: symbol)
        )
    }

    private var symbol: String {
        switch kind {
        case .automatic: "sparkles"
        case .inbox: "tray"
        case .completed: "checkmark.circle"
        case .store: "storefront"
        }
    }

    static var automatic: ShoppingListEntity {
        ShoppingListEntity(id: automaticID, name: String(localized: "Nächster Laden"),
                           detail: String(localized: "Automatisch: laufender Einkauf oder nächste Card"))
    }

    static func all(in snapshot: WidgetSnapshot) -> [ShoppingListEntity] {
        var entities = [automatic]
        entities.append(ShoppingListEntity(id: inboxID, name: String(localized: "Inbox"), detail: count(snapshot.inbox?.openCount ?? 0)))
        for store in snapshot.stores {
            let open = snapshot.page(forStore: store.id)?.openCount ?? 0
            entities.append(ShoppingListEntity(id: PageID.store(store.id).rawValue, name: store.name, detail: count(open)))
        }
        entities.append(ShoppingListEntity(id: completedID, name: String(localized: "Zuletzt erledigt"),
                                           detail: String(localized: "Nochmal kaufen")))
        return entities
    }

    private static func count(_ open: Int) -> String {
        open == 0 ? String(localized: "leer") : String(localized: "\(open) offen")
    }
}

struct ShoppingListQuery: EntityQuery {
    func entities(for identifiers: [ShoppingListEntity.ID]) async throws -> [ShoppingListEntity] {
        let all = ShoppingListEntity.all(in: SharedStore.snapshot)
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [ShoppingListEntity] {
        ShoppingListEntity.all(in: SharedStore.snapshot)
    }

    func defaultResult() async -> ShoppingListEntity? {
        .automatic
    }
}

/// One of the user's stores.
struct StoreEntity: AppEntity {
    let id: UUID
    let name: String
    let detail: String?

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Laden", numericFormat: "\(placeholder: .int) Läden")
    }

    static var defaultQuery: StoreEntityQuery { StoreEntityQuery() }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: detail.map { "\($0)" }, image: .init(systemName: "storefront"))
    }

    init(store: Store, snapshot: WidgetSnapshot) {
        id = store.id
        name = store.name
        let open = snapshot.page(forStore: store.id)?.openCount ?? 0
        detail = open == 0 ? nil : String(localized: "\(open) offen")
    }
}

struct StoreEntityQuery: EntityStringQuery {
    func entities(for identifiers: [StoreEntity.ID]) async throws -> [StoreEntity] {
        let snapshot = SharedStore.snapshot
        return identifiers.compactMap { id in snapshot.store(id).map { StoreEntity(store: $0, snapshot: snapshot) } }
    }

    func entities(matching string: String) async throws -> [StoreEntity] {
        let snapshot = SharedStore.snapshot
        let key = ItemKeyNormalizer.storeNameKey(string)
        return snapshot.stores
            .filter { ItemKeyNormalizer.storeNameKey($0.name).contains(key) }
            .map { StoreEntity(store: $0, snapshot: snapshot) }
    }

    /// Stores with open items first – that is where one goes shopping.
    func suggestedEntities() async throws -> [StoreEntity] {
        let snapshot = SharedStore.snapshot
        let active = snapshot.activeStorePages.compactMap(\.store)
        let rest = snapshot.stores.filter { store in !active.contains { $0.id == store.id } }
        return (active + rest).map { StoreEntity(store: $0, snapshot: snapshot) }
    }
}

/// A customer card, or "Automatisch" (the card of the running or next store).
struct LoyaltyCardEntity: AppEntity {
    static let automaticID = "auto"

    let id: String
    let name: String
    let detail: String?

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Kundenkarte", numericFormat: "\(placeholder: .int) Kundenkarten")
    }

    static var defaultQuery: LoyaltyCardQuery { LoyaltyCardQuery() }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: detail.map { "\($0)" },
                              image: .init(systemName: id == Self.automaticID ? "sparkles" : "wallet.pass"))
    }

    var cardID: LoyaltyCard.ID? { UUID(uuidString: id) }

    static var automatic: LoyaltyCardEntity {
        LoyaltyCardEntity(id: automaticID, name: String(localized: "Automatisch"),
                          detail: String(localized: "Karte des Ladens, in dem du einkaufst"))
    }

    init(id: String, name: String, detail: String?) {
        self.id = id
        self.name = name
        self.detail = detail
    }

    init(card: LoyaltyCard, snapshot: WidgetSnapshot) {
        id = card.id.uuidString
        name = card.name
        let stores = card.storeIDs.compactMap { snapshot.store($0)?.name }
        detail = stores.isEmpty ? nil : stores.formatted(.list(type: .and))
    }

    /// The card this entity stands for right now.
    func resolve(in snapshot: WidgetSnapshot) -> LoyaltyCard? {
        cardID.flatMap(snapshot.loyaltyCard) ?? snapshot.automaticLoyaltyCard
    }
}

struct LoyaltyCardQuery: EntityQuery {
    func entities(for identifiers: [LoyaltyCardEntity.ID]) async throws -> [LoyaltyCardEntity] {
        let all = try await suggestedEntities()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [LoyaltyCardEntity] {
        let snapshot = SharedStore.snapshot
        return [.automatic] + snapshot.loyaltyCards
            .sorted { $0.createdAt < $1.createdAt }
            .map { LoyaltyCardEntity(card: $0, snapshot: snapshot) }
    }

    func defaultResult() async -> LoyaltyCardEntity? {
        .automatic
    }
}

/// Order of the stores in the overview widget.
enum OverviewOrder: String, AppEnum {
    /// Like the cards in the app (manual, distance or smart).
    case app
    /// Most open items first.
    case count
    /// Nearest branch first.
    case distance

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Reihenfolge" }

    static var caseDisplayRepresentations: [OverviewOrder: DisplayRepresentation] {
        [
            .app: "Wie in der App",
            .count: "Meiste Einträge zuerst",
            .distance: "Nächster Laden zuerst",
        ]
    }
}
