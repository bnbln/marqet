import Foundation
import MarqetCore
import Testing

@Suite("CardBuilder – deck and store lifecycle")
struct CardBuilderTests {
    static func store(_ name: String, sortIndex: Int, planned: Bool = false) -> Store {
        Store(name: name, colorHex: "#000000", symbol: .monogram("X"), sortIndex: sortIndex,
              origin: .catalog, type: .supermarket, plannedAt: planned ? Date(timeIntervalSince1970: 0) : nil)
    }

    static func item(_ title: String, _ store: Store?, created seconds: TimeInterval = 0) -> ShoppingItem {
        ShoppingItem(id: title, title: title, storeRef: store.map { .known($0.id) },
                     creationDate: Date(timeIntervalSince1970: seconds))
    }

    let aldi = store("Aldi", sortIndex: 1)
    let dm = store("dm", sortIndex: 0)
    let lidl = store("Lidl", sortIndex: 2)

    @Test func pagesAreOffersUnsortedThenStoresBySortIndexThenMore() {
        let deck = CardBuilder.deck(
            items: [Self.item("Milch", aldi), Self.item("Zahnpasta", dm), Self.item("Batterien", nil)],
            stores: [aldi, dm, lidl]
        )
        #expect(deck.pages == [.map, .brochures, .unsorted, .store(dm.id), .store(aldi.id), .more])
    }

    @Test func emptyListKeepsUnsortedBeforeMore() {
        let deck = CardBuilder.deck(items: [], stores: [aldi, dm])
        #expect(deck.pages == [.map, .brochures, .unsorted, .more])
    }

    @Test func itemsAreOrderedOldestFirst() {
        let deck = CardBuilder.deck(
            items: [Self.item("Milch", aldi, created: 2), Self.item("Brot", aldi, created: 1)],
            stores: [aldi]
        )
        #expect(deck.items(on: .store(aldi.id)).map(\.title) == ["Brot", "Milch"])
    }

    @Test func unknownStoreIDFallsBackToUnsorted() {
        let orphan = ShoppingItem(id: "x", title: "Wurst", storeRef: .known(UUID()))
        let unresolved = ShoppingItem(id: "y", title: "Käse", storeRef: .unresolved(name: "Metzger"))
        let deck = CardBuilder.deck(items: [orphan, unresolved], stores: [aldi])
        #expect(deck.items(on: .unsorted).map(\.title).sorted() == ["Käse", "Wurst"])
    }

    // MARK: Lifecycle (KONZEPT §7.2)

    @Test func plannedEmptyStoreStays() {
        let planned = Self.store("Markt", sortIndex: 3, planned: true)
        let deck = CardBuilder.deck(items: [], stores: [aldi, planned])
        #expect(deck.pages == [.map, .brochures, .unsorted, .store(planned.id), .more])
        #expect(deck.state(of: planned.id) == .planned)
        #expect(deck.state(of: aldi.id) == nil)
    }

    @Test func shoppedEmptyStoreStaysForTheSession() {
        let deck = CardBuilder.deck(items: [], stores: [aldi],
                                    context: .init(emptiedInSession: [aldi.id]))
        #expect(deck.state(of: aldi.id) == .shoppedEmpty)
    }

    @Test func clearedStoreStaysOnlyWhileOnScreen() {
        let onScreen = CardBuilder.deck(items: [], stores: [aldi],
                                        context: .init(retainedPages: [.store(aldi.id)]))
        #expect(onScreen.state(of: aldi.id) == .clearedEmpty)

        let swipedAway = CardBuilder.deck(items: [], stores: [aldi], context: .init())
        #expect(swipedAway.state(of: aldi.id) == nil)
    }

    @Test func activeWinsOverOtherStates() {
        let planned = Self.store("Markt", sortIndex: 0, planned: true)
        let deck = CardBuilder.deck(items: [Self.item("Eier", planned)], stores: [planned],
                                    context: .init(emptiedInSession: [planned.id]))
        #expect(deck.state(of: planned.id) == .active)
    }

    @Test func retainedUnsortedPageStaysForTheComposer() {
        let deck = CardBuilder.deck(items: [], stores: [], context: .init(retainedPages: [.unsorted]))
        #expect(deck.pages == [.map, .brochures, .unsorted, .more])
    }

    @Test func pageIDRoundTrip() {
        let id = UUID()
        for page in [PageID.map, .brochures, .unsorted, .more, .store(id)] {
            #expect(PageID(rawValue: page.rawValue) == page)
        }
        #expect(PageID(rawValue: "store:nope") == nil)
        #expect(PageID(rawValue: "") == nil)
    }
}
