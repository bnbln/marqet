import Foundation

/// Deep links from widgets, the Live Activity and controls into the app (`marqet://…`,
/// KONZEPT-WIDGETS §8).
public enum MarqetLink: Hashable, Sendable {
    /// Home with the card pager, nothing opened – for widgets that show several cards.
    case home
    /// A card full screen – store or inbox.
    case page(PageID)
    /// The composer on a card.
    case compose(PageID)
    case triage
    /// "Erledigte anzeigen" – recently checked off items.
    case completed
    case loyaltyCard(LoyaltyCard.ID)
    /// All customer cards of a store (the Live Activity's wallet button).
    case storeLoyaltyCards(Store.ID)
    /// The "Angebote" card.
    case offers
    /// One chain's official leaflet.
    case offer(catalogKey: String)
    /// The store of the running trip, full screen.
    case trip

    public static let scheme = "marqet"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .home:
            components.host = "home"
        case .page(let page):
            components.host = "page"
            components.path = "/" + page.rawValue
        case .compose(let page):
            components.host = "compose"
            components.path = "/" + page.rawValue
        case .triage:
            components.host = "triage"
        case .completed:
            components.host = "completed"
        case .loyaltyCard(let id):
            components.host = "card"
            components.path = "/" + id.uuidString
        case .storeLoyaltyCards(let id):
            components.host = "card"
            components.path = "/store/" + id.uuidString
        case .offers:
            components.host = "offers"
        case .offer(let key):
            components.host = "offers"
            components.path = "/" + key
        case .trip:
            components.host = "trip"
        }
        // Only built from known values, so the URL is always valid.
        return components.url!
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else { return nil }
        let parts = url.path().split(separator: "/").map(String.init)
        switch (host, parts.count) {
        case ("home", 0): self = .home
        case ("page", 1):
            guard let page = PageID(rawValue: parts[0]) else { return nil }
            self = .page(page)
        case ("compose", 1):
            guard let page = PageID(rawValue: parts[0]) else { return nil }
            self = .compose(page)
        case ("triage", 0): self = .triage
        case ("completed", 0): self = .completed
        case ("card", 1):
            guard let id = UUID(uuidString: parts[0]) else { return nil }
            self = .loyaltyCard(id)
        case ("card", 2) where parts[0] == "store":
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            self = .storeLoyaltyCards(id)
        case ("offers", 0): self = .offers
        case ("offers", 1): self = .offer(catalogKey: parts[0])
        case ("trip", 0): self = .trip
        default: return nil
        }
    }
}
