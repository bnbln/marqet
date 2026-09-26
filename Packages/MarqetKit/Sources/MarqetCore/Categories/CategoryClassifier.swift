import Foundation

/// Where a category came from – corrections beat everything (KONZEPT §6.3).
public enum CategorySource: Sendable, Equatable {
    case userCorrection
    /// Learned without a correction, e.g. from Apple Intelligence (Pro).
    case learned
    case dictionary
    case fallback
}

public struct CategoryMatch: Sendable, Equatable {
    public let category: ItemCategory
    public let source: CategorySource

    public init(category: ItemCategory, source: CategorySource) {
        self.category = category
        self.source = source
    }
}

/// Bundled grocery dictionary (DE/EN incl. AT/CH variants), keyed by folded words.
public struct CategoryDictionary: Sendable {
    /// Folded word → category. Exceptions are merged in and win over the category lists.
    let words: [String: ItemCategory]
    /// Folded words of at least `minimumSuffixLength` characters, longest first – for compounds.
    let suffixCandidates: [(word: String, category: ItemCategory)]

    static let minimumSuffixLength = 3

    public init(categories: [ItemCategory: [String]], exceptions: [String: ItemCategory] = [:]) {
        var words: [String: ItemCategory] = [:]
        for (category, list) in categories {
            for word in list {
                let key = ItemKeyNormalizer.fold(word)
                if words[key] == nil { words[key] = category }
            }
        }
        for (word, category) in exceptions {
            words[ItemKeyNormalizer.fold(word)] = category
        }
        self.words = words
        suffixCandidates = words
            .filter { !$0.key.contains(" ") && $0.key.count >= Self.minimumSuffixLength }
            .map { ($0.key, $0.value) }
            .sorted { $0.word.count > $1.word.count }
    }

    public var wordCount: Int { words.count }

    public static func bundled() throws -> CategoryDictionary {
        guard let url = Bundle.module.url(forResource: "CategoryDictionary", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        struct File: Decodable {
            let categories: [String: [String]]
            let exceptions: [String: String]
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        var categories: [ItemCategory: [String]] = [:]
        for (raw, list) in file.categories {
            guard let category = ItemCategory(rawValue: raw) else { throw CocoaError(.coderInvalidValue) }
            categories[category] = list
        }
        let exceptions = try file.exceptions.mapValues { raw in
            guard let category = ItemCategory(rawValue: raw) else { throw CocoaError(.coderInvalidValue) }
            return category
        }
        return CategoryDictionary(categories: categories, exceptions: exceptions)
    }
}

/// Assigns a grocery category to a free-text item title (KONZEPT §6.3).
///
/// Order: user correction → learned → dictionary (whole phrase, word pairs, single words,
/// compound heads, plural stems) → `.other`. Among several matching words, an exact word beats
/// a compound match, and the first word wins ties ("Chips Paprika" → snacks).
public struct CategoryClassifier: Sendable {
    public let dictionary: CategoryDictionary
    /// Matching key → (category, is user correction).
    public var learned: [String: (category: ItemCategory, isCorrection: Bool)]

    public init(dictionary: CategoryDictionary, learned: [String: (category: ItemCategory, isCorrection: Bool)] = [:]) {
        self.dictionary = dictionary
        self.learned = learned
    }

    public func classify(_ title: String) -> CategoryMatch {
        let key = ItemKeyNormalizer.matchingKey(for: title)
        if let learned = learned[key] {
            return CategoryMatch(category: learned.category, source: learned.isCorrection ? .userCorrection : .learned)
        }
        if let category = dictionaryCategory(for: key) {
            return CategoryMatch(category: category, source: .dictionary)
        }
        return CategoryMatch(category: .other, source: .fallback)
    }

    /// The dictionary result alone, without learned entries – `nil` if the dictionary does not know it.
    public func dictionaryCategory(for key: String) -> ItemCategory? {
        guard !key.isEmpty else { return nil }
        if let exact = dictionary.words[key] { return exact }

        let tokens = key
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "/" || $0 == "," })
            .map(String.init)
        guard !tokens.isEmpty else { return nil }

        // Multi-word dictionary entries ("rote bete", "saure sahne").
        if tokens.count > 1 {
            for index in 0..<(tokens.count - 1) {
                if let pair = dictionary.words["\(tokens[index]) \(tokens[index + 1])"] { return pair }
            }
        }
        for token in tokens {
            if let exact = dictionary.words[token] ?? stemMatch(token) { return exact }
        }
        for token in tokens {
            if let compound = compoundMatch(token) { return compound }
        }
        return nil
    }

    /// German plurals and inflections the dictionary does not list explicitly.
    private func stemMatch(_ token: String) -> ItemCategory? {
        for ending in ["nen", "en", "er", "n", "e", "s"] where token.count > ending.count + 2 && token.hasSuffix(ending) {
            if let category = dictionary.words[String(token.dropLast(ending.count))] { return category }
        }
        return nil
    }

    /// Compound nouns carry their category in the last part: "Vollkorn|brot", "Katzen|futter".
    private func compoundMatch(_ token: String) -> ItemCategory? {
        dictionary.suffixCandidates.first { token.count > $0.word.count && token.hasSuffix($0.word) }?.category
    }
}

extension ItemCategory {
    /// Default walking order of a typical DACH supermarket (entrance → checkout).
    public static let defaultOrder: [ItemCategory] = allCases
}
