import MarqetCore
import Testing

@Suite("StoreMarker")
struct StoreMarkerTests {
    struct ParseCase: Sendable, CustomTestStringConvertible {
        let notes: String?
        let storeName: String?
        let userNotes: String?
        let label: String
        var testDescription: String { label }
    }

    static let parseCases: [ParseCase] = [
        .init(notes: nil, storeName: nil, userNotes: nil, label: "nil"),
        .init(notes: "", storeName: nil, userNotes: nil, label: "empty"),
        .init(notes: "🛒 Aldi", storeName: "Aldi", userNotes: nil, label: "marker only"),
        .init(notes: "🛒Aldi", storeName: "Aldi", userNotes: nil, label: "no space after cart"),
        .init(notes: "🛒   Aldi Süd  ", storeName: "Aldi Süd", userNotes: nil, label: "extra whitespace"),
        .init(notes: "🛒\u{FE0F} Aldi", storeName: "Aldi", userNotes: nil, label: "variation selector"),
        .init(notes: "  🛒 Aldi", storeName: "Aldi", userNotes: nil, label: "leading whitespace"),
        .init(notes: "\t🛒\tRewe", storeName: "Rewe", userNotes: nil, label: "tabs"),
        .init(notes: "laktosefrei\n🛒 Aldi", storeName: "Aldi", userNotes: "laktosefrei", label: "text + marker"),
        .init(notes: "laktosefrei\r\n🛒 Aldi", storeName: "Aldi", userNotes: "laktosefrei", label: "CRLF"),
        .init(notes: "🛒 Aldi\r🛒 Lidl", storeName: "Lidl", userNotes: nil, label: "CR only, last wins"),
        .init(notes: "🛒 Aldi\n🛒 Rewe", storeName: "Rewe", userNotes: nil, label: "last marker wins"),
        .init(notes: "a\n🛒 Aldi\nb", storeName: "Aldi", userNotes: "a\nb", label: "marker in the middle"),
        .init(notes: "🛒 Aldi\nnotiz", storeName: "Aldi", userNotes: "notiz", label: "marker first"),
        .init(notes: "Kaufen 🛒 bei Aldi", storeName: nil, userNotes: "Kaufen 🛒 bei Aldi", label: "cart mid-line is text"),
        .init(notes: "🛍 Aldi", storeName: nil, userNotes: "🛍 Aldi", label: "other emoji is text"),
        .init(notes: "🛒", storeName: nil, userNotes: nil, label: "bare cart"),
        .init(notes: "🛒   ", storeName: nil, userNotes: nil, label: "bare cart with spaces"),
        .init(notes: "Notiz\n\n🛒 dm\n\n", storeName: "dm", userNotes: "Notiz", label: "blank lines trimmed"),
        .init(
            notes: "🛒 " + String(repeating: "x", count: 41), storeName: nil,
            userNotes: "🛒 " + String(repeating: "x", count: 41), label: "too long is text"
        ),
        .init(
            notes: "🛒 " + String(repeating: "x", count: 40), storeName: String(repeating: "x", count: 40),
            userNotes: nil, label: "max length is marker"
        ),
        .init(notes: "Zeile1\nZeile2", storeName: nil, userNotes: "Zeile1\nZeile2", label: "no marker"),
        .init(notes: "notiz 😀\n🛒 Lidl", storeName: "Lidl", userNotes: "notiz 😀", label: "emoji in text"),
        .init(notes: "   \n🛒 Aldi", storeName: "Aldi", userNotes: nil, label: "whitespace-only text"),
        .init(notes: "  eingerückt\n🛒 Aldi", storeName: "Aldi", userNotes: "  eingerückt", label: "leading indent kept"),
        .init(notes: "🛒 Aldi\n🛒", storeName: "Aldi", userNotes: nil, label: "bare cart does not reset"),
    ]

    @Test(arguments: parseCases)
    func parse(_ testCase: ParseCase) {
        let parsed = StoreMarker.parse(testCase.notes)
        #expect(parsed.storeName == testCase.storeName)
        #expect(parsed.userNotes == testCase.userNotes)
    }

    struct WriteCase: Sendable, CustomTestStringConvertible {
        let storeName: String?
        let notes: String?
        let expected: String?
        let label: String
        var testDescription: String { label }
    }

    static let writeCases: [WriteCase] = [
        .init(storeName: "Aldi", notes: nil, expected: "🛒 Aldi", label: "into nil"),
        .init(storeName: "Aldi", notes: "", expected: "🛒 Aldi", label: "into empty"),
        .init(storeName: "Aldi", notes: "laktosefrei", expected: "laktosefrei\n🛒 Aldi", label: "append"),
        .init(storeName: "Rewe", notes: "laktosefrei\n🛒 Aldi", expected: "laktosefrei\n🛒 Rewe", label: "replace"),
        .init(storeName: nil, notes: "laktosefrei\n🛒 Aldi", expected: "laktosefrei", label: "remove keeps text"),
        .init(storeName: nil, notes: "🛒 Aldi", expected: nil, label: "remove only marker"),
        .init(storeName: nil, notes: nil, expected: nil, label: "remove from nil"),
        .init(storeName: nil, notes: "notiz", expected: "notiz", label: "remove without marker"),
        .init(storeName: "", notes: "notiz", expected: "notiz", label: "empty name removes"),
        .init(storeName: "   ", notes: "notiz", expected: "notiz", label: "blank name removes"),
        .init(storeName: "dm", notes: "a\n🛒 Aldi\nb\n🛒 Rewe", expected: "a\nb\n🛒 dm", label: "all markers cleaned"),
        .init(storeName: "Aldi", notes: "Zeile1\r\nZeile2", expected: "Zeile1\r\nZeile2\n🛒 Aldi", label: "CRLF preserved"),
        .init(storeName: "Aldi", notes: "notiz\n\n\n", expected: "notiz\n🛒 Aldi", label: "trailing blank lines"),
        .init(storeName: "  Aldi Süd  ", notes: nil, expected: "🛒 Aldi Süd", label: "name trimmed"),
        .init(storeName: "Aldi\nSüd", notes: nil, expected: "🛒 Aldi Süd", label: "newline in name"),
        .init(storeName: "Aldi", notes: "  eingerückt\n  text", expected: "  eingerückt\n  text\n🛒 Aldi", label: "indent kept"),
        .init(storeName: "Aldi", notes: "Emoji 🛒 im Text", expected: "Emoji 🛒 im Text\n🛒 Aldi", label: "cart in text kept"),
        .init(storeName: "Aldi", notes: "🛒\n", expected: "🛒 Aldi", label: "bare cart replaced"),
        .init(
            storeName: String(repeating: "y", count: 50), notes: nil,
            expected: "🛒 " + String(repeating: "y", count: 40), label: "name capped"
        ),
    ]

    @Test(arguments: writeCases)
    func write(_ testCase: WriteCase) {
        #expect(StoreMarker.write(storeName: testCase.storeName, into: testCase.notes) == testCase.expected)
    }

    @Test(arguments: [
        nil, "", "laktosefrei", "a\nb", "Zeile1\r\nZeile2", "🛒 Rewe", "text\n🛒 Lidl\n", "  eingerückt",
    ] as [String?], ["Aldi Süd", "dm", "denn's Biomarkt"])
    func roundTrip(notes: String?, storeName: String) {
        let written = StoreMarker.write(storeName: storeName, into: notes)
        let parsed = StoreMarker.parse(written)
        #expect(parsed.storeName == storeName)
        #expect(parsed.userNotes == StoreMarker.parse(notes).userNotes)
    }

    @Test func writeIsIdempotent() {
        let once = StoreMarker.write(storeName: "Aldi", into: "notiz")
        #expect(StoreMarker.write(storeName: "Aldi", into: once) == once)
    }
}
