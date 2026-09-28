import Foundation
import MarqetCore
import Testing

@Suite("Kundenkarten")
struct LoyaltyCardTests {
    @Test func checkDigitMatchesKnownCodes() {
        // 4006381333931 is a well-known sample EAN-13 (Stabilo), 96385074 a sample EAN-8.
        #expect(EANBarcode.checkDigit(for: "400638133393") == 1)
        #expect(EANBarcode.isValid("4006381333931"))
        #expect(!EANBarcode.isValid("4006381333932"))
        #expect(EANBarcode.checkDigit(for: "9638507") == 4)
        #expect(EANBarcode.isValid("96385074"))
    }

    @Test func ean13HasNinetyFiveModulesWithGuards() throws {
        let modules = try #require(EANBarcode.modules(for: "4006381333931"))
        #expect(modules.count == 95)
        #expect(Array(modules.prefix(3)) == [true, false, true])
        #expect(Array(modules.suffix(3)) == [true, false, true])
        #expect(Array(modules[45..<50]) == [false, true, false, true, false])
    }

    @Test func ean13UsesParityOfFirstDigit() throws {
        // First digit 4 → LGLLGG: the second left digit (0) uses the G code 0100111.
        let modules = try #require(EANBarcode.modules(for: "4006381333931"))
        let secondDigit = modules[10..<17].map { $0 ? "1" : "0" }.joined()
        #expect(secondDigit == "0100111")
    }

    @Test func ean8HasSixtySevenModules() throws {
        #expect(try #require(EANBarcode.modules(for: "96385074")).count == 67)
        #expect(EANBarcode.modules(for: "96385075") == nil)
    }

    @Test func validationExplainsWhatIsWrong() {
        #expect(BarcodeSymbology.ean13.validationError(for: "") == .missingNumber)
        #expect(BarcodeSymbology.ean13.validationError(for: "40063813339") == .wrongLength(expected: 13))
        #expect(BarcodeSymbology.ean13.validationError(for: "400638133393A") == .invalidDigits)
        #expect(BarcodeSymbology.ean13.validationError(for: "4006381333932") == .wrongCheckDigit)
        #expect(BarcodeSymbology.ean13.validationError(for: "4006 3813 3393 1") == nil)
        #expect(BarcodeSymbology.code128.validationError(for: "PB-1234 ÄÖ") == .unsupportedCharacters)
        #expect(BarcodeSymbology.code128.validationError(for: "3083 1234 5678") == nil)
        #expect(BarcodeSymbology.qr.validationError(for: "https://example.org/ä") == nil)
    }

    @Test func guessPrefersValidEAN() {
        #expect(BarcodeSymbology.guess(for: "4006381333931") == .ean13)
        #expect(BarcodeSymbology.guess(for: "9638 5074") == .ean8)
        #expect(BarcodeSymbology.guess(for: "4006381333932") == .code128)
        #expect(BarcodeSymbology.guess(for: "308312345678901") == .code128)
    }

    @Test func cardNeedsNameAndValidNumber() {
        var card = LoyaltyCard(name: " ", payload: "4006381333931", symbology: .ean13, colorHex: "#003EAA")
        #expect(card.validationError == .missingName)
        card.name = "Payback"
        #expect(card.validationError == nil)
    }

    @Test func cardsForStoreKeepInsertionOrder() {
        let rewe = UUID(), dm = UUID()
        let payback = LoyaltyCard(name: "Payback", payload: "1", symbology: .code128, colorHex: "#003EAA",
                                  storeIDs: [rewe, dm], createdAt: Date(timeIntervalSince1970: 2))
        let bonus = LoyaltyCard(name: "Bonus", payload: "2", symbology: .code128, colorHex: "#CC071E",
                                storeIDs: [rewe], createdAt: Date(timeIntervalSince1970: 1))
        let cards = [payback, bonus]
        #expect(cards.cards(for: rewe).map(\.name) == ["Bonus", "Payback"])
        #expect(cards.cards(for: dm).map(\.name) == ["Payback"])
        #expect(cards.cards(for: UUID()).isEmpty)
    }
}
