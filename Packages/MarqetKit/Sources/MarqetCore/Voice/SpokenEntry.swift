import Foundation

/// One shopping item heard in a dictation (KONZEPT §3): "500 g Hackfleisch bei Rewe".
///
/// `storeName` is what the parser recognized – a canonical name from the lexicon or, from the
/// language model, one of the offered store names. The app resolves it to a store.
public struct SpokenEntry: Hashable, Sendable {
    public var name: String
    public var quantity: String?
    public var storeName: String?

    public init(name: String, quantity: String? = nil, storeName: String? = nil) {
        self.name = name
        self.quantity = quantity
        self.storeName = storeName
    }

    /// Reminder title, quantity first like people write it: "500 g Kartoffeln".
    /// `ItemKeyNormalizer` strips the quantity again, so learning keys stay "kartoffeln".
    public var title: String {
        guard let quantity, !quantity.isEmpty else { return name }
        return "\(quantity) \(name)"
    }

    /// Identity across parser passes: letters and digits only, so "Kartoffeln, mehligkochend"
    /// (language model) and "Kartoffeln mehligkochend" (rules) are the same entry.
    public var identityKey: String {
        ItemKeyNormalizer.storeNameKey(ItemKeyNormalizer.key(for: name))
    }
}

/// Store names the parser listens for, each with its spoken spellings
/// ("Aldi Süd": "Aldi Süd", "Aldi"; "Markt": "Markt", "Wochenmarkt").
public struct SpokenStoreLexicon: Sendable {
    struct Spelling: Sendable {
        let tokens: [String]
        let name: String
    }

    let spellings: [Spelling]
    public let names: [String]

    public init(stores: [(name: String, spellings: [String])]) {
        var seen = Set<[String]>()
        var spellings: [Spelling] = []
        for store in stores {
            for spelling in [store.name] + store.spellings {
                let tokens = VoiceTokenizer.words(in: spelling)
                guard !tokens.isEmpty, seen.insert(tokens).inserted else { continue }
                spellings.append(Spelling(tokens: tokens, name: store.name))
            }
        }
        // Longest first: "Aldi Süd" wins over "Aldi", "Getränke Hoffmann" over "Getränke".
        self.spellings = spellings.sorted { $0.tokens.count > $1.tokens.count }
        self.names = stores.map(\.name)
    }

    /// First store mention in `tokens` at or after `start`: its token range and canonical name.
    func firstMatch(in tokens: [String], from start: Int = 0) -> (range: Range<Int>, name: String)? {
        guard start < tokens.count else { return nil }
        for index in start..<tokens.count {
            for spelling in spellings where index + spelling.tokens.count <= tokens.count {
                if Array(tokens[index..<index + spelling.tokens.count]) == spelling.tokens {
                    return (index..<index + spelling.tokens.count, spelling.name)
                }
            }
        }
        return nil
    }
}

public enum VoiceTokenizer {
    /// Folded word tokens: "Aldi-Süd" → ["aldi", "sued"].
    public static func words(in text: String) -> [String] {
        ItemKeyNormalizer.fold(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
