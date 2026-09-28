import Foundation
import MarqetCore
import Testing
@testable import Marqet

@MainActor
@Suite("Preise aktualisieren")
struct PriceRefreshTests {
    /// The settings row "Letzte Preisabfrage" must follow a refresh, although the cache itself is not observed.
    @Test func lastPriceCheckFollowsANewCacheEntry() {
        let model = AppModel.preview(stores: ["lidl"])
        final class Flag: @unchecked Sendable { var value = false }
        let changed = Flag()
        withObservationTracking { _ = model.lastPriceCheck } onChange: { changed.value = true }

        let key = PriceUpdateService.Cache.key(region: model.region, area: model.priceArea, tag: "en:milks")
        model.priceUpdates.entries[key] = .init(checkedAt: Date(), prices: [], finds: [])
        model.priceRevision += 1

        #expect(changed.value)
        #expect(model.lastPriceCheck != nil)
    }

    /// Guardrail: without a successful refresh for a week, no euro amount is shown any more.
    @Test func anExpiredCacheShowsNoMoney() throws {
        let model = AppModel.preview(stores: ["lidl", "rewe"])
        let milk = ShoppingItem(id: "milk", title: "Milch")
        let tag = try #require(PriceIndex.bundled?.category(for: "Milch")?.tag)
        let key = PriceUpdateService.Cache.key(region: model.region, area: model.priceArea, tag: tag)
        let today = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let prices = [
            PriceIndex.ChainPrice(store: "lidl", unit: .liter, typical: 0.99, count: 5, latest: today),
            PriceIndex.ChainPrice(store: "rewe", unit: .liter, typical: 1.19, count: 5, latest: today),
        ]

        model.priceUpdates.entries[key] = .init(checkedAt: Date().addingTimeInterval(-3 * 24 * 60 * 60), prices: prices, finds: [])
        #expect(model.priceHint(for: milk)?.storePrices.count == 2)

        model.priceUpdates.entries[key] = .init(checkedAt: Date().addingTimeInterval(-8 * 24 * 60 * 60), prices: prices, finds: [])
        #expect(model.priceHint(for: milk) == nil)
    }
}
