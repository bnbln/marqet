import Foundation

/// Which slot hosts the active card (KONZEPT-DUO-IPAD §2.2).
public enum SpreadAnchor: Sendable {
    /// Compact layouts or a single slot: there is no adjacent context pane.
    case leading
    /// Wide layouts keep the active list in the rightmost slot; supporting content sits to its left.
    case trailing
}

/// Pure layout math for showing 1–4 cards side by side (KONZEPT-DUO-IPAD §2).
///
/// The pager is a horizontal scroll view over *content slots*, one per page. With a trailing
/// anchor the active page sits in the rightmost slot, except on the first spread, which always
/// starts with the first page.
public enum SpreadLayout {
    public static let minimumSlotWidth: Double = 300
    public static let maximumSlots = 4

    public struct Slot: Identifiable, Hashable, Sendable {
        public let id: String
        /// `nil` for an empty filler.
        public let page: PageID?
        /// A mirrored page, if a future spread needs one; current leading fillers are blank.
        public let isGhost: Bool
    }

    public static func slotCount(availableWidth: Double, hasFold: Bool) -> Int {
        guard availableWidth.isFinite, availableWidth > 0 else { return 1 }
        var count = min(max(Int(availableWidth / minimumSlotWidth), 1), maximumSlots)
        // An even count puts the fold between two cards instead of through one.
        if hasFold, count > 1 { count -= count % 2 }
        return count
    }

    /// The pages as scroll slots. No blank fillers: the first spread always starts with the first
    /// page, so the Duo never shows an empty half next to Angebote.
    public static func contentSlots(pages: [PageID], slots: Int, anchor: SpreadAnchor) -> [Slot] {
        pages.map { Slot(id: $0.rawValue, page: $0, isGhost: false) }
    }

    /// Leading visible content index that shows `active` in its place.
    /// Trailing: `active` on the anchor slot where scrolling allows, so the first spread shows
    /// the first page on the left. Leading: `active` as far left as scrolling allows.
    public static func leadingIndex(forActive active: PageID, pages: [PageID], slots: Int, anchor: SpreadAnchor) -> Int {
        guard let index = pages.firstIndex(of: active) else { return 0 }
        let lastLeading = max(pages.count - slots, 0)
        switch anchor {
        case .trailing: return max(0, min(index - (slots - 1), lastLeading))
        case .leading: return max(0, min(index, lastLeading))
        }
    }

    /// Page on the anchor (rightmost visible) slot for a leading visible content index.
    public static func anchoredPage(leadingIndex: Int, pages: [PageID], slots: Int) -> PageID? {
        guard !pages.isEmpty else { return nil }
        return pages[min(max(leadingIndex + slots - 1, 0), pages.count - 1)]
    }

    /// Real pages currently on screen (a ghost counts as its page).
    public static func visiblePages(leadingIndex: Int, content: [Slot], slots: Int) -> [PageID] {
        guard !content.isEmpty else { return [] }
        let start = min(max(leadingIndex, 0), content.count - 1)
        let end = min(start + slots, content.count)
        return content[start..<end].compactMap(\.page)
    }

    /// Whether `page` is already visible, so a navigation request does not need to scroll.
    public static func isVisible(_ page: PageID, leadingIndex: Int, content: [Slot], slots: Int) -> Bool {
        visiblePages(leadingIndex: leadingIndex, content: content, slots: slots).contains(page)
    }
}
