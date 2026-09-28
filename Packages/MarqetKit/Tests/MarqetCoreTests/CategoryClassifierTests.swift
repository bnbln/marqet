import Foundation
import MarqetCore
import Testing

@Suite("CategoryClassifier")
struct CategoryClassifierTests {
    let classifier: CategoryClassifier

    init() throws {
        classifier = CategoryClassifier(dictionary: try CategoryDictionary.bundled())
    }

    /// Real-world shopping list entries (KONZEPT §11: goldset, target ≥ 90 % without AI).
    static let goldset: [(String, ItemCategory)] = [
        // Obst & Gemüse
        ("Bananen", .produce), ("Äpfel", .produce), ("2 kg Kartoffeln", .produce), ("Tomaten", .produce),
        ("Cherrytomaten", .produce), ("Rispentomaten", .produce), ("Gurke", .produce), ("Paprika rot", .produce),
        ("Zucchini", .produce), ("Zwiebeln", .produce), ("rote Zwiebeln", .produce), ("Knoblauch", .produce),
        ("Ingwer", .produce), ("Karotten", .produce), ("Möhren", .produce), ("Brokkoli", .produce),
        ("Blumenkohl", .produce), ("Spinat frisch", .produce), ("Feldsalat", .produce), ("Rucola", .produce),
        ("Eisbergsalat", .produce), ("Avocado", .produce), ("Zitronen", .produce), ("Limetten", .produce),
        ("Erdbeeren", .produce), ("Heidelbeeren", .produce), ("Weintrauben kernlos", .produce), ("Mango", .produce),
        ("Champignons", .produce), ("Frühlingszwiebeln", .produce), ("Petersilie", .produce), ("Basilikum", .produce),
        ("Schnittlauch", .produce), ("Süßkartoffeln", .produce), ("Lauch", .produce), ("Kohlrabi", .produce),
        ("Radieschen", .produce), ("Spargel weiß", .produce), ("Paradeiser", .produce), ("Erdäpfel", .produce),
        ("Rüebli", .produce), ("Bio-Äpfel", .produce), ("Kürbis", .produce), ("Rote Bete", .produce),
        // Brot & Backwaren
        ("Brot", .bakery), ("Vollkornbrot", .bakery), ("Brötchen", .bakery), ("6 Semmeln", .bakery),
        ("Toastbrot", .bakery), ("Laugenbrezeln", .bakery), ("Croissants", .bakery), ("Baguette", .bakery),
        ("Dinkelbrötchen", .bakery), ("Knäckebrot", .bakery), ("Wraps", .bakery), ("Aufbackbrötchen", .bakery),
        ("Kuchen", .bakery), ("Burgerbrötchen", .bakery),
        // Milchprodukte & Eier
        ("Milch", .dairyEggs), ("Milch 1,5%", .dairyEggs), ("H-Milch", .dairyEggs), ("Hafermilch", .dairyEggs),
        ("Butter", .dairyEggs), ("Sahne", .dairyEggs), ("Schlagsahne", .dairyEggs), ("Joghurt", .dairyEggs),
        ("Naturjoghurt", .dairyEggs), ("Griechischer Joghurt", .dairyEggs), ("Quark", .dairyEggs),
        ("Magerquark", .dairyEggs), ("Eier", .dairyEggs), ("10 Eier", .dairyEggs), ("Freilandeier", .dairyEggs),
        ("Schmand", .dairyEggs), ("Crème fraîche", .dairyEggs), ("Skyr", .dairyEggs), ("Margarine", .dairyEggs),
        ("Topfen", .dairyEggs), ("Schlagobers", .dairyEggs), ("Kefir", .dairyEggs), ("Buttermilch", .dairyEggs),
        ("Pudding", .dairyEggs), ("Tofu", .dairyEggs), ("Blätterteig", .dairyEggs), ("Pizzateig", .dairyEggs),
        // Käse
        ("Käse", .cheese), ("Gouda", .cheese), ("Mozzarella", .cheese), ("Parmesan", .cheese), ("Feta", .cheese),
        ("Frischkäse", .cheese), ("Reibekäse", .cheese), ("Scheibenkäse", .cheese), ("Bergkäse", .cheese),
        ("Camembert", .cheese), ("Halloumi", .cheese), ("Hüttenkäse", .cheese), ("Emmentaler", .cheese),
        ("Mascarpone", .cheese), ("Ziegenkäse", .cheese), ("Raclettekäse", .cheese),
        // Fleisch & Wurst
        ("Hackfleisch", .meat), ("500 g Hackfleisch gemischt", .meat), ("Hähnchenbrust", .meat), ("Schnitzel", .meat),
        ("Salami", .meat), ("Schinken", .meat), ("Kochschinken", .meat), ("Bratwurst", .meat), ("Wiener Würstchen", .meat),
        ("Speck", .meat), ("Leberwurst", .meat), ("Aufschnitt", .meat), ("Putenbrust", .meat), ("Rinderhack", .meat),
        ("Gulasch", .meat), ("Leberkäse", .meat), ("Faschiertes", .meat), ("Weißwürste", .meat), ("Bacon", .meat),
        ("Chicken Nuggets", .meat), ("Cervelat", .meat), ("Lyoner", .meat), ("Fleischwurst", .meat),
        // Fisch
        ("Lachs", .fish), ("Räucherlachs", .fish), ("Thunfisch", .fish), ("Garnelen", .fish), ("Forelle", .fish),
        ("Matjes", .fish), ("Lachsfilet", .fish), ("Seelachs", .fish),
        // Frühstück
        ("Müsli", .breakfast), ("Haferflocken", .breakfast), ("Cornflakes", .breakfast), ("Marmelade", .breakfast),
        ("Erdbeermarmelade", .breakfast), ("Honig", .breakfast), ("Nutella", .breakfast), ("Erdnussbutter", .breakfast),
        ("Konfitüre", .breakfast), ("Granola", .breakfast), ("Kakao", .breakfast),
        // Vorrat
        ("Nudeln", .pantry), ("Spaghetti", .pantry), ("Penne", .pantry), ("Reis", .pantry), ("Basmatireis", .pantry),
        ("Mehl", .pantry), ("Zucker", .pantry), ("Salz", .pantry), ("Olivenöl", .pantry), ("Sonnenblumenöl", .pantry),
        ("Essig", .pantry), ("Senf", .pantry), ("Ketchup", .pantry), ("Mayonnaise", .pantry), ("Tomatenmark", .pantry),
        ("Passierte Tomaten", .pantry), ("Pesto", .pantry), ("Gemüsebrühe", .pantry), ("Linsen", .pantry),
        ("Kichererbsen", .pantry), ("Kokosmilch", .pantry), ("Sojasauce", .pantry), ("Couscous", .pantry),
        ("Tortellini", .pantry), ("Gnocchi", .pantry), ("Spätzle", .pantry), ("Oliven", .pantry), ("Essiggurken", .pantry),
        ("Walnüsse", .pantry), ("Mandeln", .pantry), ("Kidneybohnen", .pantry), ("Pfeffer", .pantry), ("Currypulver", .pantry),
        ("Semmelbrösel", .pantry), ("Apfelmus", .pantry), ("Lasagneplatten", .pantry), ("Vollkornnudeln", .pantry),
        // Backzutaten
        ("Backpulver", .baking), ("Puderzucker", .baking), ("Vanillezucker", .pantry), ("Hefe", .pantry),
        ("Speisestärke", .baking), ("Gelatine", .baking), ("Kuvertüre", .baking), ("Backpapier", .baking),
        ("Dinkelmehl", .baking), ("Kokosraspeln", .baking),
        // Snacks & Süßes
        ("Chips", .snacks), ("Chips Paprika", .snacks), ("Schokolade", .snacks), ("Zartbitterschokolade", .snacks),
        ("Gummibärchen", .snacks), ("Kekse", .snacks), ("Salzstangen", .snacks), ("Erdnussflips", .snacks),
        ("Popcorn", .snacks), ("Schokoriegel", .snacks), ("Butterkekse", .snacks), ("Studentenfutter", .snacks),
        ("Reiswaffeln", .snacks), ("Milchschokolade", .snacks),
        // Tiefkühl
        ("Tiefkühlpizza", .frozen), ("Pizza", .frozen), ("Pommes", .frozen), ("Eis", .frozen), ("Vanilleeis", .frozen),
        ("Fischstäbchen", .frozen), ("Rahmspinat", .frozen), ("TK Erbsen", .frozen), ("Eiswürfel", .frozen),
        ("Kroketten", .frozen),
        // Getränke
        ("Wasser", .beverages), ("Mineralwasser", .beverages), ("Orangensaft", .beverages), ("Apfelsaft", .beverages),
        ("Cola", .beverages), ("Cola Zero", .beverages), ("Kaffee", .beverages), ("Kaffeebohnen", .beverages),
        ("Tee", .beverages), ("Pfefferminztee", .beverages), ("Eistee", .beverages), ("Apfelschorle", .beverages),
        ("Kaffeepads", .beverages), ("Almdudler", .beverages), ("Rivella", .beverages), ("Sprudel", .beverages),
        // Alkohol
        ("Bier", .alcohol), ("Rotwein", .alcohol), ("Weißwein", .alcohol), ("Sekt", .alcohol), ("Prosecco", .alcohol),
        ("Radler", .alcohol), ("Gin", .alcohol), ("Aperol", .alcohol), ("Weißbier", .alcohol),
        // Drogerie & Pflege
        ("Zahnpasta", .personalCare), ("Zahnbürste", .personalCare), ("Shampoo", .personalCare),
        ("Duschgel", .personalCare), ("Deo", .personalCare), ("Sonnencreme", .personalCare), ("Handcreme", .personalCare),
        ("Taschentücher", .personalCare), ("Pflaster", .personalCare), ("Rasierklingen", .personalCare),
        ("Wattepads", .personalCare), ("Tampons", .personalCare), ("Ibuprofen", .personalCare), ("Kinderzahnpasta", .personalCare),
        ("Mundspülung", .personalCare), ("Zahnseide", .personalCare),
        // Haushalt
        ("Klopapier", .household), ("Toilettenpapier", .household), ("Küchenrolle", .household), ("Spülmittel", .household),
        ("Spülmaschinentabs", .household), ("Waschmittel", .household), ("Weichspüler", .household), ("Müllbeutel", .household),
        ("Alufolie", .household), ("Frischhaltefolie", .household), ("Batterien AA", .household), ("Allzweckreiniger", .household),
        ("Glühbirne", .household), ("Teelichter", .household), ("Schwämme", .household), ("WC-Reiniger", .household),
        ("Grillkohle", .household), ("Gefrierbeutel", .household),
        // Baby
        ("Windeln", .baby), ("Babybrei", .baby), ("Folgemilch", .baby), ("Feuchttücher Baby", .baby),
        // Tier
        ("Katzenfutter", .pet), ("Hundefutter", .pet), ("Katzenstreu", .pet), ("Leckerlis", .pet),
        // Englisch
        ("Milk", .dairyEggs), ("Eggs", .dairyEggs), ("Bread", .bakery), ("Bananas", .produce), ("Chicken", .meat),
        ("Toilet paper", .household), ("Coffee", .beverages), ("Cheese", .cheese), ("Toothpaste", .personalCare),
        ("Rice", .pantry), ("Beer", .alcohol), ("Ice cream", .frozen),
    ]

    @Test(arguments: ["Spinat TK", "TK Erbsen", "Erbsen tiefgekühlt", "Himbeeren gefroren", "Frozen peas"])
    func freezerMarkerWinsOverTheFirstWord(_ title: String) throws {
        let classifier = CategoryClassifier(dictionary: try CategoryDictionary.bundled())
        #expect(classifier.classify(title).category == .frozen)
    }

    @Test func goldsetAccuracyIsAtLeast90Percent() {
        var misses: [String] = []
        for (title, expected) in Self.goldset {
            let actual = classifier.classify(title).category
            if actual != expected { misses.append("\(title): \(actual.rawValue) ≠ \(expected.rawValue)") }
        }
        let accuracy = 1 - Double(misses.count) / Double(Self.goldset.count)
        #expect(accuracy >= 0.9, "Accuracy \(Int(accuracy * 100)) %, misses: \(misses.joined(separator: "; "))")
        print("Goldset: \(Self.goldset.count) items, accuracy \(String(format: "%.1f", accuracy * 100)) %, misses: \(misses)")
    }

    @Test func dictionaryIsLarge() {
        // ≈ 1.000 Begriffe in v1 (Ziel laut Konzept ≈ 2.500, Ausbau mit echten Beta-Listen).
        #expect(classifier.dictionary.wordCount >= 950)
        print("Dictionary: \(classifier.dictionary.wordCount) words")
    }

    @Test(arguments: [
        ("Vollkornbrot", ItemCategory.bakery),     // compound head
        ("Basmatireis", .pantry),                  // longest suffix wins over "eis"
        ("Speiseeis", .frozen),
        ("Kinderzahnpasta", .personalCare),        // "zahnpasta" beats "pasta"
        ("Tomatenmark", .pantry),                  // exception
        ("Milch laktosefrei", .dairyEggs),         // head first
        ("Chips Paprika", .snacks),                // first matching word wins
        ("Kürbiskernöl", .pantry),                 // "öl" folds to "oel", long enough for compounds
        ("2x Bio-Milch", .dairyEggs),              // quantity and hyphen
    ])
    func rules(_ title: String, _ expected: ItemCategory) {
        #expect(classifier.classify(title).category == expected)
    }

    @Test func unknownIsOtherFromFallback() {
        let match = classifier.classify("Geschenkpapier")
        #expect(match == CategoryMatch(category: .other, source: .fallback))
    }

    @Test func correctionWinsOverDictionary() {
        var classifier = classifier
        classifier.learned[ItemKeyNormalizer.matchingKey(for: "Milch")] = (.beverages, true)
        #expect(classifier.classify("Milch") == CategoryMatch(category: .beverages, source: .userCorrection))
        #expect(classifier.classify("milch!") == CategoryMatch(category: .beverages, source: .userCorrection))
    }
}

@Suite("SectionBuilder")
struct SectionBuilderTests {
    let classifier = CategoryClassifier(dictionary: try! CategoryDictionary.bundled())

    func items(_ titles: [String]) -> [ShoppingItem] {
        titles.map { ShoppingItem(id: $0, title: $0) }
    }

    @Test func grocerySectionsFollowDefaultOrder() {
        let sections = SectionBuilder.sections(
            items: items(["Milch", "Bananen", "Brot", "Pizza", "Butter"]),
            storeType: .discounter,
            category: { classifier.classify($0.title).category }
        )
        #expect(sections.map(\.category) == [.produce, .bakery, .dairyEggs, .frozen])
        #expect(sections[2].items.map(\.title) == ["Butter", "Milch"])
    }

    @Test func drugstoreIsFlat() {
        let sections = SectionBuilder.sections(items: items(["Zahnpasta", "Shampoo"]), storeType: .drugstore,
                                               category: { classifier.classify($0.title).category })
        #expect(sections.count == 1)
        #expect(sections[0].category == nil)
    }

    @Test func unsortedIsFlat() {
        let sections = SectionBuilder.sections(items: items(["Milch"]), storeType: nil,
                                               category: { classifier.classify($0.title).category })
        #expect(sections.map(\.category) == [nil])
    }

    @Test func manualCategoryOrderIsRespected() {
        let positions = RouteLearner.manualPositions(for: [.frozen, .dairyEggs, .produce])
        let order = SectionBuilder.categoryOrder(positions)
        #expect(Array(order.prefix(1)) == [.frozen])
        #expect(order.firstIndex(of: .dairyEggs)! < order.firstIndex(of: .produce)!)
    }

    @Test func learnedItemPositionsPutUnknownFirst() {
        let positions: [String: OrderPosition] = ["milch": .init(value: 0.2), "butter": .init(value: 0.8)]
        let sections = SectionBuilder.sections(
            items: items(["Butter", "Quark", "Milch"]), storeType: .supermarket,
            category: { _ in .dairyEggs }, ordering: .init(itemPositions: positions)
        )
        #expect(sections[0].items.map(\.title) == ["Quark", "Milch", "Butter"])
    }
}
