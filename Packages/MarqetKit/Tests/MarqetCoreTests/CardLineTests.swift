import Foundation
@testable import MarqetCore
import Testing

@Suite("Karten-Zeilen und Ziehen")
struct CardLineTests {
    let bananas = ShoppingItem(id: "bananen", title: "Bananen")
    let zucchini = ShoppingItem(id: "zucchini", title: "Zucchini")
    let butter = ShoppingItem(id: "butter", title: "Butter")
    let milk = ShoppingItem(id: "milch", title: "Milch")

    var lines: [CardLine] {
        CardLine.lines(of: [
            CardSection(category: .produce, items: [bananas, zucchini]),
            CardSection(category: .dairyEggs, items: [butter, milk]),
        ])
    }

    @Test func titlesOnlyForCategorySections() {
        #expect(lines.map(\.id) == ["header:produce", "bananen", "zucchini", "header:dairyEggs", "butter", "milch"])
        let flat = CardLine.lines(of: [CardSection(category: nil, items: [butter, milk])])
        #expect(flat.map(\.id) == ["butter", "milch"])
    }

    @Test func movingInsideASectionKeepsTheCategory() throws {
        // Milch (row 5) above Butter (row 4).
        let placement = try #require(CardLine.placement(afterMoving: [5], to: 4, in: lines))
        #expect(placement.item.id == "milch")
        #expect(placement.category == .dairyEggs)
        #expect(placement.order.map(\.id) == ["milch", "butter"])
    }

    @Test func movingPastATitleTakesThatCategory() throws {
        // Zucchini (row 2) below the dairy title, before Butter.
        let down = try #require(CardLine.placement(afterMoving: [2], to: 4, in: lines))
        #expect(down.category == .dairyEggs)
        #expect(down.order.map(\.id) == ["zucchini", "butter", "milch"])
        // Butter (row 4) up behind Bananen.
        let up = try #require(CardLine.placement(afterMoving: [4], to: 2, in: lines))
        #expect(up.category == .produce)
        #expect(up.order.map(\.id) == ["bananen", "butter", "zucchini"])
    }

    @Test func abovePassingEveryTitleLandsInTheFirstSection() throws {
        let placement = try #require(CardLine.placement(afterMoving: [4], to: 0, in: lines))
        #expect(placement.category == .produce)
        #expect(placement.order.map(\.id) == ["butter", "bananen", "zucchini"])
    }

    @Test func titlesDoNotMove() {
        #expect(CardLine.placement(afterMoving: [0], to: 3, in: lines) == nil)
    }
}
