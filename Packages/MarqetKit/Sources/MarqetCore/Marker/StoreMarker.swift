import Foundation

/// Reads and writes the store assignment stored in a reminder's notes (KONZEPT §4).
///
/// ```
/// laktosefrei, 1,5 %     ← user text, preserved as-is
/// 🛒 Aldi Süd            ← marker line, managed by Marqet
/// ```
///
/// Rules:
/// - A marker line starts (after optional whitespace) with 🛒, optionally followed by U+FE0F.
/// - The last marker line wins.
/// - Names longer than `maxNameLength` are not treated as markers, so free text that happens
///   to start with 🛒 is not mistaken for a store.
/// - Writing removes all marker lines and trailing whitespace, then appends one marker line.
public enum StoreMarker {
    public static let prefix = "🛒"
    public static let maxNameLength = 40

    private static let cartScalar: Unicode.Scalar = "\u{1F6D2}"
    private static let variationSelector: Unicode.Scalar = "\u{FE0F}"

    public struct Parsed: Equatable, Sendable {
        /// Store name of the last marker line, `nil` if there is none.
        public var storeName: String?
        /// Notes without any marker line, trailing whitespace trimmed; `nil` if empty.
        public var userNotes: String?

        public init(storeName: String?, userNotes: String?) {
            self.storeName = storeName
            self.userNotes = userNotes
        }
    }

    public static func parse(_ notes: String?) -> Parsed {
        guard let notes, !notes.isEmpty else { return Parsed(storeName: nil, userNotes: nil) }

        var storeName: String?
        for line in lines(of: notes) {
            if case .marker(let name) = classify(line.text), let name {
                storeName = name
            }
        }
        let text = userText(from: notes)
        return Parsed(storeName: storeName, userNotes: text.isEmpty ? nil : text)
    }

    /// Returns the new notes with `storeName` as the only marker. `nil`/empty name removes the assignment.
    public static func write(storeName: String?, into notes: String?) -> String? {
        let text = notes.map(userText(from:)) ?? ""
        guard let name = sanitized(storeName) else {
            return text.isEmpty ? nil : text
        }
        let marker = "\(prefix) \(name)"
        return text.isEmpty ? marker : "\(text)\n\(marker)"
    }

    // MARK: - Internals

    private enum LineKind: Equatable {
        case text
        /// `nil` name: a bare 🛒 line – removed on write, but not an assignment.
        case marker(String?)
    }

    private struct Line {
        var text: Substring
        /// The line break that followed this line ("" for the last line). Kept verbatim (\n, \r\n, \r).
        var separator: Substring
    }

    private static func lines(of string: String) -> [Line] {
        var result: [Line] = []
        var lineStart = string.startIndex
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(after: index)
            // "\r\n" is a single Character in Swift, so this handles all three line-break styles.
            if string[index].isNewline {
                result.append(Line(text: string[lineStart..<index], separator: string[index..<next]))
                lineStart = next
            }
            index = next
        }
        result.append(Line(text: string[lineStart..<string.endIndex], separator: ""))
        return result
    }

    private static func classify(_ line: Substring) -> LineKind {
        let scalars = line.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex, scalars[index].properties.isWhitespace {
            index = scalars.index(after: index)
        }
        guard index < scalars.endIndex, scalars[index] == cartScalar else { return .text }
        index = scalars.index(after: index)
        if index < scalars.endIndex, scalars[index] == variationSelector {
            index = scalars.index(after: index)
        }

        let name = String(Substring(scalars[index...])).trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return .marker(nil) }
        if name.count > maxNameLength { return .text }
        return .marker(name)
    }

    private static func userText(from notes: String) -> String {
        var result = ""
        for line in lines(of: notes) where classify(line.text) == .text {
            result += line.text
            result += line.separator
        }
        return trimmingTrailingWhitespace(result)
    }

    private static func trimmingTrailingWhitespace(_ string: String) -> String {
        var trimmed = Substring(string)
        while let last = trimmed.last, last.isWhitespace {
            trimmed.removeLast()
        }
        return String(trimmed)
    }

    private static func sanitized(_ name: String?) -> String? {
        guard let name else { return nil }
        let singleLine = name
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let capped = String(singleLine.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
        return capped.isEmpty ? nil : capped
    }
}
