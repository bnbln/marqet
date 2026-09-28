import Foundation

/// When downloaded Open Prices may still be shown as money (docs/OFFENE-DATEN.md, Guardrails).
///
/// Two ages count: how long ago Marqet last refreshed a category successfully, and how old the
/// newest observation of a chain is. Stale data never turns into a euro amount on screen; the
/// app shows nothing rather than an outdated price.
public enum PriceFreshness {
    /// A successful refresh younger than this is reused without asking again.
    public static let refreshInterval: TimeInterval = 24 * 60 * 60
    /// After this long without a successful refresh, a category shows no prices at all.
    public static let displayLimit: TimeInterval = 7 * 24 * 60 * 60
    /// Price finds (discounts, price leaders) are about the current week – they go sooner.
    public static let findsDisplayLimit: TimeInterval = 2 * 24 * 60 * 60
    /// A chain whose newest observation is older than this is left out, even from a fresh refresh.
    public static let maximumObservationAge: TimeInterval = 60 * 24 * 60 * 60

    public enum State: Equatable, Sendable {
        /// Refreshed within `refreshInterval`: nothing to do.
        case fresh
        /// Still shown, but due for a refresh.
        case due
        /// Past `displayLimit`: no money values any more.
        case expired
    }

    public static func state(checkedAt: Date, now: Date = Date()) -> State {
        let age = now.timeIntervalSince(checkedAt)
        if age < refreshInterval { return .fresh }
        return age < displayLimit ? .due : .expired
    }

    /// Prices that may be shown: none once the refresh is too old, otherwise only chains with a
    /// recent observation.
    public static func displayable(_ prices: [PriceIndex.ChainPrice], checkedAt: Date, now: Date = Date()) -> [PriceIndex.ChainPrice] {
        guard state(checkedAt: checkedAt, now: now) != .expired else { return [] }
        return prices.filter { isRecent(observedOn: $0.latest, now: now) }
    }

    /// Whether an observation date (`yyyy-MM-dd`) lies within `maximumObservationAge`.
    /// An unreadable date counts as old.
    public static func isRecent(observedOn day: String, now: Date = Date(), limit: TimeInterval = maximumObservationAge) -> Bool {
        guard let date = try? Date(day, strategy: .iso8601.year().month().day().dateSeparator(.dash)) else { return false }
        return now.timeIntervalSince(date) <= limit
    }
}
