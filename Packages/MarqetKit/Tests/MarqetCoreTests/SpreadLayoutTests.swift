import Foundation
import MarqetCore
import Testing

@Suite("SpreadLayout – cards side by side (KONZEPT-DUO-IPAD §2)")
struct SpreadLayoutTests {
    let rewe = PageID.store(UUID())
    let aldi = PageID.store(UUID())
    let dm = PageID.store(UUID())

    var pages: [PageID] { [.brochures, .unsorted, rewe, aldi, dm, .more] }

    @Test(arguments: [
        (390.0, false, 1),   // iPhone
        (418.0, false, 1),   // Duo outside, minus vertical bar
        (669.0, false, 2),   // Duo inside, portrait
        (951.0, true, 2),    // Duo inside, landscape with fold: 3 rounded down to even
        (834.0, false, 2),   // iPad 11" portrait
        (1194.0, false, 3),  // iPad 11" landscape
        (1376.0, false, 4),  // iPad 13" landscape
        (2400.0, false, 4),  // capped
        (0.0, false, 1),
    ])
    func slotCount(_ width: Double, _ hasFold: Bool, _ expected: Int) {
        #expect(SpreadLayout.slotCount(availableWidth: width, hasFold: hasFold) == expected)
    }

    // MARK: Trailing anchor (Duo)

    @Test func trailingAnchorHasNoBlankSlot() {
        let content = SpreadLayout.contentSlots(pages: pages, slots: 2, anchor: .trailing)
        #expect(content.map(\.page) == pages)
    }

    @Test func unfoldingKeepsActiveOnTheRightWithPredecessorLeft() {
        let content = SpreadLayout.contentSlots(pages: pages, slots: 2, anchor: .trailing)
        let leading = SpreadLayout.leadingIndex(forActive: aldi, pages: pages, slots: 2, anchor: .trailing)
        #expect(SpreadLayout.visiblePages(leadingIndex: leading, content: content, slots: 2) == [rewe, aldi])
        #expect(SpreadLayout.anchoredPage(leadingIndex: leading, pages: pages, slots: 2) == aldi)
    }

    @Test func inboxKeepsBrochuresOnTheLeft() {
        let content = SpreadLayout.contentSlots(pages: pages, slots: 2, anchor: .trailing)
        let leading = SpreadLayout.leadingIndex(forActive: .unsorted, pages: pages, slots: 2, anchor: .trailing)
        #expect(SpreadLayout.visiblePages(leadingIndex: leading, content: content, slots: 2) == [.brochures, .unsorted])
    }

    @Test func brochuresNeverLeaveABlankHalf() {
        let content = SpreadLayout.contentSlots(pages: pages, slots: 2, anchor: .trailing)
        let leading = SpreadLayout.leadingIndex(forActive: .brochures, pages: pages, slots: 2, anchor: .trailing)
        #expect(leading == 0)
        #expect(SpreadLayout.visiblePages(leadingIndex: leading, content: content, slots: 2) == [.brochures, .unsorted])
        #expect(SpreadLayout.anchoredPage(leadingIndex: leading, pages: pages, slots: 2) == .unsorted)
    }

    @Test func lastPageStillReachesTheAnchor() {
        let content = SpreadLayout.contentSlots(pages: pages, slots: 2, anchor: .trailing)
        let leading = SpreadLayout.leadingIndex(forActive: .more, pages: pages, slots: 2, anchor: .trailing)
        #expect(SpreadLayout.visiblePages(leadingIndex: leading, content: content, slots: 2) == [dm, .more])
    }

    @Test func swipingMovesByOneCard() {
        let content = SpreadLayout.contentSlots(pages: pages, slots: 2, anchor: .trailing)
        // Scroll view snapped one slot further: the former right card is now on the left.
        let leading = SpreadLayout.leadingIndex(forActive: aldi, pages: pages, slots: 2, anchor: .trailing) + 1
        #expect(SpreadLayout.visiblePages(leadingIndex: leading, content: content, slots: 2) == [aldi, dm])
        #expect(SpreadLayout.anchoredPage(leadingIndex: leading, pages: pages, slots: 2) == dm)
    }

    @Test func onePageStartsOnTheLeft() {
        #expect(SpreadLayout.leadingIndex(forActive: .more, pages: [.more], slots: 2, anchor: .trailing) == 0)
        #expect(SpreadLayout.anchoredPage(leadingIndex: 0, pages: [.more], slots: 2) == .more)
    }

    // MARK: Leading anchor (iPad)

    @Test func leadingAnchorShowsActiveFirst() {
        let content = SpreadLayout.contentSlots(pages: pages, slots: 3, anchor: .leading)
        let leading = SpreadLayout.leadingIndex(forActive: rewe, pages: pages, slots: 3, anchor: .leading)
        #expect(SpreadLayout.visiblePages(leadingIndex: leading, content: content, slots: 3) == [rewe, aldi, dm])
    }

    @Test func leadingAnchorClampsAtTheEnd() {
        let content = SpreadLayout.contentSlots(pages: pages, slots: 3, anchor: .leading)
        let leading = SpreadLayout.leadingIndex(forActive: .more, pages: pages, slots: 3, anchor: .leading)
        #expect(leading == 3)
        #expect(SpreadLayout.visiblePages(leadingIndex: leading, content: content, slots: 3) == [aldi, dm, .more])
        #expect(SpreadLayout.isVisible(.more, leadingIndex: leading, content: content, slots: 3))
    }

    @Test func unknownActiveFallsBackToStart() {
        #expect(SpreadLayout.leadingIndex(forActive: .store(UUID()), pages: pages, slots: 2, anchor: .trailing) == 0)
    }
}
