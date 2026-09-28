import MarqetCore
import SwiftUI

/// The store's customer cards in its full-screen view, below the leaflet (KONZEPT §2.1).
/// Without a card it offers to add one.
struct LoyaltyCardsSection: View {
    let store: Store
    @Environment(AppModel.self) private var model
    @State private var shownCard: LoyaltyCard?
    @State private var showsEditor = false

    var body: some View {
        let cards = model.loyaltyCards(for: store.id)
        VStack(spacing: 10) {
            ForEach(cards) { card in
                Button { shownCard = card } label: {
                    row(icon: "wallet.pass.fill", iconBackground: Color(hex: card.colorHex),
                        iconForeground: Color(hex: card.colorHex).contrastingForeground,
                        title: card.name, subtitle: String(localized: "An der Kasse zeigen"), trailing: "barcode")
                }
                .buttonStyle(.plain)
            }
            Button { showsEditor = true } label: {
                row(icon: "plus", iconBackground: Color(.tertiarySystemFill), iconForeground: .primary,
                    title: String(localized: "Kundenkarte hinzufügen"),
                    subtitle: cards.isEmpty ? String(localized: "Payback, \(store.name)-Karte …") : nil, trailing: nil)
            }
            .buttonStyle(.plain)
        }
        .fullScreenCover(item: $shownCard) { card in
            LoyaltyCardScreen(cards: cards, initialCardID: card.id)
        }
        .sheet(isPresented: $showsEditor) {
            LoyaltyCardEditor(for: store)
        }
    }

    private func row(icon: String, iconBackground: Color, iconForeground: Color, title: String, subtitle: String?, trailing: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconForeground)
                .frame(width: 44, height: 44)
                .background(iconBackground, in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let trailing {
                Image(systemName: trailing).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
        .contentShape(.rect)
    }
}

/// Settings → Kundenkarten: all cards, including those without a store.
struct LoyaltyCardsSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var editedCard: LoyaltyCard?
    @State private var showsNewCard = false

    var body: some View {
        List {
            if model.loyaltyCards.isEmpty {
                ContentUnavailableView {
                    Label("Keine Kundenkarten", systemImage: "wallet.pass")
                } description: {
                    Text("Scanne deine Karten einmal: Marqet zeigt sie im Vollbild des passenden Ladens.")
                }
                .listRowBackground(Color.clear)
            }
            ForEach(model.loyaltyCards) { card in
                Button { editedCard = card } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "wallet.pass.fill")
                            .foregroundStyle(Color(hex: card.colorHex).contrastingForeground)
                            .frame(width: 32, height: 32)
                            .background(Color(hex: card.colorHex), in: .rect(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.name).foregroundStyle(.primary)
                            Text(storeNames(of: card))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { model.deleteLoyaltyCard(model.loyaltyCards[index].id) }
            }
        }
        .navigationTitle("Kundenkarten")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Kundenkarte hinzufügen", systemImage: "plus") { showsNewCard = true }
            }
        }
        .sheet(item: $editedCard) { LoyaltyCardEditor(card: $0) }
        .sheet(isPresented: $showsNewCard) { LoyaltyCardEditor(for: nil) }
    }

    private func storeNames(of card: LoyaltyCard) -> String {
        let names = card.storeIDs.compactMap { model.store($0)?.name }
        return names.isEmpty ? String(localized: "Keinem Laden zugeordnet") : names.formatted(.list(type: .and))
    }
}
