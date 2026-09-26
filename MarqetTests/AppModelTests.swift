import Foundation
import MarqetCore
import MarqetPersistence
import MarqetReminders
import Testing
@testable import Marqet

/// Answers like Apple Intelligence would, without the model.
private struct FakeIntelligence: IntelligenceService {
    var stores: [String: String] = [:]
    var categories: [String: ItemCategory] = [:]
    var isAvailable: Bool { true }
    func suggestStores(for titles: [String], stores: [IntelligenceStore]) async throws -> [String: String] {
        self.stores.filter { titles.contains($0.key) }
    }
    func categorize(_ titles: [String]) async throws -> [String: ItemCategory] {
        categories.filter { titles.contains($0.key) }
    }
}

@Suite("AppModel", .serialized)
@MainActor
struct AppModelTests {
    let gateway = InMemoryReminderGateway()

    func makeModel(items: [(String, String?)] = [], pro: Bool = false, intelligence: any IntelligenceService = UnavailableIntelligence()) async throws -> AppModel {
        let model = AppModel(
            gateway: gateway,
            container: try PersistenceContainer.make(inMemory: true),
            intelligence: intelligence,
            defaults: try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
        )
        model.hasCompletedOnboarding = true
        model.isPro = pro
        let list = await gateway.seed(listTitle: "Einkaufen", reminders: items.map { ($0.0, $0.1) })
        await model.selectList(list.id)
        return model
    }

    func catalogStore(_ model: AppModel, _ key: String) throws -> Store {
        model.addStore(from: try #require(model.catalog?.entry(forKey: key)), planned: false)
    }

    func notes(of title: String) async throws -> String? {
        let list = try #require(try await gateway.lists().first)
        return try await gateway.openReminders(in: list.id).first { $0.title == title }?.notes
    }

    // MARK: M2 – cards, composer, lifecycle

    @Test func markerFromAnotherDeviceBecomesCatalogStore() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 aldi sued")])
        let store = try #require(model.stores.first)
        #expect(store.catalogKey == "aldi-sued")
        #expect(model.items.first?.storeID == store.id)
        // The unsorted inbox is always the first page (K3).
        #expect(model.deck.pages == [.unsorted, .store(store.id), .more])
    }

    @Test func composerAddsToStoreWritesMarkerAndLearns() async throws {
        let model = try await makeModel()
        let aldi = try catalogStore(model, "aldi-sued")
        await model.addItem(title: "Butter", to: .store(aldi.id))
        #expect(try await notes(of: "Butter") == "🛒 Aldi Süd")
        #expect(model.assignmentMemory.counts["butter"]?[aldi.id] == 1)
    }

    @Test func checkingOffHasUndoWindowThenEmptiesStore() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Rewe")])
        let item = try #require(model.items.first)
        let rewe = try #require(item.storeID)

        await model.toggleCompletion(item)
        #expect(model.items.first?.isCompleted == true)
        await model.toggleCompletion(item)                    // undo within the window
        #expect(model.items.first?.isCompleted == false)
        #expect(model.pendingCompletions.isEmpty)

        await model.toggleCompletion(item)
        try await Task.sleep(for: .seconds(1.8))
        #expect(model.items.isEmpty)
        #expect(model.deck.state(of: rewe) == .shoppedEmpty)  // stays for the shopping session
        #expect(model.recentlyCompleted.map(\.title) == ["Milch"])
    }

    @Test func plannedStoreStaysAndHideRemovesIt() async throws {
        let model = try await makeModel()
        let dm = try catalogStore(model, "dm")
        #expect(model.deck.pages == [.unsorted, .more])
        model.plan(dm.id)
        #expect(model.deck.pages == [.unsorted, .store(dm.id), .more])
        model.hide(dm.id)
        #expect(model.deck.pages == [.unsorted, .more])
    }

    // MARK: M5 – store management

    @Test func renamingStoreRewritesMarkersAndKeepsAlias() async throws {
        let model = try await makeModel(items: [("Wurst", "vom Metzger\n🛒 Huber")])
        let huber = try #require(model.stores.first)
        await model.rename(storeID: huber.id, to: "Metzgerei Huber")
        #expect(try await notes(of: "Wurst") == "vom Metzger\n🛒 Metzgerei Huber")
        #expect(model.store(huber.id)?.aliases == ["Huber"])
        #expect(StoreMatcher(stores: model.stores).store(named: "Huber")?.id == huber.id)
    }

    @Test func deletingStoreMakesItemsUnsorted() async throws {
        let model = try await makeModel(items: [("Zahnpasta", "🛒 dm")])
        let dm = try #require(model.stores.first)
        await model.deleteStore(dm.id)
        #expect(model.stores.isEmpty)
        #expect(model.unsortedItems.map(\.title) == ["Zahnpasta"])
        #expect(try await notes(of: "Zahnpasta") == nil)
    }

    @Test func storesReorder() async throws {
        let model = try await makeModel()
        let a = try catalogStore(model, "aldi-sued")
        let b = try catalogStore(model, "dm")
        let c = try catalogStore(model, "rewe")
        model.moveStores(from: IndexSet(integer: 2), to: 0)
        #expect(model.sortedStores.map(\.id) == [c.id, a.id, b.id])
    }

    // MARK: M3 – categories

    @Test func grocerySectionsAndCorrection() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Aldi Süd"), ("Bananen", "🛒 Aldi Süd"), ("Hafermilch", "🛒 Aldi Süd")])
        let aldi = try #require(model.stores.first)
        let page = PageID.store(aldi.id)
        #expect(model.sections(for: page, items: model.deck.items(on: page)).map(\.category) == [.produce, .dairyEggs])

        let oatMilk = try #require(model.items.first { $0.title == "Hafermilch" })
        model.setCategory(.beverages, for: oatMilk)
        #expect(model.sections(for: page, items: model.deck.items(on: page)).map(\.category) == [.produce, .dairyEggs, .beverages])

        model.setCategoryOrder([.beverages, .dairyEggs, .produce], for: aldi.id)
        #expect(model.sections(for: page, items: model.deck.items(on: page)).map(\.category) == [.beverages, .dairyEggs, .produce])
    }

    // MARK: M4 – triage

    @Test func triageAssignUndoAndSummary() async throws {
        let model = try await makeModel(items: [("Milch", nil), ("Zahnpasta", nil)])
        let aldi = try catalogStore(model, "aldi-sued")
        model.startTriage()
        #expect(model.triageQueue.map(\.title) == ["Milch", "Zahnpasta"])

        let milk = try #require(model.triageQueue.first)
        await model.triageAssign(milk, to: aldi)
        #expect(model.triageQueue.map(\.title) == ["Zahnpasta"])
        #expect(try await notes(of: "Milch") == "🛒 Aldi Süd")

        await model.triageUndo()
        #expect(model.triageQueue.map(\.title) == ["Milch", "Zahnpasta"])
        #expect(model.assignmentMemory.counts["milch"] == nil)

        model.triageSkip(milk)
        #expect(model.triageQueue.map(\.title) == ["Zahnpasta"])
    }

    @Test func freeUsersGetLearnedSuggestionsNotAutoAssign() async throws {
        let model = try await makeModel()
        let rewe = try catalogStore(model, "rewe")
        for _ in 0..<2 { model.rememberAssignment(of: ShoppingItem(id: "x", title: "Hafermilch"), to: rewe) }
        let list = try #require(try await gateway.lists().first)
        _ = try await gateway.createReminder(title: "Hafermilch", notes: nil, in: list.id)
        await model.reload()

        let item = try #require(model.unsortedItems.first)
        #expect(model.suggestion(for: item)?.storeID == rewe.id)
        #expect(model.unsortedItems.count == 1)     // Free: not assigned automatically
        model.startTriage()
        await model.triageAcceptAllSuggestions()
        #expect(model.unsortedItems.isEmpty)
    }

    // MARK: M6 – Pro intelligence

    @Test func proAutoAssignsAndUndoPenalizes() async throws {
        let model = try await makeModel(pro: true)
        let rewe = try catalogStore(model, "rewe")
        for _ in 0..<2 { model.rememberAssignment(of: ShoppingItem(id: "x", title: "Hafermilch"), to: rewe) }
        let list = try #require(try await gateway.lists().first)
        _ = try await gateway.createReminder(title: "Hafermilch", notes: nil, in: list.id)
        await model.reload()

        #expect(model.unsortedItems.isEmpty)
        #expect(model.autoAssignReport?.assignments.count == 1)

        await model.undoAutoAssign()
        #expect(model.unsortedItems.map(\.title) == ["Hafermilch"])
        #expect(model.assignmentMemory.counts["hafermilch"]?[rewe.id] == 1)
    }

    @Test func intelligenceSuggestsStoresAndCategories() async throws {
        let fake = FakeIntelligence(stores: ["Katzenstreu Premium": "dm"], categories: ["Geschenkpapier": .household])
        let model = try await makeModel(items: [("Katzenstreu Premium", nil), ("Geschenkpapier", nil)], pro: true, intelligence: fake)
        let dm = try catalogStore(model, "dm")
        await model.prepareIntelligentSuggestions(for: model.unsortedItems)
        let litter = try #require(model.items.first { $0.title == "Katzenstreu Premium" })
        #expect(model.suggestion(for: litter) == StoreSuggestion(storeID: dm.id, source: .intelligence, confidence: .medium))

        await model.learnMissingCategories()
        let paper = try #require(model.items.first { $0.title == "Geschenkpapier" })
        #expect(model.category(of: paper) == .household)
    }

    @Test func routeLearningReordersSectionsForPro() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Aldi Süd"), ("Bananen", "🛒 Aldi Süd"), ("Bier", "🛒 Aldi Süd")], pro: true)
        let aldi = try #require(model.stores.first)
        let old = Date.now.addingTimeInterval(-2 * 60 * 60)
        // This Aldi: drinks first, produce last.
        for (index, (key, category)) in [("bier", ItemCategory.alcohol), ("milch", .dairyEggs), ("bananen", .produce)].enumerated() {
            _ = model.sessionTracker.record(CheckOff(storeID: aldi.id, itemKey: key, category: category, date: old.addingTimeInterval(Double(index) * 60)))
        }
        model.finishExpiredRouteSessions()

        let page = PageID.store(aldi.id)
        #expect(model.sections(for: page, items: model.deck.items(on: page)).map(\.category) == [.alcohol, .dairyEggs, .produce])
    }

    // MARK: Briefing (KONZEPT #40)

    @Test(.disabled("Briefing vorerst deaktiviert")) func briefingSummarizesStoresAndInboxOncePerLaunch() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Rewe"), ("Butter", "🛒 Rewe"), ("Zahnpasta", "🛒 dm"), ("Batterien", nil)])
        let briefing = try #require(model.briefing)
        #expect(briefing.stores.map(\.store.name) == ["Rewe", "dm"])
        #expect(briefing.stores.map(\.openCount) == [2, 1])
        #expect(briefing.inboxCount == 1)
        #expect(briefing.headline == "Einkäufe bei 2 Läden")
        #expect(briefing.detail.contains("3 Einträge für Rewe und dm."))
        #expect(briefing.detail.contains("1 Eintrag wartet in der Inbox."))
        #expect(briefing.firstStore?.name == "Rewe")

        model.dismissBriefing()
        await model.reload()
        #expect(model.briefing == nil)   // not again in the same launch
    }

    @Test func noBriefingWithOnlyInboxItems() async throws {
        let model = try await makeModel(items: [("Batterien", nil), ("Geschenkpapier", nil)])
        #expect(model.briefing == nil)
    }

    @Test(.disabled("Briefing vorerst deaktiviert")) func briefingGoesAwayWhenTheUserActs() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Rewe"), ("Batterien", nil)])
        #expect(model.briefing != nil)
        model.startComposer(on: .unsorted)
        #expect(model.briefing == nil)
        #expect(model.briefingProgress == 0)
    }

    @Test(arguments: [(7, "Guten Morgen"), (13, "Guten Tag"), (19, "Guten Abend"), (2, "Hallo")])
    func greetingFollowsTheTimeOfDay(_ hour: Int, _ greeting: String) throws {
        let date = try #require(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now))
        #expect(AppModel.greeting(at: date) == greeting)
    }
}
