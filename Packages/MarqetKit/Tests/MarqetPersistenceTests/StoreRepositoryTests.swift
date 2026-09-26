import Foundation
import MarqetCore
import MarqetPersistence
import Testing

@Suite("StoreRepository")
@MainActor
struct StoreRepositoryTests {
    let repository = StoreRepository.inMemory()

    func store(_ name: String, sortIndex: Int, symbol: StoreSymbol = .monogram("X")) -> Store {
        Store(name: name, aliases: ["\(name) Alias"], colorHex: "#123456", symbol: symbol,
              sortIndex: sortIndex, origin: .catalog, type: .discounter)
    }

    @Test func roundTripKeepsEveryField() throws {
        var aldi = store("Aldi Süd", sortIndex: 0)
        aldi.catalogKey = "aldi-sued"
        aldi.plannedAt = Date(timeIntervalSince1970: 42)
        let market = store("Markt", sortIndex: 1, symbol: .systemImage("carrot.fill"))

        try repository.save([aldi, market])

        #expect(try repository.all() == [aldi, market])
    }

    @Test func saveUpdatesByID() throws {
        var rewe = store("Rewe", sortIndex: 0)
        try repository.save(rewe)
        rewe.plannedAt = .now
        rewe.sortIndex = 5
        try repository.save(rewe)

        let all = try repository.all()
        #expect(all.count == 1)
        #expect(all.first == rewe)
    }

    @Test func allIsSortedBySortIndex() throws {
        try repository.save([store("B", sortIndex: 2), store("A", sortIndex: 1), store("C", sortIndex: 3)])
        #expect(try repository.all().map(\.name) == ["A", "B", "C"])
    }

    @Test func deleteRemovesStore() throws {
        let dm = store("dm", sortIndex: 0)
        try repository.save([dm, store("Lidl", sortIndex: 1)])
        try repository.delete(id: dm.id)
        #expect(try repository.all().map(\.name) == ["Lidl"])
    }
}
