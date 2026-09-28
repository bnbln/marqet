import MarqetCore
import SwiftUI

/// Open Prices while assigning stores (docs/OFFENE-DATEN.md §4): "Am günstigsten: Lidl, ca. 0,99 €/l".
extension PriceIndex.ChainPrice {
    /// "ca. 0,99 €/l" – a typical entry price, never exact.
    var displayText: String {
        let amount = typical.formatted(.currency(code: StoreCatalog.Region.current.currencyCode))
        return switch unit {
        case .kilogram: String(localized: "ca. \(amount)/kg")
        case .liter: String(localized: "ca. \(amount)/l")
        case .piece: String(localized: "ca. \(amount)/Stk.")
        }
    }

    /// "0,99 €/l" for the narrow store tiles.
    var shortText: String {
        let amount = typical.formatted(.currency(code: StoreCatalog.Region.current.currencyCode))
        return switch unit {
        case .kilogram: "\(amount)/kg"
        case .liter: "\(amount)/l"
        case .piece: String(localized: "\(amount)/Stk.")
        }
    }

    /// Compact estimate for an assigned item, using its requested quantity when recognizable.
    func estimateText(for title: String) -> String {
        guard let quantity = Self.quantity(in: title, for: unit) else {
            return String(localized: "ca. \(shortText)")
        }
        let amount = (typical * quantity).formatted(.currency(code: StoreCatalog.Region.current.currencyCode))
        return String(localized: "ca. \(amount)")
    }

    private static func quantity(in title: String, for unit: PriceIndex.Unit) -> Double? {
        let pattern = #"(?i)(\d+(?:[.,]\d+)?)\s*(kg|kilo|g|gr|l|liter|ml|cl|stück|stk\.?|x|×)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let valueRange = Range(match.range(at: 1), in: title),
              let unitRange = Range(match.range(at: 2), in: title),
              let value = Double(title[valueRange].replacingOccurrences(of: ",", with: ".")) else { return nil }
        let measure = title[unitRange].lowercased()
        switch unit {
        case .kilogram:
            switch measure {
            case "kg", "kilo": return value
            case "g", "gr": return value / 1_000
            default: return nil
            }
        case .liter:
            switch measure {
            case "l", "liter": return value
            case "ml": return value / 1_000
            case "cl": return value / 100
            default: return nil
            }
        case .piece:
            return ["stück", "stk", "stk.", "x", "×"].contains(measure) ? value : nil
        }
    }
}

extension StoreCatalog.Region {
    var currencyCode: String { self == .switzerland ? "CHF" : "EUR" }
}

/// The cheapest of the user's stores for an item, or the one price there is.
struct PriceHintLine: View {
    let hint: StorePriceHint
    @Environment(AppModel.self) private var model

    var body: some View {
        if let cheapest = hint.cheapest, let store = model.store(cheapest.storeID) {
            Label {
                Text("Am günstigsten: \(store.name), \(cheapest.price.displayText)")
            } icon: {
                Image(systemName: "tag.fill")
            }
            .foregroundStyle(store.readableColor)
            .accessibilityHint(Text("Preise von Open Prices"))
        } else if let only = hint.storePrices.first, let store = model.store(only.storeID) {
            Label("\(store.name): \(only.price.displayText)", systemImage: "tag")
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
extension AppModel {
    /// `-demo -demo-prices`: groceries without a store, at chains Open Prices knows well.
    static func pricesDemo() -> AppModel {
        let titles = ["Milch", "Butter", "Brot", "Bananen", "Joghurt", "Kaffee", "Nudeln", "Äpfel", "Eier", "Zahnpasta"]
        let model = preview(items: titles.map { ($0, nil) }, stores: ["lidl", "rewe", "aldi-sued", "netto", "dm"])
        model.hasCompletedOnboarding = true
        return model
    }
}
#endif

/// Attribution required by the ODbL, shown wherever a price is.
struct OpenPricesAttribution: View {
    var body: some View {
        Text("Preise: Open Prices (ODbL), Einstiegspreise der Kategorie, ohne Angebote")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
