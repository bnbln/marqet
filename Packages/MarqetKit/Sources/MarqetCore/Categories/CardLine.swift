import Foundation

/// A card's list as one run of rows: category titles and items. One run instead of one list
/// section per category, so the list's own reordering can carry an item past a title into
/// another category – the other rows make room while the finger moves (KONZEPT #55). The card
/// pins the current title on top itself.
public enum CardLine: Identifiable, Hashable, Sendable {
    case header(ItemCategory)
    /// `index`: position inside its section, for the staggered reveal.
    case item(ShoppingItem, index: Int)

    public var id: String {
        switch self {
        case .header(let category): "header:\(category.rawValue)"
        case .item(let item, _): item.id
        }
    }

    public var item: ShoppingItem? {
        if case .item(let item, _) = self { item } else { nil }
    }

    public var category: ItemCategory? {
        if case .header(let category) = self { category } else { nil }
    }

    /// Titles only for category sections; a flat list is items only.
    public static func lines(of sections: [CardSection]) -> [CardLine] {
        sections.flatMap { section -> [CardLine] in
            let items = section.items.enumerated().map { CardLine.item($1, index: $0) }
            return section.category.map { [.header($0)] + items } ?? items
        }
    }

    /// Where an item lands after the list moved rows `source` to `destination` (`onMove`): its
    /// section's category – the nearest title above it, or the first section when dropped above
    /// every title – and the new order of that section. `nil` when a title was moved.
    public static func placement(
        afterMoving source: IndexSet,
        to destination: Int,
        in lines: [CardLine]
    ) -> (item: ShoppingItem, category: ItemCategory?, order: [ShoppingItem])? {
        guard source.count == 1, let from = source.first, lines.indices.contains(from),
              let moved = lines[from].item else { return nil }
        // Like SwiftUI's `move(fromOffsets:toOffset:)`: `destination` counts before the removal.
        var reordered = lines
        reordered.remove(at: from)
        reordered.insert(lines[from], at: min(destination > from ? destination - 1 : destination, reordered.count))

        var current = reordered.lazy.compactMap(\.category).first
        var sectionOf: [String: ItemCategory?] = [:]
        for line in reordered {
            if let category = line.category {
                current = category
            } else if let item = line.item {
                sectionOf[item.id] = current
            }
        }
        let category = sectionOf[moved.id] ?? nil
        let order = reordered.compactMap(\.item).filter { (sectionOf[$0.id] ?? nil) == category }
        return (moved, category, order)
    }
}
