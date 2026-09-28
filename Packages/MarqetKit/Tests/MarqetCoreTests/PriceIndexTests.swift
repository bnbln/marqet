import Foundation
import MarqetCore
import Testing

@Suite("Open Prices index & price suggestions")
struct PriceIndexTests {
    typealias Price = PriceIndex.ChainPrice

    static func price(_ store: String, _ typical: Double, count: Int = 5, unit: PriceIndex.Unit = .liter) -> Price {
        Price(store: store, unit: unit, typical: typical, count: count, latest: "2026-08-01")
    }

    let index = PriceIndex(
        generated: "2026-09-28",
        source: "Open Prices",
        categories: [
            "en:milks": .init(names: ["de": "Milch", "en": "Milks"], depth: 2),
            "en:whole-milks": .init(names: ["de": "Vollmilch", "en": "Whole milks"], depth: 3),
            "en:breads": .init(names: ["de": "Brote", "en": "Breads"], aliases: ["brot"], depth: 2),
            "en:tomatoes": .init(names: ["de": "Tomaten"], aliases: ["tomate"], depth: 3),
            "en:butters": .init(names: ["de": "Butter"], depth: 3),
            "en:chicken-eggs": .init(names: ["de": "Hühnereier"], aliases: ["eier"], depth: 4),
        ],
        prices: [
            "DE": [
                "en:milks": [price("rewe", 1.25), price("lidl", 0.99), price("kaufland", 6.9, count: 1, unit: .kilogram)],
                "en:whole-milks": [price("lidl", 1.09), price("aldi-sued", 1.35)],
                "en:breads": [price("netto", 3.4, unit: .kilogram), price("rewe", 5.3, unit: .kilogram)],
                "en:tomatoes": [price("lidl", 2.49, unit: .kilogram)],
                "en:chicken-eggs": [price("rewe", 0.3, unit: .piece)],
            ],
            "AT": ["en:milks": [price("billa", 1.49)]],
        ]
    )

    // MARK: Matching

    @Test func matchesWholeTitleWordsPluralsAliasesAndCompounds() {
        #expect(index.match(for: "Milch", region: .germany)?.categoryTag == "en:milks")
        #expect(index.match(for: "2x Vollmilch", region: .germany)?.categoryTag == "en:whole-milks")
        #expect(index.match(for: "Tomate", region: .germany)?.categoryTag == "en:tomatoes")
        #expect(index.match(for: "Brot", region: .germany)?.categoryTag == "en:breads")
        #expect(index.match(for: "Eier", region: .germany)?.categoryTag == "en:chicken-eggs")
        // Compound head: "Bio|milch", "Vollkorn|brot" (the alias counts, too).
        #expect(index.match(for: "Biomilch", region: .germany)?.categoryTag == "en:milks")
        #expect(index.match(for: "Vollkornbrot", region: .germany)?.categoryTag == "en:breads")
        #expect(index.match(for: "Milch fettarm", region: .germany)?.categoryTag == "en:milks")
    }

    @Test func categoriesWithoutPricesInTheRegionDoNotMatch() {
        #expect(index.match(for: "Butter", region: .germany) == nil)
        #expect(index.match(for: "Vollmilch", region: .austria)?.categoryTag == "en:milks")
        #expect(index.match(for: "Milch", region: .switzerland) == nil)
        #expect(index.match(for: "Batterien", region: .germany) == nil)
    }

    @Test func comparesOnlyTheDominantUnitCheapestFirst() throws {
        let match = try #require(index.match(for: "Milch", region: .germany))
        #expect(match.unit == .liter)
        #expect(match.prices.map(\.store) == ["lidl", "rewe"])
    }

    @Test func decodesTheBuildScriptFormat() throws {
        let json = """
        {"generated":"2026-09-28","source":"Open Prices","since":"2025-04-01","version":1,
         "categories":{"en:milks":{"names":{"de":"Milch"},"depth":2}},
         "prices":{"DE":{"en:milks":[{"store":"lidl","unit":"l","typical":0.99,"median":1.05,
           "low":0.95,"high":1.29,"count":12,"latest":"2026-09-01"}]}}}
        """
        let decoded = try PriceIndex.decode(Data(json.utf8))
        #expect(decoded.match(for: "Milch", region: .germany)?.prices.first?.median == 1.05)
    }

    @Test func bundledCategoriesKnowEverydayItemsWithoutBundledPrices() throws {
        let bundled = try #require(PriceIndex.bundled)
        #expect(bundled.prices.isEmpty)
        for title in ["Milch", "Butter", "Brot", "Eier", "Bananen", "Kaffee", "Joghurt"] {
            #expect(bundled.category(for: title) != nil, "\(title)")
        }
    }

    // MARK: Stores

    let lidl = Store(catalogKey: "lidl", name: "Lidl", colorHex: "#000", symbol: .monogram("L"), sortIndex: 0, origin: .catalog, type: .discounter)
    let rewe = Store(catalogKey: "rewe", name: "Rewe", colorHex: "#000", symbol: .monogram("R"), sortIndex: 1, origin: .catalog, type: .supermarket)
    let dm = Store(catalogKey: "dm", name: "dm", colorHex: "#000", symbol: .monogram("dm"), sortIndex: 2, origin: .catalog, type: .drugstore)
    let market = Store(name: "Markt", colorHex: "#000", symbol: .systemImage("basket"), sortIndex: 3, origin: .custom, type: .market)

    @Test func hintMapsPricesOntoTheUsersStores() throws {
        let hint = try #require(StorePriceHint(title: "Milch", stores: [rewe, dm, market, lidl], index: index, region: .germany))
        #expect(hint.storePrices.map(\.storeID) == [lidl.id, rewe.id])
        #expect(hint.cheapest?.storeID == lidl.id)
        #expect(hint.isReliable)
        let savings = try #require(hint.savingsShare(comparedTo: rewe.id))
        #expect(abs(savings - (1.25 - 0.99) / 1.25) < 0.0001)
        #expect(hint.savingsShare(comparedTo: dm.id) == nil)
    }

    @Test func equalPricesFollowTheUsersStoreOrder() throws {
        let tied = PriceIndex(generated: "", source: "", categories: index.categories, prices: ["DE": [
            "en:milks": [Self.price("lidl", 0.95), Self.price("rewe", 0.95), Self.price("dm", 1.25)],
        ]])
        let reweFirst = Store(catalogKey: "rewe", name: "Rewe", colorHex: "#000", symbol: .monogram("R"), sortIndex: -1, origin: .catalog, type: .supermarket)
        let hint = try #require(StorePriceHint(title: "Milch", stores: [lidl, reweFirst, dm], index: tied, region: .germany))
        #expect(hint.cheapest?.storeID == reweFirst.id)
        #expect(hint.isCheapest(lidl.id) && hint.isCheapest(reweFirst.id) && !hint.isCheapest(dm.id))
    }

    @Test func aSinglePriceTagDoesNotBeatWellKnownPrices() throws {
        let butter = PriceIndex(generated: "", source: "", categories: index.categories, prices: ["DE": [
            "en:milks": [Self.price("dm", 0.50, count: 1), Self.price("lidl", 0.99), Self.price("rewe", 1.25)],
        ]])
        let hint = try #require(StorePriceHint(title: "Milch", stores: [lidl, rewe, dm], index: butter, region: .germany))
        #expect(hint.storePrices.first?.storeID == dm.id)       // still shown
        #expect(hint.cheapest?.storeID == lidl.id)
        #expect(hint.isReliable)
        #expect(!hint.isCheapest(dm.id))
    }

    @Test func oneComparableStoreShowsAPriceButNoCheapest() throws {
        let hint = try #require(StorePriceHint(title: "Tomaten", stores: [lidl, rewe], index: index, region: .germany))
        #expect(hint.price(of: lidl.id)?.typical == 2.49)
        #expect(hint.cheapest == nil)
        #expect(StorePriceHint(title: "Milch", stores: [dm, market], index: index, region: .germany) == nil)
    }

    // MARK: Suggestions

    func hint(_ title: String = "Milch", stores: [Store]? = nil) -> StorePriceHint? {
        StorePriceHint(title: title, stores: stores ?? [lidl, rewe, dm], index: index, region: .germany)
    }

    @Test func cheapestStoreIsSuggestedWhenNothingElseIs() {
        let suggestion = SuggestionEngine.applyingPrice(nil, hint: hint())
        #expect(suggestion == StoreSuggestion(storeID: lidl.id, source: .price, confidence: .medium))
        #expect(suggestion?.allowsAutoAssign == false)
        #expect(SuggestionEngine.applyingPrice(nil, hint: nil) == nil)
    }

    @Test func aClearHabitAlwaysWins() {
        let habit = StoreSuggestion(storeID: rewe.id, source: .learned, confidence: .high)
        #expect(SuggestionEngine.applyingPrice(habit, hint: hint()) == habit)
    }

    @Test func weakerSuggestionsGiveWayToAClearlyCheaperStore() {
        for source in [StoreSuggestion.Source.similar, .intelligence, .storeType] {
            let weak = StoreSuggestion(storeID: rewe.id, source: source, confidence: .medium)
            #expect(SuggestionEngine.applyingPrice(weak, hint: hint())?.storeID == lidl.id, "\(source)")
        }
        let unclearHabit = StoreSuggestion(storeID: rewe.id, source: .learned, confidence: .medium)
        #expect(SuggestionEngine.applyingPrice(unclearHabit, hint: hint())?.source == .price)
    }

    @Test func aSuggestedStoreWithoutPricesOnlyYieldsToTheStoreTypeGuess() {
        let intelligence = StoreSuggestion(storeID: dm.id, source: .intelligence, confidence: .medium)
        #expect(SuggestionEngine.applyingPrice(intelligence, hint: hint()) == intelligence)
        let guess = StoreSuggestion(storeID: dm.id, source: .storeType, confidence: .low)
        #expect(SuggestionEngine.applyingPrice(guess, hint: hint())?.storeID == lidl.id)
    }

    @Test func smallSavingsAndThinDataDoNotOverrule() {
        let close = PriceIndex(generated: "", source: "", categories: index.categories, prices: ["DE": [
            "en:milks": [Self.price("lidl", 1.20), Self.price("rewe", 1.25)],
            "en:breads": [Self.price("lidl", 2.0, count: 1, unit: .kilogram), Self.price("rewe", 5.0, count: 1, unit: .kilogram)],
        ]])
        let similar = StoreSuggestion(storeID: rewe.id, source: .similar, confidence: .medium)
        let milk = StorePriceHint(title: "Milch", stores: [lidl, rewe], index: close, region: .germany)
        #expect(SuggestionEngine.applyingPrice(similar, hint: milk) == similar)      // 4 % cheaper
        let bread = StorePriceHint(title: "Brot", stores: [lidl, rewe], index: close, region: .germany)
        #expect(bread?.isReliable == false)
        #expect(SuggestionEngine.applyingPrice(similar, hint: bread) == similar)     // one price each
        #expect(SuggestionEngine.applyingPrice(nil, hint: bread)?.confidence == .low)
    }
}
