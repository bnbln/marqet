import MarqetCore

extension ItemCategory {
    var displayName: String {
        switch self {
        case .produce: String(localized: "Obst & Gemüse")
        case .bakery: String(localized: "Brot & Backwaren")
        case .dairyEggs: String(localized: "Milchprodukte & Eier")
        case .cheese: String(localized: "Käse")
        case .meat: String(localized: "Fleisch & Wurst")
        case .fish: String(localized: "Fisch")
        case .breakfast: String(localized: "Frühstück & Aufstriche")
        case .pantry: String(localized: "Vorrat")
        case .baking: String(localized: "Backzutaten")
        case .snacks: String(localized: "Snacks & Süßes")
        case .frozen: String(localized: "Tiefkühl")
        case .beverages: String(localized: "Getränke")
        case .alcohol: String(localized: "Wein, Bier & Spirituosen")
        case .personalCare: String(localized: "Drogerie & Pflege")
        case .household: String(localized: "Haushalt")
        case .baby: String(localized: "Baby")
        case .pet: String(localized: "Tier")
        case .other: String(localized: "Sonstiges")
        }
    }

    var symbol: String {
        switch self {
        case .produce: "carrot"
        case .bakery: "birthday.cake"
        case .dairyEggs: "drop"
        case .cheese: "triangle.bottomhalf.filled"
        case .meat: "fork.knife"
        case .fish: "fish"
        case .breakfast: "sun.horizon"
        case .pantry: "cabinet"
        case .baking: "whisk"
        case .snacks: "popcorn"
        case .frozen: "snowflake"
        case .beverages: "waterbottle"
        case .alcohol: "wineglass"
        case .personalCare: "comb"
        case .household: "house"
        case .baby: "figure.and.child.holdinghands"
        case .pet: "pawprint"
        case .other: "square.grid.2x2"
        }
    }
}
