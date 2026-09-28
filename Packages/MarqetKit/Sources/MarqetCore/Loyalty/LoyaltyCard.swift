import Foundation

/// A customer card (Payback, Rewe Bonus, dm …) shown at the checkout of the stores it belongs to
/// (KONZEPT #42, §2). One card can belong to several stores.
public struct LoyaltyCard: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    /// The barcode's content, exactly as scanned or typed.
    public var payload: String
    public var symbology: BarcodeSymbology
    public var colorHex: String
    public var storeIDs: [UUID]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        payload: String,
        symbology: BarcodeSymbology,
        colorHex: String,
        storeIDs: [UUID] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.payload = payload
        self.symbology = symbology
        self.colorHex = colorHex
        self.storeIDs = storeIDs
        self.createdAt = createdAt
    }

    /// `nil` when the card can be saved, otherwise why not.
    public var validationError: ValidationError? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missingName }
        return symbology.validationError(for: payload)
    }

    public enum ValidationError: Equatable, Sendable {
        case missingName
        case missingNumber
        case invalidDigits
        case wrongLength(expected: Int)
        case wrongCheckDigit
        case unsupportedCharacters
    }
}

extension [LoyaltyCard] {
    /// Cards of one store, oldest first (the order the user added them).
    public func cards(for storeID: UUID) -> [LoyaltyCard] {
        filter { $0.storeIDs.contains(storeID) }.sorted { $0.createdAt < $1.createdAt }
    }
}

/// The barcode types found on customer cards. Raw values are persisted.
public enum BarcodeSymbology: String, CaseIterable, Codable, Sendable {
    case ean13
    case ean8
    case code128
    case qr
    case pdf417
    case aztec

    /// Normalizes typed input: EAN keeps digits only, 2D codes and Code 128 keep the text.
    public func normalized(_ payload: String) -> String {
        switch self {
        case .ean13, .ean8:
            payload.filter { !$0.isWhitespace && $0 != "-" }
        case .code128:
            payload.trimmingCharacters(in: .whitespacesAndNewlines)
        case .qr, .pdf417, .aztec:
            payload
        }
    }

    public func validationError(for payload: String) -> LoyaltyCard.ValidationError? {
        let value = normalized(payload)
        guard !value.isEmpty else { return .missingNumber }
        switch self {
        case .ean13, .ean8:
            let length = self == .ean13 ? 13 : 8
            guard value.allSatisfy(\.isASCIIDigit) else { return .invalidDigits }
            guard value.count == length else { return .wrongLength(expected: length) }
            return EANBarcode.isValid(value) ? nil : .wrongCheckDigit
        case .code128:
            // Code 128 set B covers printable ASCII.
            return value.unicodeScalars.allSatisfy { (32...126).contains($0.value) } ? nil : .unsupportedCharacters
        case .qr, .pdf417, .aztec:
            return nil
        }
    }

    /// Best guess for a typed number: 13 or 8 valid EAN digits, else Code 128.
    public static func guess(for payload: String) -> BarcodeSymbology {
        let digits = BarcodeSymbology.ean13.normalized(payload)
        if digits.allSatisfy(\.isASCIIDigit), EANBarcode.isValid(digits) {
            if digits.count == 13 { return .ean13 }
            if digits.count == 8 { return .ean8 }
        }
        return .code128
    }
}

/// EAN-13 and EAN-8 as bar modules. Core Image has no EAN generator, so the app draws these itself.
public enum EANBarcode {
    /// Check digit for the digits before it (12 for EAN-13, 7 for EAN-8).
    public static func checkDigit(for body: String) -> Int? {
        let digits = body.compactMap(\.wholeNumberValue)
        guard digits.count == body.count, !digits.isEmpty else { return nil }
        // Weights 3,1,3,1… from the right end of the body.
        let sum = digits.reversed().enumerated().reduce(0) { sum, pair in
            sum + pair.element * (pair.offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10
    }

    public static func isValid(_ code: String) -> Bool {
        guard code.count == 13 || code.count == 8, let last = code.last?.wholeNumberValue else { return false }
        return checkDigit(for: String(code.dropLast())) == last
    }

    /// Bars (`true`) and spaces from left to right, without quiet zones; `nil` for invalid codes.
    public static func modules(for code: String) -> [Bool]? {
        guard isValid(code) else { return nil }
        let digits = code.compactMap(\.wholeNumberValue)
        var result: [Bool] = []
        let guardPattern = "101"
        let centerPattern = "01010"

        let left: [Int]
        let right: [Int]
        var parity = Array(repeating: false, count: 6) // false = L code, true = G code
        if digits.count == 13 {
            parity = parityPatterns[digits[0]]
            left = Array(digits[1...6])
            right = Array(digits[7...12])
        } else {
            left = Array(digits[0...3])
            right = Array(digits[4...7])
        }

        result += bits(guardPattern)
        for (index, digit) in left.enumerated() {
            result += bits(parity[index] ? gCodes[digit] : lCodes[digit])
        }
        result += bits(centerPattern)
        for digit in right { result += bits(rCodes[digit]) }
        result += bits(guardPattern)
        return result
    }

    private static func bits(_ pattern: String) -> [Bool] { pattern.map { $0 == "1" } }

    private static let lCodes = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"]
    private static let gCodes = ["0100111", "0110011", "0011011", "0100001", "0011101", "0111001", "0000101", "0010001", "0001001", "0010111"]
    private static let rCodes = ["1110010", "1100110", "1101100", "1000010", "1011100", "1001110", "1010000", "1000100", "1001000", "1110100"]
    /// First EAN-13 digit → parity of the six left digits (true = G code).
    private static let parityPatterns: [[Bool]] = [
        "LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL",
    ].map { $0.map { $0 == "G" } }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
