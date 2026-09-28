import Foundation

/// Open Food Facts category names and runtime Open Prices comparisons (docs/OFFENE-DATEN.md).
/// The bundle contains only category names; prices are fetched when needed. List items are matched
/// to an Open Food Facts category by its German or English name ("Vollmilch" → `en:whole-milks`),
/// not by barcode.
public struct PriceIndex: Sendable {
    public enum Unit: String, Codable, Sendable {
        case kilogram = "kg"
        case liter = "l"
        case piece
    }

    /// Unit price of one chain for one category.
    public struct ChainPrice: Codable, Hashable, Sendable {
        /// Catalog key of the chain (`StoreCatalog.Entry.key`).
        public let store: String
        public let unit: Unit
        /// Typical entry price (lower quartile): what the budget end of the category costs there.
        /// Compared between stores; categories mix budget and premium products.
        public let typical: Double
        public let median: Double
        public let low: Double
        public let high: Double
        /// Number of price observations behind the median.
        public let count: Int
        /// Date of the newest observation, `yyyy-MM-dd`.
        public let latest: String

        public init(store: String, unit: Unit, typical: Double, median: Double? = nil, low: Double? = nil,
                    high: Double? = nil, count: Int, latest: String) {
            self.store = store
            self.unit = unit
            self.typical = typical
            self.median = median ?? typical
            self.low = low ?? typical
            self.high = high ?? typical
            self.count = count
            self.latest = latest
        }
    }

    public struct Category: Codable, Hashable, Sendable {
        /// Names by language code (`de`, `en`).
        public let names: [String: String]
        /// Further folded names: singulars of plural names ("brot" for "Brote"), everyday words.
        public let aliases: [String]?
        /// Distance from the taxonomy root; deeper is more specific.
        public let depth: Int

        public init(names: [String: String], aliases: [String]? = nil, depth: Int) {
            self.names = names
            self.aliases = aliases
            self.depth = depth
        }
    }

    /// What an item title matched: the category and its prices in one region, in one unit.
    public struct Match: Hashable, Sendable {
        public let categoryTag: String
        public let category: Category
        public let unit: Unit
        /// Cheapest first.
        public let prices: [ChainPrice]

        public init(categoryTag: String, category: Category, unit: Unit, prices: [ChainPrice]) {
            self.categoryTag = categoryTag
            self.category = category
            self.unit = unit
            self.prices = prices
        }
    }

    public struct CategoryMatch: Hashable, Sendable {
        public let tag: String
        public let category: Category
    }

    public let generated: String
    public let source: String
    public let categories: [String: Category]
    /// Region code (`DE`, `AT`, `CH`) → category tag → chain prices.
    public let prices: [String: [String: [ChainPrice]]]

    /// Folded name → category tags carrying that name, deepest first.
    private let tagsByName: [String: [String]]
    /// Single-word names of at least `minimumCompoundLength` characters, longest first.
    private let compoundNames: [String]

    static let minimumCompoundLength = 4

    public init(generated: String, source: String, categories: [String: Category], prices: [String: [String: [ChainPrice]]]) {
        self.generated = generated
        self.source = source
        self.categories = categories
        self.prices = prices

        var tagsByName: [String: [String]] = [:]
        for (tag, category) in categories {
            for name in Set(category.names.values.map(ItemKeyNormalizer.fold)) where !name.isEmpty {
                tagsByName[name, default: []].append(tag)
            }
        }
        // Aliases never shadow a real name of another category.
        var aliasTags: [String: [String]] = [:]
        for (tag, category) in categories {
            for alias in Set((category.aliases ?? []).map(ItemKeyNormalizer.fold)) where !alias.isEmpty && tagsByName[alias] == nil {
                aliasTags[alias, default: []].append(tag)
            }
        }
        tagsByName.merge(aliasTags) { names, _ in names }
        for name in tagsByName.keys {
            tagsByName[name]?.sort { lhs, rhs in
                let (l, r) = (categories[lhs]!.depth, categories[rhs]!.depth)
                return l != r ? l > r : lhs < rhs
            }
        }
        self.tagsByName = tagsByName
        compoundNames = tagsByName.keys
            .filter { !$0.contains(" ") && $0.count >= Self.minimumCompoundLength }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
    }

    // MARK: Lookup

    /// Find a category even before any price has been downloaded.
    public func category(for title: String) -> CategoryMatch? {
        for tag in candidateTags(for: title) {
            if let category = categories[tag] { return CategoryMatch(tag: tag, category: category) }
        }
        return nil
    }

    /// Prices for a free-text list item in `region`, or `nil` if no category with prices matches.
    ///
    /// Order: whole title, word pairs, single words (also without plural endings), then the
    /// last part of compounds ("Vollkorn|brot"). Within a step the longest name wins.
    public func match(for title: String, region: StoreCatalog.Region) -> Match? {
        guard let regional = prices[region.rawValue], !regional.isEmpty else { return nil }
        for tag in candidateTags(for: title) {
            if let match = firstMatch(tags: [tag], in: regional) { return match }
        }
        return nil
    }

    /// Compare downloaded rows for one matched category, using the most observed unit.
    public func match(categoryTag: String, rows: [ChainPrice]) -> Match? {
        firstMatch(tags: [categoryTag], in: [categoryTag: rows])
    }

    private func candidateTags(for title: String) -> [String] {
        let key = ItemKeyNormalizer.matchingKey(for: title)
        guard !key.isEmpty else { return [] }

        let tokens = key
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "/" || $0 == "," })
            .map(String.init)
        var steps: [[String]] = [[key]]
        if tokens.count > 1 {
            steps.append((0..<(tokens.count - 1)).map { "\(tokens[$0]) \(tokens[$0 + 1])" })
        }
        steps.append(tokens)
        steps.append(tokens.flatMap(Self.stems))

        var tags: [String] = []
        for names in steps {
            let hits = names.filter { tagsByName[$0] != nil }.sorted { $0.count > $1.count }
            for name in hits {
                tags.append(contentsOf: tagsByName[name]!)
            }
        }
        for token in tokens {
            for name in compoundNames where token.count > name.count && token.hasSuffix(name) {
                tags.append(contentsOf: tagsByName[name]!)
            }
        }
        return tags
    }

    private func firstMatch(tags: [String], in regional: [String: [ChainPrice]]) -> Match? {
        for tag in tags {
            guard let rows = regional[tag], !rows.isEmpty, let category = categories[tag] else { continue }
            // One unit per comparison: the one with the most observations (milk in l, not kg).
            var counts: [Unit: Int] = [:]
            for row in rows { counts[row.unit, default: 0] += row.count }
            guard let unit = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue })?.key
            else { continue }
            let sorted = rows.filter { $0.unit == unit }.sorted { $0.typical != $1.typical ? $0.typical < $1.typical : $0.store < $1.store }
            return Match(categoryTag: tag, category: category, unit: unit, prices: sorted)
        }
        return nil
    }

    /// German and English plural endings the taxonomy does not list ("Tomaten" → "tomate").
    private static func stems(_ token: String) -> [String] {
        ["nen", "en", "er", "n", "e", "s"]
            .filter { token.count > $0.count + 2 && token.hasSuffix($0) }
            .map { String(token.dropLast($0.count)) }
    }

    // MARK: Loading

    private struct File: Decodable {
        let generated: String
        let source: String
        let categories: [String: Category]
        let prices: [String: [String: [ChainPrice]]]?
    }

    public static func decode(_ data: Data) throws -> PriceIndex {
        let file = try JSONDecoder().decode(File.self, from: data)
        return PriceIndex(generated: file.generated, source: file.source, categories: file.categories, prices: file.prices ?? [:])
    }

    /// Bundled category names, without any price observations.
    public static let bundled: PriceIndex? = {
        guard let url = Bundle.module.url(forResource: "OpenPriceCategories", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }()
}

extension PriceIndex.Category {
    /// Name in the app language, falling back to the other one.
    public func name(for languageCode: String?) -> String {
        names[languageCode == "de" ? "de" : "en"] ?? names["de"] ?? names["en"] ?? ""
    }
}
