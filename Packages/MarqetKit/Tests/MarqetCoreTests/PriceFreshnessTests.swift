import Foundation
import MarqetCore
import Testing

@Suite("Open Prices freshness guardrails")
struct PriceFreshnessTests {
    let now = try! Date("2026-09-28T12:00:00Z", strategy: .iso8601)
    let day: TimeInterval = 24 * 60 * 60

    func price(_ store: String, latest: String) -> PriceIndex.ChainPrice {
        PriceIndex.ChainPrice(store: store, unit: .liter, typical: 0.99, count: 3, latest: latest)
    }

    @Test func stateFollowsTheLastSuccessfulRefresh() {
        #expect(PriceFreshness.state(checkedAt: now.addingTimeInterval(-2 * 60 * 60), now: now) == .fresh)
        #expect(PriceFreshness.state(checkedAt: now.addingTimeInterval(-2 * day), now: now) == .due)
        #expect(PriceFreshness.state(checkedAt: now.addingTimeInterval(-6.9 * day), now: now) == .due)
        #expect(PriceFreshness.state(checkedAt: now.addingTimeInterval(-7 * day), now: now) == .expired)
    }

    @Test func noMoneyValuesOnceTheRefreshIsTooOld() {
        let prices = [price("lidl", latest: "2026-09-20")]
        #expect(PriceFreshness.displayable(prices, checkedAt: now.addingTimeInterval(-3 * day), now: now).count == 1)
        #expect(PriceFreshness.displayable(prices, checkedAt: now.addingTimeInterval(-8 * day), now: now).isEmpty)
    }

    @Test func oldObservationsAreLeftOutEvenFromAFreshRefresh() {
        let prices = [price("lidl", latest: "2026-09-20"), price("rewe", latest: "2026-07-01"), price("dm", latest: "kaputt")]
        let shown = PriceFreshness.displayable(prices, checkedAt: now, now: now)
        #expect(shown.map(\.store) == ["lidl"])
        #expect(PriceFreshness.isRecent(observedOn: "2026-07-31", now: now))    // 59,5 Tage
        #expect(!PriceFreshness.isRecent(observedOn: "2026-07-29", now: now))   // 61,5 Tage
    }
}
