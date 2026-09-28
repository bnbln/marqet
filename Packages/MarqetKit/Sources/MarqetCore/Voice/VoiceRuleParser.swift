import Foundation

/// Language of a dictation. Vocabulary is shared (people mix "Rewe" and "grocery store"),
/// only rules that depend on grammar differ.
public enum VoiceLanguage: Sendable {
    case german, english

    public init(languageCode: String?) {
        self = languageCode?.lowercased().hasPrefix("en") == true ? .english : .german
    }
}

/// Rule-based reading of a shopping dictation in German or English (KONZEPT §3.3).
///
/// It runs on every transcript update, so the lists build up while the user speaks – also on
/// devices without Apple Intelligence and for Free. The language model (Pro) refines the result
/// afterwards; these rules only need to be fast, predictable and good at the common phrasings:
///
///     "Ich brauche 10 Eier und will sie auf dem Markt kaufen, genau wie Suppengrün.
///      Bei Rewe will ich 500 g Hackfleisch kaufen. Ah, und ich brauche Zwiebeln vom Markt."
///
/// Sentences split at `.!?;`, clauses at commas, colons and connectors ("und", "sowie",
/// "genau wie"). Where an item's store comes from, in this order:
/// 1. its own clause ("Zwiebeln vom Markt"),
/// 2. another clause of its sentence – the one before first ("10 Eier, die will ich auf dem Markt kaufen"),
/// 3. the next sentence, if that one names only a store ("Ich brauche Milch. Die hole ich bei Rewe."),
/// 4. the sentence before, if this one continues it ("Und Butter.", "Genau wie Suppengrün.") or
///    if that one only announced a store ("Bei Rewe brauche ich einiges. Milch, Butter.").
public enum VoiceRuleParser {
    public static func parse(_ transcript: String, lexicon: SpokenStoreLexicon, language: VoiceLanguage = .german) -> [SpokenEntry] {
        var entries: [SpokenEntry] = []
        /// Last store named in the previous sentence.
        var carriedStore: String?
        /// Announced by a sentence without items, for the sentences that follow.
        var announcedStore: String?
        /// Indices in `entries` of the previous sentence's items without a store.
        var previousOpen: [Int] = []

        for sentence in sentences(in: tokens(in: transcript)) {
            let clauses = self.clauses(in: sentence, lexicon: lexicon, language: language)
            let sentenceStore = clauses.last(where: { $0.store != nil })?.store
            // "Butter." after "Bei Rewe Milch." – the transcriber sets a period at every pause, so a
            // bare enumeration continues the sentence before; "Ich brauche Zahnpasta." does not.
            let isBare = sentenceStore == nil && clauses.allSatisfy { $0.fillerCount == 0 }
            let continues = opensWithContinuation(sentence, language: language) || isBare
            let sentenceStart = entries.count
            var open: [Int] = []

            for (index, clause) in clauses.enumerated() where !clause.items.isEmpty {
                // "500 g Kartoffeln, mehligkochend": a lowercase clause describes the item before it
                // (German transcripts capitalize nouns).
                if language == .german, clause.store == nil, entries.count > sentenceStart,
                   let item = clause.items.first, item.isAttribute, item.quantity == nil {
                    entries[entries.count - 1].name += ", " + item.name.lowercased()
                    continue
                }
                let preceding = clauses[..<index].last(where: { $0.store != nil })?.store
                let following = clauses[(index + 1)...].first(where: { $0.store != nil })?.store
                let continued = (continues || (index == 0 && clause.continues)) ? carriedStore : nil
                let store = clause.store ?? preceding ?? following ?? continued ?? announcedStore
                for item in clause.items {
                    if store == nil { open.append(entries.count) }
                    entries.append(SpokenEntry(name: item.name, quantity: item.quantity, storeName: store))
                }
            }

            let hasItems = entries.count > sentenceStart
            if let store = sentenceStore {
                if hasItems {
                    announcedStore = nil
                } else if !previousOpen.isEmpty {
                    // A sentence that only names a store refers back ("Die hole ich bei Rewe.").
                    for index in previousOpen { entries[index].storeName = store }
                    announcedStore = nil
                } else {
                    // … or, with nothing open before it, announces the store for what follows.
                    announcedStore = store
                }
                carriedStore = store
            } else if hasItems, !continues, announcedStore == nil {
                // A fresh sentence without a store ends the thought of the one before.
                carriedStore = nil
            }
            if hasItems || sentenceStore != nil { previousOpen = open }
        }
        return entries
    }

    /// The store the user talked about last – its card is highlighted while listening.
    public static func lastStoreMention(in transcript: String, lexicon: SpokenStoreLexicon) -> String? {
        let words = tokens(in: transcript).filter { !$0.isPunctuation }.map(\.folded)
        var start = 0
        var last: String?
        while let match = lexicon.firstMatch(in: words, from: start) {
            last = match.name
            start = match.range.upperBound
        }
        return last
    }

    // MARK: Tokens

    struct Token {
        let text: String
        let folded: String
        let isNumber: Bool
        let isPunctuation: Bool
        /// "Bio-Milch": "Milch" is glued to "Bio" by a hyphen.
        let isHyphenated: Bool
    }

    static func tokens(in transcript: String) -> [Token] {
        var tokens: [Token] = []
        var previousEnd: String.Index?
        for match in transcript.matches(of: #/\d+(?:[.,]\d+)?|[\p{L}][\p{L}\p{N}]*|[.,!?;:]/#) {
            let text = String(match.output)
            let isHyphenated = previousEnd.map { end in
                match.range.lowerBound > end
                    && transcript[end..<match.range.lowerBound] == "-"
            } ?? false
            tokens.append(Token(
                text: text,
                folded: ItemKeyNormalizer.fold(text),
                isNumber: text.first?.isNumber == true,
                isPunctuation: text.count == 1 && ".,!?;:".contains(text),
                isHyphenated: isHyphenated
            ))
            previousEnd = match.range.upperBound
        }
        return tokens
    }

    /// Sentences end at `.!?;` – a colon introduces a list ("Bei Rewe: Milch, Butter").
    private static func sentences(in tokens: [Token]) -> [[Token]] {
        tokens.split(whereSeparator: { $0.isPunctuation && ".!?;".contains($0.text) }).map(Array.init)
    }

    /// "Und Butter.", "Außerdem Käse.", "Genau wie Suppengrün.", "Also some milk." – also after
    /// interjections like "Ah,".
    private static func opensWithContinuation(_ sentence: [Token], language: VoiceLanguage) -> Bool {
        let words = Array(sentence.filter { !$0.isPunctuation }.map(\.folded).drop(while: { interjections.contains($0) }))
        guard let first = words.first else { return false }
        if markerLength(at: words) != nil { return true }
        return sentenceContinuations.contains(first) || (language == .english && first == "also")
    }

    // MARK: Clauses

    struct Clause {
        var store: String?
        var items: [(name: String, quantity: String?, isAttribute: Bool)]
        /// Starts with "genau wie" / "sowie" / "as well as": continues the previous thought.
        var continues: Bool
        /// Words besides store and item ("ich brauche") – a clause without any is a bare enumeration.
        var fillerCount = 0
    }

    private static func clauses(in sentence: [Token], lexicon: SpokenStoreLexicon, language: VoiceLanguage) -> [Clause] {
        var raw: [(tokens: [Token], continues: Bool)] = []
        var current: [Token] = []
        var continues = false
        var index = 0
        func close(nextContinues: Bool) {
            if !current.isEmpty { raw.append((current, continues)) }
            current = []
            continues = nextContinues
        }
        let folded = sentence.map(\.folded)
        while index < sentence.count {
            let token = sentence[index]
            if token.isPunctuation {
                close(nextContinues: false)
            } else if let length = markerLength(at: Array(folded[index...])) {
                close(nextContinues: true)
                index += length - 1
            } else if continuationWords.contains(token.folded) || (language == .english && token.folded == "also") {
                close(nextContinues: true)
            } else if connectorWords.contains(token.folded) {
                close(nextContinues: continues && current.isEmpty)
            } else {
                current.append(token)
            }
            index += 1
        }
        close(nextContinues: false)
        return raw.map { clause(from: $0.tokens, continues: $0.continues, lexicon: lexicon) }
    }

    /// Length of a multi-word continuation marker ("genau wie", "as well as") at the start of `words`.
    private static func markerLength(at words: [String]) -> Int? {
        continuationMarkers.first { marker in
            words.count >= marker.count && Array(words.prefix(marker.count)) == marker
        }?.count
    }

    private static func clause(from tokens: [Token], continues: Bool, lexicon: SpokenStoreLexicon) -> Clause {
        var remaining = tokens
        var store: String?
        // Remove every store mention with its preposition ("auf dem Markt", "at the market")
        // and a trailing "Markt"/"store" of the chain ("Rewe-Markt", "Aldi store", "Lidl's").
        while let match = lexicon.firstMatch(in: remaining.map(\.folded)) {
            store = store ?? match.name
            var lower = match.range.lowerBound
            while lower > 0, storePrepositions.contains(remaining[lower - 1].folded) { lower -= 1 }
            var upper = match.range.upperBound
            while upper < remaining.count, storeSuffixes.contains(remaining[upper].folded) { upper += 1 }
            remaining.removeSubrange(lower..<upper)
        }
        let words = remaining.filter { !fillerWords.contains($0.folded) }
        let fillerCount = remaining.filter { fillerWords.contains($0.folded) && !interjections.contains($0.folded) }.count
        guard let item = item(from: words) else {
            return Clause(store: store, items: [], continues: continues, fillerCount: fillerCount)
        }
        return Clause(store: store, items: [item], continues: continues, fillerCount: fillerCount)
    }

    // MARK: Items & quantities

    private static func item(from words: [Token]) -> (name: String, quantity: String?, isAttribute: Bool)? {
        var words = words
        var quantity = leadingQuantity(in: &words)
        if quantity == nil {
            words.reverse()
            // Trailing: "Hackfleisch 500 Gramm" – read backwards, unit before amount.
            if let unit = words.first.flatMap({ units[$0.folded] }), words.count > 1, let amount = amount(of: words[1]) {
                quantity = "\(amount) \(unit ?? words[0].text)"
                words.removeFirst(2)
            } else if let first = words.first, first.isNumber {
                quantity = first.text
                words.removeFirst()
            }
            words.reverse()
        }
        guard words.contains(where: { !$0.isNumber && $0.text.count >= 2 }) else { return nil }
        var name = ""
        for (index, word) in words.enumerated() {
            if index > 0 { name += word.isHyphenated ? "-" : " " }
            name += word.text
        }
        let isAttribute = words.allSatisfy { $0.text.first?.isLowercase == true }
        return (name.prefix(1).uppercased() + name.dropFirst(), quantity, isAttribute)
    }

    /// "10", "zehn", "500 g", "ein Kilo", "ein halbes Kilo", "2 Packungen", "a dozen",
    /// "half a pound", "2 cans of". Consumes the tokens.
    private static func leadingQuantity(in words: inout [Token]) -> String? {
        var index = 0
        var value: String?
        var fromArticle = false
        if let first = words.first {
            if let amount = amount(of: first) {
                value = amount
                index = 1
            } else if articles.contains(first.folded) {
                value = "1"
                fromArticle = true
                index = 1
            }
        }
        if index < words.count, halfWords.contains(words[index].folded) {
            value = "0,5"
            fromArticle = false
            index += 1
            if index < words.count, articles.contains(words[index].folded) { index += 1 }
        }
        if index < words.count, words[index].folded == "dozen" {
            value = String((Int(value ?? "1") ?? 1) * 12)
            fromArticle = false
            index += 1
        }
        var unit: String?
        if index < words.count, let known = units[words[index].folded], known != nil || value != nil {
            // A word unit needs an amount ("2 Dosen"); alone it is part of the name ("Dose Tomaten").
            unit = known ?? words[index].text
            index += 1
        }
        if index < words.count, words[index].folded == "of", unit != nil || (value != nil && !fromArticle) { index += 1 }
        if unit == nil, fromArticle {
            // "eine Gurke", "an onion": the article is no quantity, but no part of the name either.
            words.removeFirst()
            return nil
        }
        if value == nil, unit != nil { value = "1" }
        guard let value, index < words.count || unit == nil else {
            // Only a quantity, no item ("2 Packungen"): keep the words as the item.
            return nil
        }
        words.removeFirst(index)
        return unit.map { "\(value) \($0)" } ?? value
    }

    private static func amount(of token: Token) -> String? {
        if token.isNumber { return token.text }
        return numberWords[token.folded]
    }

    // MARK: Vocabulary (folded, German and English)

    private static let connectorWords: Set<String> = ["und", "ausserdem", "dann", "plus", "and", "then"]
    private static let continuationWords: Set<String> = ["sowie", "ebenso", "ebenfalls"]
    /// Words that open a sentence continuing the one before.
    private static let sentenceContinuations: Set<String> = [
        "und", "ausserdem", "auch", "dazu", "noch", "sowie", "ebenso", "plus", "and", "too",
    ]
    private static let continuationMarkers: [[String]] = [
        ["genau", "wie"], ["so", "wie"], ["ebenso", "wie"], ["zusammen", "mit"],
        ["as", "well", "as"], ["along", "with"], ["same", "as"], ["just", "like"], ["together", "with"],
    ]
    private static let interjections: Set<String> = [
        "ah", "aeh", "aehm", "ahm", "oh", "hm", "hmm", "ok", "okay", "ja", "achja", "uh", "um", "well", "right", "oops",
    ]

    private static let storePrepositions: Set<String> = [
        "bei", "beim", "vom", "von", "im", "in", "auf", "aus", "dem", "der", "den", "zum", "zur",
        "am", "an", "fuer", "fuers", "ins", "zu", "nach",
        "at", "from", "the", "to", "for", "on",
    ]
    private static let storeSuffixes: Set<String> = ["s", "markt", "filiale", "store", "shop", "supermarket"]

    private static let fillerWords: Set<String> = [
        // German
        "ich", "wir", "du", "man", "mir", "uns", "sie", "es", "er", "die", "das", "der", "den", "dem", "des",
        "brauche", "brauchen", "braucht", "benoetige", "benoetigen", "will", "wollen", "moechte", "moechten",
        "haette", "haetten", "gern", "gerne", "kaufen", "kaufe", "holen", "hole", "besorgen", "besorge",
        "mitbringen", "mitnehmen", "einkaufen", "noch", "auch", "bitte", "mal", "ah", "aeh", "aehm", "ahm",
        "oh", "hm", "hmm", "ok", "okay", "genau", "wie", "also", "jetzt", "heute", "morgen", "schnell",
        "unbedingt", "nicht", "vergessen", "soll", "sollen", "muss", "muessen", "gehe", "gehen", "fahre",
        "fahren", "dort", "da", "dazu", "davon", "etwas", "paar", "bisschen", "und", "oder", "aber", "ja",
        "nein", "doch", "nachher", "gleich", "spaeter", "vorher", "naechste", "woche", "liste", "einkaufsliste",
        "brauchst", "hol", "kauf", "wollte", "sollte", "wuerde", "einiges", "sachen", "dinge", "zeug",
        "folgendes", "folgende", "was", "alles", "beides", "dafuer", "ausserdem", "ebenfalls", "dann",
        // English
        "i", "we", "you", "me", "my", "our", "need", "needs", "want", "wanna", "would", "like", "to", "buy",
        "get", "grab", "pick", "up", "some", "please", "uh", "um", "it", "them", "they", "those", "these",
        "that", "this", "the", "too", "or", "but", "yes", "no", "just", "still", "more", "there", "have",
        "has", "got", "gotta", "go", "going", "shop", "shopping", "list", "dont", "don", "forget", "ll", "m",
        "d", "s", "ve", "re", "t", "things", "stuff", "few", "couple", "following", "should", "must",
        "lets", "let", "us", "well", "anything", "something", "everything", "both", "else", "then",
        "and", "plus", "same", "for", "will", "can",
    ]

    private static let articles: Set<String> = ["ein", "eine", "einen", "einem", "einer", "eins", "a", "an", "one"]
    private static let halfWords: Set<String> = ["halb", "halbe", "halbes", "halben", "half"]

    private static let numberWords: [String: String] = [
        "zwei": "2", "drei": "3", "vier": "4", "fuenf": "5", "sechs": "6", "sieben": "7", "acht": "8",
        "neun": "9", "zehn": "10", "elf": "11", "zwoelf": "12", "fuenfzehn": "15", "zwanzig": "20",
        "dreissig": "30", "vierzig": "40", "fuenfzig": "50", "hundert": "100",
        "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8",
        "nine": "9", "ten": "10", "eleven": "11", "twelve": "12", "fifteen": "15", "twenty": "20",
        "thirty": "30", "forty": "40", "fifty": "50", "hundred": "100",
    ]

    /// Known units; `nil` keeps the spoken word ("2 Dosen", "2 cans").
    private static let units: [String: String?] = [
        "g": "g", "gr": "g", "gramm": "g", "gram": "g", "grams": "g",
        "kg": "kg", "kilo": "kg", "kilos": "kg", "kilogramm": "kg", "kilogram": "kg", "kilograms": "kg",
        "l": "l", "liter": "l", "liters": "l", "litre": "l", "litres": "l", "ml": "ml", "milliliter": "ml",
        "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb", "pfund": "Pfund",
        "oz": "oz", "ounce": "oz", "ounces": "oz",
        "stueck": "Stück", "stk": "Stück", "packung": nil, "packungen": nil, "pack": nil, "packs": nil,
        "dose": nil, "dosen": nil, "flasche": nil, "flaschen": nil, "bund": nil, "becher": nil,
        "glas": nil, "glaeser": nil, "netz": nil, "tuete": nil, "tueten": nil, "beutel": nil,
        "kiste": nil, "kisten": nil, "tafel": nil, "tafeln": nil, "rolle": nil, "rollen": nil,
        "scheiben": nil, "kopf": nil, "koepfe": nil,
        "package": nil, "packages": nil, "cans": nil, "bottle": nil, "bottles": nil,
        "bag": nil, "bags": nil, "bunch": nil, "bunches": nil, "box": nil, "boxes": nil, "jar": nil,
        "jars": nil, "loaf": nil, "loaves": nil, "head": nil, "heads": nil, "piece": nil, "pieces": nil,
        "carton": nil, "cartons": nil, "slices": nil,
    ]
}
