import MarqetCore
import SwiftUI

/// Reads the iPhone Duo fold (KONZEPT-DUO-IPAD §2.4). `nil` without a fold or before iOS 27.1.
enum FoldGeometry {
    /// A vertical fold crossing the container, in the container's coordinates.
    /// Inactive regions count too, so the layout does not jump when the device is laid flat.
    static func verticalFold(in proxy: GeometryProxy) -> Fold? {
        guard #available(iOS 27.1, *) else { return nil }
        let width = proxy.size.width
        return proxy
            .reservedRegions(kind: .division, options: .includeInactive, layoutDirectionBehavior: .fixed)
            .first { $0.frame.height >= $0.frame.width && $0.frame.minX > width * 0.25 && $0.frame.maxX < width * 0.75 }
            .map { Fold(frame: $0.frame, isActive: $0.isActive) }
    }
}

struct Fold: Equatable {
    let frame: CGRect
    /// Angled like a book: the crease is a real edge, cards keep more distance.
    let isActive: Bool
}

/// Frames for Home's page spread or a two-column detail view.
///
/// The scroll view is only as wide as the visible slots and does not clip, so neighbor cards
/// peek in from the margins while `.viewAligned` snaps exactly one slot per swipe.
struct PagerMetrics: Equatable {
    let slots: Int
    let anchor: SpreadAnchor
    let slotWidth: CGFloat
    let spacing: CGFloat
    /// Leading x of the scroll view inside the pager.
    let scrollX: CGFloat

    var scrollWidth: CGFloat { CGFloat(slots) * slotWidth + CGFloat(slots - 1) * spacing }

    init(size: CGSize, fold: Fold?, maximumVisibleSlots: Int = SpreadLayout.maximumSlots) {
        let width = size.width
        let slots = min(SpreadLayout.slotCount(availableWidth: width, hasFold: fold != nil), max(1, maximumVisibleSlots))

        if let isActive = fold?.isActive, let fold = fold?.frame, slots == 2 {
            // One card per half; the gap sits exactly on the fold. Angled like a book, the cards
            // move a bit further away from the crease so nothing bends over its edge.
            let gapToFold: CGFloat = isActive ? 22 : 6
            let outerMargin: CGFloat = 12
            let cardWidth = max(min(fold.minX - gapToFold - outerMargin, width - fold.maxX - gapToFold - outerMargin), 100)
            self.slots = 2
            anchor = .trailing
            slotWidth = cardWidth
            spacing = fold.width + 2 * gapToFold
            scrollX = fold.minX - gapToFold - cardWidth
        } else {
            let margin: CGFloat = slots == 1 ? 20 : 16
            let spacing: CGFloat = slots == 1 ? 10 : 14
            self.slots = slots
            // Home preserves its established leading order on iPad. The zoom detail view
            // separately limits itself to two columns when it needs a context/list spread.
            anchor = .leading
            self.spacing = spacing
            slotWidth = max((width - 2 * margin - CGFloat(slots - 1) * spacing) / CGFloat(slots), 100)
            scrollX = margin
        }
    }
}
