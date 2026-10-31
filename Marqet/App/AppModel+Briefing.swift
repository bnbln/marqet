import Foundation
import MarqetCore

/// "Was jetzt wichtig ist" – a card above the inbox when the app opens with lists at stores
/// (KONZEPT #40). Built from the deck, no model call: the numbers must always be right.
struct Briefing: Equatable {
    struct StoreLine: Equatable, Identifiable {
        let store: Store
        let openCount: Int
        var id: Store.ID { store.id }
    }

    /// Stores with open items or planned for this trip, in card order.
    let stores: [StoreLine]
    let inboxCount: Int
    let greeting: String
    let headline: String
    let detail: String

    /// The first store card – where "Einkauf starten" swipes to.
    var firstStore: Store? { stores.first?.store }
}

extension AppModel {
    /// Once per launch (and list), after the first load: only with lists at stores, not only in the inbox.
    func prepareBriefing(now: Date = .now) {
        guard !hasPreparedBriefing else { return }
        hasPreparedBriefing = true
        guard hasCompletedOnboarding, triage == nil else { return }
        briefing = makeBriefing(now: now)
        briefingProgress = 0
    }

    func dismissBriefing() {
        guard briefing != nil else { return }
        briefing = nil
        briefingProgress = 0
    }

    func makeBriefing(now: Date = .now) -> Briefing? {
        let deck = deck
        let lines: [Briefing.StoreLine] = deck.pages.compactMap { page in
            guard let id = page.storeID, let store = store(id) else { return nil }
            let open = openItemCount(of: id)
            guard open > 0 || deck.state(of: id) == .planned else { return nil }
            return Briefing.StoreLine(store: store, openCount: open)
        }
        guard !lines.isEmpty else { return nil }
        let inbox = unsortedItems.count

        let headline = lines.count == 1
            ? String(localized: "Einkauf bei \(lines[0].store.name)")
            : String(localized: "Einkäufe bei \(lines.count) Läden")

        var sentences: [String] = []
        let names = lines.map(\.store.name).formatted(.list(type: .and))
        let total = lines.reduce(0) { $0 + $1.openCount }
        if total > 0 {
            sentences.append(total == 1
                ? String(localized: "1 Eintrag für \(names).")
                : String(localized: "\(total) Einträge für \(names)."))
        } else {
            sentences.append(String(localized: "\(names) ist angeheftet, die Liste ist noch leer."))
        }
        if let nearest = lines.min(by: { (travelMinutes(to: $0.store.id) ?? .infinity) < (travelMinutes(to: $1.store.id) ?? .infinity) }),
           lines.count > 1, let distance = distanceText(to: nearest.store.id) {
            sentences.append(String(localized: "\(nearest.store.name) ist am nächsten (\(distance))."))
        }
        if inbox > 0 {
            sentences.append(inbox == 1
                ? String(localized: "1 Eintrag wartet in der Inbox.")
                : String(localized: "\(inbox) Einträge warten in der Inbox."))
        }

        return Briefing(
            stores: lines,
            inboxCount: inbox,
            greeting: Self.greeting(at: now),
            headline: headline,
            detail: sentences.joined(separator: " ")
        )
    }

    static func greeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: String(localized: "Guten Morgen")
        case 11..<17: String(localized: "Guten Tag")
        case 17..<23: String(localized: "Guten Abend")
        default: String(localized: "Hallo")
        }
    }
}
