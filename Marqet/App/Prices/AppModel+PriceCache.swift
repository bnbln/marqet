import Foundation
import MarqetCore

/// Reading the Open Prices cache under the freshness guardrails (docs/OFFENE-DATEN.md).
extension AppModel {
    /// Prices of a category that may be shown as money right now, or `nil`.
    ///
    /// Local prices first. Without them – no location permission yet, or nothing nearby – the
    /// country-wide ones, e.g. from the first download during onboarding. `PriceFreshness` drops
    /// everything once a refresh is too old and chains whose newest observation is too old.
    func displayablePrices(for tag: String, now: Date = Date()) -> [PriceIndex.ChainPrice]? {
        var areas = [priceArea]
        if priceArea.center != nil { areas.append(PriceUpdateService.Area(location: nil)) }
        for area in areas {
            let key = PriceUpdateService.Cache.key(region: region, area: area, tag: tag)
            guard let entry = priceUpdates.entries[key] else { continue }
            let rows = PriceFreshness.displayable(entry.prices, checkedAt: entry.checkedAt, now: now)
            if !rows.isEmpty { return rows }
        }
        return nil
    }
}
