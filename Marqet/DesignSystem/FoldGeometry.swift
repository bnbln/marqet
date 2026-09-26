import MarqetCore
import SwiftUI

/// Reads the iPhone Duo fold (KONZEPT-DUO-IPAD §2.4). `nil` without a fold or before iOS 27.1.
enum FoldGeometry {
    /// A vertical fold crossing the container, in the container's coordinates.
    /// Inactive regions count too, so the layout does not jump when the device is angled.
    static func verticalFold(in proxy: GeometryProxy) -> CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        let width = proxy.size.width
        return proxy
            .reservedRegions(kind: .division, options: .includeInactive, layoutDirectionBehavior: .fixed)
            .map(\.frame)
            .first { $0.height >= $0.width && $0.minX > width * 0.25 && $0.maxX < width * 0.75 }
    }
}

/// Frames of the pager: how many cards, how wide, where the scroll view sits.
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

    init(size: CGSize, fold: CGRect?) {
        let width = size.width
        let slots = SpreadLayout.slotCount(availableWidth: width, hasFold: fold != nil)

        if let fold, slots == 2 {
            // One card per half; the gap sits exactly on the fold.
            let gapToFold: CGFloat = 6
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
            anchor = .leading
            self.spacing = spacing
            slotWidth = max((width - 2 * margin - CGFloat(slots - 1) * spacing) / CGFloat(slots), 100)
            scrollX = margin
        }
    }
}
