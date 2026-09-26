import Foundation
import MarqetCore
import Testing

@Suite("RouteLearner & sessions")
struct RouteLearnerTests {
    let aldi = UUID()
    let start = Date(timeIntervalSince1970: 1_000_000)

    func checkOff(_ key: String, _ category: ItemCategory, minute: Double, store: UUID? = nil) -> CheckOff {
        CheckOff(storeID: store ?? aldi, itemKey: key, category: category, date: start.addingTimeInterval(minute * 60))
    }

    @Test func relativePositionsSpreadFromZeroToOne() {
        let positions = RouteLearner.relativePositions(["a", "b", "c"])
        #expect(positions == ["a": 0, "b": 0.5, "c": 1])
        #expect(RouteLearner.relativePositions(["x", "y", "x"])["x"] == 0.5)
    }

    @Test func movingAverageIsFastFirstThenStable() {
        var position = RouteLearner.updated(nil, observed: 1)
        #expect(position == OrderPosition(value: 1, samples: 1))
        position = RouteLearner.updated(position, observed: 0)      // α = 1/2
        #expect(position.value == 0.5)
        position = RouteLearner.updated(position, observed: 0)      // α = 1/3
        #expect(abs(position.value - 1.0 / 3) < 0.0001)
        position = RouteLearner.updated(position, observed: 1)      // α = 0.3
        #expect(abs(position.value - (1.0 / 3 * 0.7 + 0.3)) < 0.0001)
    }

    @Test func manualPositionsMoveHalfAsFast() {
        let manual = OrderPosition(value: 0, samples: 5, isManual: true)
        #expect(abs(RouteLearner.updated(manual, observed: 1).value - 0.15) < 0.0001)
    }

    @Test func twoShopsLearnTheWalkingOrder() {
        // In this Aldi, drinks come first and produce last – the opposite of the default.
        var positions: [ItemCategory: OrderPosition] = [:]
        positions = RouteLearner.learn([.beverages, .dairyEggs, .produce], into: positions)
        positions = RouteLearner.learn([.beverages, .bakery, .produce], into: positions)
        let order = SectionBuilder.categoryOrder(positions)
        #expect(order.firstIndex(of: .beverages)! < order.firstIndex(of: .dairyEggs)!)
        #expect(order.firstIndex(of: .dairyEggs)! < order.firstIndex(of: .produce)!)
    }

    @Test func sessionsNeedThreeCheckOffsAndEndAfterAGap() {
        var tracker = ShoppingSessionTracker()
        #expect(tracker.record(checkOff("milch", .dairyEggs, minute: 0)).isEmpty)
        #expect(tracker.record(checkOff("brot", .bakery, minute: 3)).isEmpty)
        #expect(tracker.record(checkOff("eier", .dairyEggs, minute: 5)).isEmpty)
        // 30 minutes later: the first session ends and is long enough.
        let finished = tracker.record(checkOff("bier", .alcohol, minute: 35))
        #expect(finished.map { $0.map(\.itemKey) } == [["milch", "brot", "eier"]])
    }

    @Test func shortSessionsAreDropped() {
        var tracker = ShoppingSessionTracker()
        _ = tracker.record(checkOff("milch", .dairyEggs, minute: 0))
        _ = tracker.record(checkOff("brot", .bakery, minute: 1))
        #expect(tracker.flushExpired(now: start.addingTimeInterval(60 * 60)).isEmpty)
        #expect(tracker.pending.isEmpty)
    }

    @Test func storesAreTrackedSeparatelyAndUndoRemoves() {
        let dm = UUID()
        var tracker = ShoppingSessionTracker()
        for (index, key) in ["a", "b", "c"].enumerated() {
            _ = tracker.record(checkOff(key, .produce, minute: Double(index)))
        }
        _ = tracker.record(checkOff("zahnpasta", .personalCare, minute: 4, store: dm))
        tracker.remove(itemKey: "c", storeID: aldi)
        #expect(tracker.pending[aldi]?.map(\.itemKey) == ["a", "b"])
        #expect(tracker.pending[dm]?.count == 1)
    }
}

@Suite("SuggestionEngine")
struct SuggestionEngineTests {
    let aldi = UUID()
    let rewe = UUID()
    var valid: Set<UUID> { [aldi, rewe] }

    @Test func exactMemoryWithClearMajorityIsHighConfidence() {
        var memory = AssignmentMemory()
        memory.record(itemKey: "milch", storeID: aldi)
        memory.record(itemKey: "milch", storeID: aldi)
        let suggestion = SuggestionEngine.suggestion(for: "2x Milch", memory: memory, validStores: valid)
        #expect(suggestion == StoreSuggestion(storeID: aldi, source: .learned, confidence: .high))
        #expect(suggestion?.allowsAutoAssign == true)
    }

    @Test func singleOrSplitMemoryIsOnlyMedium() {
        var memory = AssignmentMemory()
        memory.record(itemKey: "brot", storeID: aldi)
        #expect(SuggestionEngine.suggestion(for: "Brot", memory: memory, validStores: valid)?.confidence == .medium)

        memory.record(itemKey: "brot", storeID: aldi)
        memory.record(itemKey: "brot", storeID: rewe)
        let split = SuggestionEngine.suggestion(for: "Brot", memory: memory, validStores: valid)
        #expect(split?.storeID == aldi)
        #expect(split?.confidence == .medium)   // 2 of 3 = 67 % < 80 %
    }

    @Test func similarItemsSuggestWithoutAutoAssign() {
        var memory = AssignmentMemory()
        memory.record(itemKey: "milch", storeID: rewe)
        memory.record(itemKey: "milch", storeID: rewe)
        let suggestion = SuggestionEngine.suggestion(for: "Bio-Milch", memory: memory, validStores: valid)
        #expect(suggestion == StoreSuggestion(storeID: rewe, source: .similar, confidence: .medium))
        #expect(suggestion?.allowsAutoAssign == false)
        #expect(SuggestionEngine.suggestion(for: "Hafermilch", memory: memory, validStores: valid)?.storeID == rewe)
    }

    @Test func deletedStoresAreIgnoredAndPenaltyReducesCount() {
        var memory = AssignmentMemory()
        memory.record(itemKey: "eier", storeID: UUID())
        #expect(SuggestionEngine.suggestion(for: "Eier", memory: memory, validStores: valid) == nil)

        memory.record(itemKey: "kaffee", storeID: aldi)
        memory.record(itemKey: "kaffee", storeID: aldi)
        memory.penalize(itemKey: "kaffee", storeID: aldi)
        #expect(memory.counts["kaffee"]?[aldi] == 1)
        memory.penalize(itemKey: "kaffee", storeID: aldi)
        #expect(memory.counts["kaffee"] == nil)   // no empty leftovers that would still match as "similar"

        memory.record(itemKey: "tee", storeID: rewe)
        memory.forget(storeID: rewe)
        #expect(memory.counts["tee"] == nil)
    }

    @Test func storeTypeFallbackPicksFittingStore() {
        let dm = Store(name: "dm", colorHex: "#000000", symbol: .monogram("dm"), sortIndex: 1, origin: .catalog, type: .drugstore)
        let lidl = Store(name: "Lidl", colorHex: "#000000", symbol: .monogram("L"), sortIndex: 0, origin: .catalog, type: .discounter)
        #expect(SuggestionEngine.storeTypeSuggestion(for: .personalCare, stores: [lidl, dm])?.storeID == dm.id)
        #expect(SuggestionEngine.storeTypeSuggestion(for: .dairyEggs, stores: [lidl, dm])?.storeID == lidl.id)
        #expect(SuggestionEngine.storeTypeSuggestion(for: .other, stores: [lidl, dm]) == nil)
    }
}
