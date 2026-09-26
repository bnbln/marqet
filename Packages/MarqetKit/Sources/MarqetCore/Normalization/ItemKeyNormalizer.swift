import Foundation

/// Turns free-text titles into stable keys for learning (KONZEPT §5.3).
///
/// Learning is keyed by the normalized title, not by reminder ID: IDs can change on iCloud
/// resyncs, and next week's "Milch" is a brand-new reminder.
public enum ItemKeyNormalizer {
    /// Display-stable key: lowercased, quantities and trailing punctuation removed.
    /// `"2x Bio-Milch 1,5%  "` → `"bio-milch 1,5%"`
    public static func key(for title: String) -> String {
        var key = collapsingWhitespace(title.lowercased())
        key = key.replacing(leadingQuantity, with: "")
        key = key.replacing(trailingQuantity, with: "")
        key = key.replacing(#/[!?.,;:]+$/#, with: "")
        return collapsingWhitespace(key)
    }

    /// Key for fuzzy comparisons: `key(for:)` plus German transliteration and diacritic folding,
    /// so "Käse", "Kaese" and "KÄSE" all match.
    public static func matchingKey(for title: String) -> String {
        fold(key(for: title))
    }

    /// Key for store names: folded and reduced to letters and digits.
    /// `"Aldi-Süd"`, `"ALDI SÜD"` and `"aldi sued"` → `"aldisued"`
    public static func storeNameKey(_ name: String) -> String {
        let scalars = fold(name).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Lowercases, transliterates ä/ö/ü/ß and removes remaining diacritics.
    public static func fold(_ string: String) -> String {
        var folded = string.precomposedStringWithCanonicalMapping.lowercased()
        for (umlaut, replacement) in [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")] {
            folded = folded.replacingOccurrences(of: umlaut, with: replacement)
        }
        return folded.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    // MARK: - Internals

    private static func collapsingWhitespace(_ string: String) -> String {
        string.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // "2x ", "500 g ", "3 Stück ", "1,5 l " …
    private static var leadingQuantity: Regex<Substring> {
        #/^\d+(?:[.,]\d+)?\s*(?:x|×|stk\.?|st\.?|stück|g|gr\.?|kg|kilo|l|liter|ml|cl|pck\.?|pkg\.?|packung(?:en)?|pack|dosen?|flaschen?|becher|gläser|glas|bund|netz|tüten?|beutel)?\s+/#
    }

    // " 2x", " 3 Stück", " x2"
    private static var trailingQuantity: Regex<Substring> {
        #/\s+(?:\d+(?:[.,]\d+)?\s*(?:x|×|stk\.?|stück)|x\s*\d+)$/#
    }
}
