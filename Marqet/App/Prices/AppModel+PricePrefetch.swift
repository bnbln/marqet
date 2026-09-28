import Foundation
import MarqetCore

/// First price download while onboarding runs (docs/OFFENE-DATEN.md, Aktualisierung).
extension AppModel {
    /// Everyday items most lists contain. Their categories are downloaded once while the user reads
    /// the welcome screens, so the first "Zuordnen" already shows prices.
    static let staplePriceItems = [
        "Milch", "Butter", "Brot", "Eier", "Bananen", "Äpfel", "Tomaten", "Kartoffeln", "Zwiebeln",
        "Nudeln", "Reis", "Mehl", "Zucker", "Joghurt", "Käse", "Kaffee", "Hackfleisch", "Mineralwasser",
    ]

    /// Country-wide prices for the staples. No location is requested here: without permission
    /// `refreshPrices` asks for the country, and `displayablePrices` falls back to those later.
    /// Runs quietly: the requests leave the main actor, and categories fetched within the last
    /// day are skipped, so going back to the welcome screen does not start it again.
    func prefetchStaplePrices() async {
        let staples = Self.staplePriceItems.map { ShoppingItem(id: "staple:\($0)", title: $0) }
        await refreshPrices(for: staples)
    }
}
