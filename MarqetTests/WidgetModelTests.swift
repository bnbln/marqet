import Foundation
import MarqetCore
import MarqetPersistence
import MarqetReminders
import Testing
@testable import Marqet

/// Widgets, deep links and the shopping trip seen from the model (KONZEPT-WIDGETS §12).
@Suite("Widgets & Einkauf", .serialized)
@MainActor
struct WidgetModelTests {
    let gateway = InMemoryReminderGateway()

    func makeModel(items: [(String, String?)] = []) async throws -> AppModel {
        let model = AppModel(
            gateway: gateway,
            container: try PersistenceContainer.make(inMemory: true),
            intelligence: UnavailableIntelligence(),
            defaults: try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
        )
        model.hasCompletedOnboarding = true
        let list = await gateway.seed(listTitle: "Einkaufen", reminders: items)
        await model.selectList(list.id)
        return model
    }

    func store(_ model: AppModel, _ name: String) throws -> Store {
        try #require(model.stores.first { $0.name == name })
    }

    // MARK: Snapshot

    @Test func registryAndSnapshotMirrorTheCards() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Aldi Süd"), ("Zahnpasta", "🛒 dm"), ("Batterien", nil)])
        let registry = model.makeWidgetRegistry()
        #expect(registry.status == .ready)
        #expect(Set(registry.stores.map(\.name)) == ["Aldi Süd", "dm"])
        let snapshot = model.makeWidgetSnapshot(registry: registry)
        #expect(snapshot.pages.map { $0.store?.name ?? "Inbox" } == ["Inbox", "Aldi Süd", "dm"])
        #expect(snapshot.totalOpenCount == 3)
    }

    @Test func checkedItemsLeaveTheSnapshotRightAway() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Aldi Süd"), ("Brot", "🛒 Aldi Süd")])
        let milk = try #require(model.items.first { $0.title == "Milch" })
        await model.toggleCompletion(milk)
        // Still in the undo window in the app, but the widget must not offer it again.
        #expect(model.makeWidgetSnapshot().page(forStore: try store(model, "Aldi Süd").id)?.items.map(\.title) == ["Brot"])
    }

    // MARK: Trip

    @Test func firstCheckOffStartsTheTripAndCheckingOffElsewhereMovesIt() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Aldi Süd"), ("Zahnpasta", "🛒 dm")])
        let aldi = try store(model, "Aldi Süd")
        let dm = try store(model, "dm")
        await model.toggleCompletion(try #require(model.items.first { $0.title == "Milch" }))
        #expect(model.trip?.storeID == aldi.id)
        #expect(model.trip?.doneItemIDs.count == 1)
        await model.toggleCompletion(try #require(model.items.first { $0.title == "Zahnpasta" }))
        #expect(model.trip?.storeID == dm.id)
    }

    @Test func undoWithinTheWindowTakesTheItemOutOfTheTrip() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Aldi Süd")])
        let milk = try #require(model.items.first)
        await model.toggleCompletion(milk)
        await model.toggleCompletion(try #require(model.items.first))
        #expect(model.trip?.doneItemIDs.isEmpty == true)
    }

    @Test func noAutomaticTripWhenSwitchedOff() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Aldi Süd")])
        model.autoStartsTrip = false
        await model.toggleCompletion(try #require(model.items.first))
        #expect(model.trip == nil)
    }

    @Test func startingWithoutStoreTakesTheFirstCardWithItems() async throws {
        let model = try await makeModel(items: [("Zahnpasta", "🛒 dm"), ("Milch", "🛒 Aldi Süd")])
        let first = try #require(model.deck.pages.compactMap(\.storeID).first)
        let started = await model.startTrip(at: nil)
        #expect(started?.id == first)
        await model.endTrip()
        #expect(model.trip == nil)
    }

    @Test func expiredTripEnds() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Aldi Süd")])
        model.trip = ShoppingTrip(storeID: try store(model, "Aldi Süd").id, startedAt: .now.addingTimeInterval(-3_600))
        model.endTripIfExpired()
        #expect(model.trip == nil)
    }

    // MARK: Deep links

    @Test func pageLinkOpensTheCardFullScreen() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Aldi Süd")])
        let aldi = try store(model, "Aldi Süd")
        model.open(MarqetLink.page(.store(aldi.id)).url)
        #expect(model.focusedPage == .store(aldi.id))
        #expect(model.activePage == .store(aldi.id))
    }

    @Test func linkToAHiddenStorePlansItsCard() async throws {
        let model = try await makeModel()
        let lidl = model.addStore(from: try #require(model.catalog?.entry(forKey: "lidl")), planned: false)
        #expect(!model.deck.pages.contains(.store(lidl.id)))
        model.open(.page(.store(lidl.id)))
        #expect(model.deck.pages.contains(.store(lidl.id)))
    }

    @Test func composeLinkOpensTheComposerOnTheCard() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Aldi Süd")])
        let aldi = try store(model, "Aldi Süd")
        model.open(.compose(.store(aldi.id)))
        #expect(model.composerTarget == .store(aldi.id))
    }

    @Test func triageLinkStartsTriageWhenTheInboxHasItems() async throws {
        let model = try await makeModel(items: [("Batterien", nil)])
        model.open(.triage)
        #expect(model.triage != nil)
    }

    @Test func loyaltyLinkPresentsTheCard() async throws {
        let model = try await makeModel(items: [("Milch", "🛒 Rewe")])
        let rewe = try store(model, "Rewe")
        let card = LoyaltyCard(name: "Payback", payload: "4006381333931", symbology: .ean13, colorHex: "#0046AA", storeIDs: [rewe.id])
        #expect(model.saveLoyaltyCard(card))
        model.open(.storeLoyaltyCards(rewe.id))
        #expect(model.presentedLoyaltyCards?.cards.map(\.id) == [card.id])
    }

    @Test func linksWaitUntilTheListIsLoaded() async throws {
        let model = AppModel(
            gateway: gateway,
            container: try PersistenceContainer.make(inMemory: true),
            defaults: try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
        )
        model.hasCompletedOnboarding = true
        model.open(.triage)
        #expect(model.pendingLink == .triage)
        let list = await gateway.seed(listTitle: "Einkaufen", reminders: [("Batterien", nil)])
        await model.selectList(list.id)
        #expect(model.pendingLink == nil)
        #expect(model.triage != nil)
    }
}
