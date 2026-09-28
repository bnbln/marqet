import SwiftUI

/// "Milch 1 l" → name "Milch" and the quantity "1 l" as a tag, before or after the name.
/// Shared by list rows and the triage card so quantities read the same everywhere.
struct ItemTitleParts {
    let name: String
    let prefix: String?
    let suffix: String?

    init(_ title: String) {
        var remaining = title
        var leading: String?
        var trailing: String?
        if let match = Self.prefixPattern.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
           let tagRange = Range(match.range(at: 1), in: remaining),
           let nameRange = Range(match.range(at: 2), in: remaining) {
            leading = String(remaining[tagRange])
            remaining = String(remaining[nameRange])
        }
        if let match = Self.suffixPattern.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
           let nameRange = Range(match.range(at: 1), in: remaining),
           let tagRange = Range(match.range(at: 2), in: remaining) {
            trailing = String(remaining[tagRange])
            remaining = String(remaining[nameRange])
        }
        name = remaining
        prefix = leading
        suffix = trailing
    }

    private static let prefixPattern = try! NSRegularExpression(
        pattern: #"^((?:\d+(?:[.,]\d+)?\s*)?(?:x|×|kg|g|mg|l|ml|Stück|Stk\.?))\s+(.+)$"#,
        options: [.caseInsensitive]
    )
    private static let suffixPattern = try! NSRegularExpression(
        pattern: #"^(.+?)\s+((?:\d+(?:[.,]\d+)?\s*)?(?:x|×|kg|g|mg|l|ml|Stück|Stk\.?))$"#,
        options: [.caseInsensitive]
    )
}

/// The small gray capsule for a quantity ("1 l", "2x").
struct QuantityTag: View {
    let value: String
    var font: Font = .caption2.weight(.semibold)

    var body: some View {
        Text(value)
            .font(font)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemFill), in: .capsule)
    }
}
