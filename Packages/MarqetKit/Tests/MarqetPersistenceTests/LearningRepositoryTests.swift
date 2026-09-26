import Foundation
import MarqetCore
import MarqetPersistence
import Testing

@Suite("LearningRepository")
@MainActor
struct LearningRepositoryTests {
    let repository = LearningRepository(container: try! PersistenceContainer.make(inMemory: true))
    let aldi = UUID()

    @Test func correctionIsNotOverwrittenByLearnedValue() throws {
        try repository.setCategory(.beverages, for: "milch", isUserCorrection: true)
        try repository.setCategory(.dairyEggs, for: "milch", isUserCorrection: false)
        let memory = try repository.categoryMemory()
        #expect(memory["milch"]?.category == .beverages)
        #expect(memory["milch"]?.isCorrection == true)

        try repository.setCategory(.dairyEggs, for: "milch", isUserCorrection: true)
        #expect(try repository.categoryMemory()["milch"]?.category == .dairyEggs)
    }

    @Test func assignmentsCountAndPenaltyRemovesAtZero() throws {
        try repository.recordAssignment(itemKey: "milch", storeID: aldi)
        try repository.recordAssignment(itemKey: "milch", storeID: aldi)
        #expect(try repository.assignmentMemory().counts["milch"]?[aldi] == 2)
        try repository.penalizeAssignment(itemKey: "milch", storeID: aldi)
        try repository.penalizeAssignment(itemKey: "milch", storeID: aldi)
        #expect(try repository.assignmentMemory().counts["milch"] == nil)
    }

    @Test func positionsRoundTripPerStore() throws {
        let positions = RouteLearner.manualPositions(for: [.frozen, .produce])
        try repository.saveCategoryPositions(positions, storeID: aldi)
        try repository.saveItemPositions(["milch": OrderPosition(value: 0.3, samples: 2)], storeID: aldi)
        #expect(try repository.categoryPositions(storeID: aldi) == positions)
        #expect(try repository.itemPositions(storeID: aldi)["milch"]?.value == 0.3)
        #expect(try repository.categoryPositions(storeID: UUID()).isEmpty)
    }

    @Test func resetKeepsCorrectionsAndManualOrder() throws {
        try repository.setCategory(.pet, for: "futter", isUserCorrection: true)
        try repository.setCategory(.snacks, for: "chips", isUserCorrection: false)
        try repository.recordAssignment(itemKey: "chips", storeID: aldi)
        try repository.saveCategoryPositions(RouteLearner.manualPositions(for: [.produce]), storeID: aldi)
        try repository.saveItemPositions(["chips": OrderPosition(value: 0.5, samples: 3)], storeID: aldi)

        try repository.resetLearning()

        #expect(try repository.categoryMemory().keys.sorted() == ["futter"])
        #expect(try repository.assignmentMemory().counts.isEmpty)
        #expect(try repository.categoryPositions(storeID: aldi).count == 1)
        #expect(try repository.itemPositions(storeID: aldi).isEmpty)
    }

    @Test func forgetStoreRemovesItsData() throws {
        try repository.recordAssignment(itemKey: "brot", storeID: aldi)
        try repository.saveCategoryPositions(RouteLearner.manualPositions(for: [.bakery]), storeID: aldi)
        try repository.forget(storeID: aldi)
        #expect(try repository.assignmentMemory().counts.isEmpty)
        #expect(try repository.categoryPositions(storeID: aldi).isEmpty)
    }
}
