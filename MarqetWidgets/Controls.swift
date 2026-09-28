import AppIntents
import MarqetCore
import SwiftUI
import WidgetKit

// Control Center, Lock Screen and Action button (KONZEPT-WIDGETS §6).

struct AddItemControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: WidgetKind.addItemControl, intent: AddItemControlIntent.self) { configuration in
            ControlWidgetButton(action: AddItemIntent(list: configuration.list)) {
                Label(title(for: configuration.list), systemImage: "cart.badge.plus")
            }
        }
        .displayName("Eintrag hinzufügen")
        .description("Öffnet Marqet mit der Tastatur auf der gewählten Liste.")
    }

    private func title(for list: ShoppingListEntity?) -> String {
        guard let list, list.kind != .automatic else { return String(localized: "Eintrag hinzufügen") }
        return String(localized: "Zu \(list.name)")
    }
}

struct LoyaltyCardControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: WidgetKind.loyaltyCardControl, intent: LoyaltyCardControlIntent.self) { configuration in
            ControlWidgetButton(action: ShowLoyaltyCardIntent(card: configuration.card)) {
                Label(configuration.card.flatMap { $0.id == LoyaltyCardEntity.automaticID ? nil : $0.name }
                        ?? String(localized: "Kundenkarte"),
                      systemImage: "wallet.pass.fill")
            }
        }
        .displayName("Kundenkarte")
        .description("Zeigt den Barcode im Vollbild – ideal für die Aktionstaste.")
    }
}

struct TripControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKind.tripControl, provider: TripControlProvider()) { isRunning in
            ControlWidgetToggle(
                "Einkauf",
                isOn: isRunning,
                action: TripToggleIntent()
            ) { isOn in
                Label(isOn ? String(localized: "Einkauf läuft") : String(localized: "Einkauf starten"),
                      systemImage: isOn ? "cart.fill" : "cart")
            }
            .tint(Color(hex: SharedStore.snapshot.accentHex))
        }
        .displayName("Einkauf")
        .description("Startet oder beendet den Einkauf als Live-Aktivität.")
    }
}

struct TripControlProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        SharedStore.trip != nil
    }
}
