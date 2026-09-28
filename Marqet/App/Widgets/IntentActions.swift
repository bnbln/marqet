import AppIntents
import Foundation
import MarqetCore

/// What the shared intents do in the app process (KONZEPT-WIDGETS §8). If the system launched
/// Marqet in the background just for a widget button, the model loads the list first.
@MainActor
enum IntentActions {
    private static func readyModel() async -> AppModel? {
        guard let model = AppModel.active, await model.prepareInBackground() else { return nil }
        return model
    }

    static func checkOff(itemID: String) async {
        guard let model = await readyModel() else { return }
        if let item = model.items.first(where: { $0.id == itemID }), !item.isCompleted {
            await model.toggleCompletion(item)
        }
        await model.syncWidgetsNow()
    }

    static func restore(itemID: String) async {
        guard let model = await readyModel() else { return }
        await model.reopen(itemID: itemID)
        await model.syncWidgetsNow()
    }

    static func assign(itemID: String, to storeID: Store.ID) async {
        guard let model = await readyModel(),
              let item = model.items.first(where: { $0.id == itemID }),
              let store = model.store(storeID) else { return }
        await model.assign(item, to: store)
        await model.syncWidgetsNow()
    }

    /// Returns the sentence Siri says.
    static func startTrip(at storeID: Store.ID?) async -> String {
        guard let model = await readyModel() else {
            return String(localized: "Öffne Marqet einmal, um deine Einkaufsliste zu verbinden.")
        }
        guard let store = await model.startTrip(at: storeID) else {
            return String(localized: "Gerade ist nichts zu besorgen.")
        }
        return String(localized: "Einkauf bei \(store.name) gestartet.")
    }

    static func endTrip() async {
        guard let model = await readyModel() else { return }
        await model.endTrip()
    }

    static func moveTrip(to storeID: Store.ID) async {
        guard let model = await readyModel() else { return }
        await model.moveTrip(to: storeID)
    }

    // MARK: Opening the app (foreground intents)

    static func open(_ kind: ShoppingListEntity.Kind, composing: Bool) {
        guard let model = AppModel.active else { return }
        let page: PageID? = switch kind {
        case .automatic: SharedStore.snapshot.automaticPage?.pageID ?? .unsorted
        case .inbox: .unsorted
        case .store(let id): .store(id)
        case .completed: nil
        }
        if let page {
            model.open(composing ? .compose(page) : .page(page))
        } else {
            model.open(composing ? .compose(.unsorted) : .completed)
        }
    }

    static func showLoyaltyCard(_ id: LoyaltyCard.ID?) {
        guard let model = AppModel.active else { return }
        let card = id.flatMap { id in model.loyaltyCards.first { $0.id == id } }
            ?? SharedStore.snapshot.automaticLoyaltyCard
        if let card { model.open(.loyaltyCard(card.id)) }
    }
}

/// Siri and Shortcuts (KONZEPT-WIDGETS §7). Every phrase names the app, as Apple requires.
struct MarqetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTripIntent(),
            phrases: [
                "Einkauf starten in \(.applicationName)",
                "Einkauf bei \(\.$store) starten in \(.applicationName)",
            ],
            shortTitle: "Einkauf starten",
            systemImageName: "cart"
        )
        AppShortcut(
            intent: ShowLoyaltyCardIntent(),
            phrases: [
                "Kundenkarte zeigen in \(.applicationName)",
                "Zeig meine Kundenkarte in \(.applicationName)",
            ],
            shortTitle: "Kundenkarte",
            systemImageName: "wallet.pass"
        )
        AppShortcut(
            intent: AddItemIntent(),
            phrases: ["Eintrag in \(.applicationName) hinzufügen"],
            shortTitle: "Eintrag hinzufügen",
            systemImageName: "plus"
        )
        AppShortcut(
            intent: OpenListIntent(),
            phrases: ["\(\.$list) in \(.applicationName) öffnen"],
            shortTitle: "Liste öffnen",
            systemImageName: "list.bullet"
        )
    }
}
