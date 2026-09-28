import Foundation
import MarqetCore

/// Customer cards (KONZEPT #42, §2): scanned once, shown at the checkout of their stores.
extension AppModel {
    func loyaltyCards(for storeID: Store.ID) -> [LoyaltyCard] {
        loyaltyCards.cards(for: storeID)
    }

    /// Inserts or updates a card. The payload is stored normalized; invalid cards are refused.
    @discardableResult
    func saveLoyaltyCard(_ card: LoyaltyCard) -> Bool {
        var card = card
        card.name = card.name.trimmingCharacters(in: .whitespacesAndNewlines)
        card.payload = card.symbology.normalized(card.payload)
        let known = Set(stores.map(\.id))
        card.storeIDs = card.storeIDs.filter(known.contains).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        guard card.validationError == nil else { return false }
        do {
            try loyaltyRepository.save(card)
            if let index = loyaltyCards.firstIndex(where: { $0.id == card.id }) {
                loyaltyCards[index] = card
            } else {
                loyaltyCards.append(card)
            }
            return true
        } catch {
            present(error)
            return false
        }
    }

    func deleteLoyaltyCard(_ id: LoyaltyCard.ID) {
        do {
            try loyaltyRepository.delete(id: id)
            loyaltyCards.removeAll { $0.id == id }
        } catch {
            present(error)
        }
    }

    /// A deleted store leaves its cards; a card without any store stays in the settings.
    func detachLoyaltyCards(from storeID: Store.ID) {
        for card in loyaltyCards where card.storeIDs.contains(storeID) {
            var updated = card
            updated.storeIDs.removeAll { $0 == storeID }
            saveLoyaltyCard(updated)
        }
    }
}
