import MarqetCore
import Testing

@Suite("ItemKeyNormalizer")
struct ItemKeyNormalizerTests {
    @Test(arguments: [
        ("Milch", "milch"),
        ("  Milch  ", "milch"),
        ("Milch!", "milch"),
        ("Milch...", "milch"),
        ("2x Bio-Milch 1,5%  ", "bio-milch 1,5%"),
        ("2 x Milch", "milch"),
        ("2× Milch", "milch"),
        ("500 g Hackfleisch", "hackfleisch"),
        ("500g Hackfleisch", "hackfleisch"),
        ("1,5 kg Kartoffeln", "kartoffeln"),
        ("3 Stück Paprika", "paprika"),
        ("3 Eier", "eier"),
        ("2 Dosen Tomaten", "tomaten"),
        ("1 l Milch", "milch"),
        ("6 Flaschen Wasser", "wasser"),
        ("3 lachs", "lachs"),
        ("Milch 2x", "milch"),
        ("Milch x2", "milch"),
        ("Eier 10 Stück", "eier"),
        ("Tomaten   passiert", "tomaten passiert"),
        ("7up", "7up"),
        ("Coca-Cola Zero", "coca-cola zero"),
    ])
    func key(_ title: String, _ expected: String) {
        #expect(ItemKeyNormalizer.key(for: title) == expected)
    }

    @Test func matchingKeyFoldsUmlautsAndCase() {
        let expected = "kaese"
        #expect(ItemKeyNormalizer.matchingKey(for: "Käse") == expected)
        #expect(ItemKeyNormalizer.matchingKey(for: "KÄSE") == expected)
        #expect(ItemKeyNormalizer.matchingKey(for: "Kaese") == expected)
        // Decomposed "ä" (a + combining diaeresis), as some keyboards produce it.
        #expect(ItemKeyNormalizer.matchingKey(for: "Ka\u{0308}se") == expected)
    }

    @Test func matchingKeyFoldsOtherDiacriticsAndEszett() {
        #expect(ItemKeyNormalizer.matchingKey(for: "Crème fraîche") == "creme fraiche")
        #expect(ItemKeyNormalizer.matchingKey(for: "Weißwurst") == "weisswurst")
    }

    @Test(arguments: [
        ("Aldi Süd", "aldisued"),
        ("ALDI SÜD", "aldisued"),
        ("Aldi-Sued", "aldisued"),
        ("denn's Biomarkt", "dennsbiomarkt"),
        ("dm-drogerie markt", "dmdrogeriemarkt"),
        ("Billa Plus", "billaplus"),
    ])
    func storeNameKey(_ name: String, _ expected: String) {
        #expect(ItemKeyNormalizer.storeNameKey(name) == expected)
    }
}
