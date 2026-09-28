import Foundation
import MarqetCore
import Testing

@Suite("StoreCatalog")
struct StoreCatalogTests {
    let catalog: StoreCatalog

    init() throws {
        catalog = try StoreCatalog.bundled()
    }

    @Test func keysAndNamesAreUnique() {
        #expect(Set(catalog.stores.map(\.key)).count == catalog.stores.count)
        #expect(Set(catalog.stores.map { ItemKeyNormalizer.storeNameKey($0.name) }).count == catalog.stores.count)
    }

    @Test func everyEntryIsValid() {
        for entry in catalog.stores {
            #expect(RGBColor(hex: entry.color) != nil, "\(entry.key): invalid color")
            #expect(!entry.regions.isEmpty, "\(entry.key): no region")
            #expect((entry.monogram == nil) != (entry.symbol == nil), "\(entry.key): needs monogram xor symbol")
            #expect(entry.name.count <= StoreMarker.maxNameLength, "\(entry.key): name too long for marker")
        }
    }

    @Test func regionsFilterChains() {
        let austria = catalog.entries(for: .austria).map(\.key)
        #expect(austria.contains("billa"))
        #expect(austria.contains("lidl"))
        #expect(!austria.contains("rewe"))
        #expect(catalog.entries(for: .switzerland).map(\.key).contains("migros"))
    }

    @Test func shoppingBrandsCoverMoreThanGroceries() throws {
        let german = catalog.entries(for: .germany).map(\.key)
        for key in ["sephora", "douglas", "kadewe", "breuninger", "galeria"] {
            #expect(german.contains(key))
        }
        let galeria = try #require(catalog.entry(forKey: "galeria"))
        #expect(galeria.aliases.contains("Galeria Kaufhof"))
        #expect(galeria.type == .department)
    }

    @Test func catalogStoresResolveThroughMatcher() {
        let stores = catalog.entries(for: .germany).enumerated().map { $1.makeStore(sortIndex: $0) }
        let matcher = StoreMatcher(stores: stores)
        #expect(matcher.store(named: "Aldi Sued")?.catalogKey == "aldi-sued")
        #expect(matcher.store(named: "Bäckerei")?.catalogKey == "generic-bakery")
        #expect(matcher.store(named: "denns")?.catalogKey == "denns")
    }

    @Test func makeStoreMapsSymbol() throws {
        let aldi = try #require(catalog.entry(forKey: "aldi-sued")).makeStore(sortIndex: 3)
        #expect(aldi.symbol == .monogram("AS"))
        #expect(aldi.origin == .catalog)
        #expect(aldi.sortIndex == 3)
        let market = try #require(catalog.entry(forKey: "generic-market")).makeStore(sortIndex: 0)
        #expect(market.symbol == .systemImage("carrot.fill"))
        #expect(market.type.showsCategorySections)
    }
}

@Suite("RGBColor")
struct RGBColorTests {
    @Test func parsesHex() {
        #expect(RGBColor(hex: "#FF0000") == RGBColor(red: 1, green: 0, blue: 0))
        #expect(RGBColor(hex: "00ff00") == RGBColor(red: 0, green: 1, blue: 0))
        #expect(RGBColor(hex: "#FFF") == nil)
        #expect(RGBColor(hex: "nope") == nil)
    }

    @Test func foregroundChoice() throws {
        #expect(try #require(RGBColor(hex: "#F5C400")).prefersDarkForeground)   // Edeka-like yellow
        #expect(try !#require(RGBColor(hex: "#243C8C")).prefersDarkForeground)  // Aldi-like blue
    }

    @Test(arguments: ["#F5C400", "#243C8C", "#E0662B", "#5E9E3C", "#23879B"])
    func readableAdjustment(_ hex: String) throws {
        let color = try #require(RGBColor(hex: hex))
        let lightCard = RGBColor.white
        let darkCard = try #require(RGBColor(hex: "#1C1C1E"))
        #expect(color.adjusted(forContrast: 4.5, on: lightCard).contrastRatio(with: lightCard) >= 4.5)
        #expect(color.adjusted(forContrast: 4.5, on: darkCard).contrastRatio(with: darkCard) >= 4.5)
    }

    @Test func readableAdjustmentKeepsSufficientColors() throws {
        let blue = try #require(RGBColor(hex: "#243C8C"))
        #expect(blue.adjusted(forContrast: 4.5, on: .white) == blue)
    }
}

@Suite("Mapping & heuristics")
struct MappingTests {
    let aldi = Store(name: "Aldi Süd", colorHex: "#243C8C", symbol: .monogram("AS"), sortIndex: 1, origin: .catalog, type: .discounter)
    let dm = Store(name: "dm", colorHex: "#233F85", symbol: .monogram("dm"), sortIndex: 0, origin: .catalog, type: .drugstore)

    @Test func mapperResolvesMarker() {
        let matcher = StoreMatcher(stores: [aldi, dm])
        let known = ShoppingItemMapper.item(
            from: ReminderSnapshot(id: "1", title: "Milch", notes: "laktosefrei\n🛒 aldi sued"), matcher: matcher
        )
        #expect(known.storeRef == .known(aldi.id))
        #expect(known.userNotes == "laktosefrei")

        let unknown = ShoppingItemMapper.item(from: ReminderSnapshot(id: "2", title: "Wurst", notes: "🛒 Metzger Huber"), matcher: matcher)
        #expect(unknown.storeRef == .unresolved(name: "Metzger Huber"))
        #expect(unknown.unresolvedStoreName == "Metzger Huber")

        let unsorted = ShoppingItemMapper.item(from: ReminderSnapshot(id: "3", title: "Brot"), matcher: matcher)
        #expect(unsorted.storeRef == nil)
    }

    @Test(arguments: [
        ("Einkaufen", true), ("Einkaufsliste", true), ("Wocheneinkauf", true), ("Lebensmittel", true),
        ("Groceries", true), ("Shopping", true), ("Arbeit", false), ("Urlaub", false),
    ])
    func shoppingListHeuristics(_ title: String, _ expected: Bool) {
        #expect(ShoppingListHeuristics.isLikelyShoppingList(title) == expected)
    }
}
