import Foundation
import MarqetCore
import Testing

@Suite("StoreMatcher & DetectedStoreFactory")
struct StoreMatcherTests {
    static func store(_ name: String, aliases: [String] = [], sortIndex: Int = 0) -> Store {
        Store(name: name, aliases: aliases, colorHex: "#000000", symbol: .monogram("X"),
              sortIndex: sortIndex, origin: .catalog, type: .supermarket)
    }

    let aldiSued = store("Aldi Süd", aliases: ["Aldi Sued"])
    let aldiNord = store("Aldi Nord")
    let dm = store("dm", aliases: ["dm-drogerie markt"])
    let rewe = store("Rewe")

    @Test(arguments: ["Aldi Süd", "aldi süd", "ALDI SÜD", "Aldi-Sued", "aldi sued", " Aldi  Süd "])
    func exactNameVariants(_ name: String) {
        let matcher = StoreMatcher(stores: [aldiSued, aldiNord, dm])
        #expect(matcher.store(named: name) == aldiSued)
    }

    @Test func aliasMatches() {
        let matcher = StoreMatcher(stores: [aldiSued, dm])
        #expect(matcher.store(named: "dm-drogerie markt") == dm)
        #expect(matcher.store(named: "DM Drogerie Markt") == dm)
    }

    @Test func uniquePrefixMatches() {
        let matcher = StoreMatcher(stores: [aldiSued, dm, rewe])
        #expect(matcher.store(named: "Aldi") == aldiSued)
        #expect(matcher.store(named: "rew") == rewe)
    }

    @Test func ambiguousPrefixDoesNotMatch() {
        let matcher = StoreMatcher(stores: [aldiSued, aldiNord])
        #expect(matcher.store(named: "Aldi") == nil)
    }

    @Test func shortPrefixDoesNotMatch() {
        let matcher = StoreMatcher(stores: [rewe])
        #expect(matcher.store(named: "re") == nil)
    }

    @Test func unknownAndEmptyDoNotMatch() {
        let matcher = StoreMatcher(stores: [aldiSued, dm])
        #expect(matcher.store(named: "Metzger Huber") == nil)
        #expect(matcher.store(named: "") == nil)
        #expect(matcher.store(named: "!!!") == nil)
    }

    @Test func nameWinsOverForeignAlias() {
        let billa = Self.store("Billa")
        let billaPlus = Self.store("Billa Plus", aliases: ["Billa"])
        let matcher = StoreMatcher(stores: [billaPlus, billa])
        #expect(matcher.store(named: "Billa") == billa)
    }

    @Test func detectedStoresAreDedupedAndAppended() {
        let existing = [Self.store("Rewe", sortIndex: 4)]
        let created = DetectedStoreFactory.makeStores(
            forUnresolved: ["Metzger Huber", "metzger huber", "Hofladen", "REWE", ""],
            existing: existing
        )
        #expect(created.map(\.name) == ["Metzger Huber", "Hofladen"])
        #expect(created.map(\.sortIndex) == [5, 6])
        #expect(created.allSatisfy { $0.origin == .detected })
    }

    @Test func catalogChainsAreRecognizedExactly() throws {
        let catalog = try StoreCatalog.bundled().stores
        let created = DetectedStoreFactory.makeStores(
            forUnresolved: ["aldi sued", "ALDI SÜD", "Aldi", "Bäckerei"],
            existing: [],
            catalog: catalog
        )
        // "aldi sued" and "ALDI SÜD" are the same chain; "Aldi" alone is ambiguous → neutral store.
        #expect(created.map(\.name) == ["Aldi Süd", "Aldi", "Bäcker"])
        #expect(created.map(\.origin) == [.catalog, .detected, .catalog])
        #expect(created[0].catalogKey == "aldi-sued")
        #expect(created[0].symbol == .monogram("AS"))
    }

    @Test func catalogChainIsNotCreatedTwice() throws {
        let catalog = try StoreCatalog.bundled().stores
        let existing = try #require(catalog.first { $0.key == "rewe" }).makeStore(sortIndex: 0)
        let created = DetectedStoreFactory.makeStores(forUnresolved: ["REWE City"], existing: [existing], catalog: catalog)
        #expect(created.isEmpty)
    }
}
