import EventKit
import Foundation
import MarqetCore
import MarqetReminders
import Testing

/// Integration test against the real EventKit store (KONZEPT §11).
///
/// Needs Reminders access for the host app in the simulator:
/// `xcrun simctl privacy booted grant reminders app.marqet.Marqet`
@Suite(
    "EventKit round-trip",
    .serialized,
    .enabled(
        if: EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
        "Reminders access not granted – run: xcrun simctl privacy booted grant reminders app.marqet.Marqet"
    )
)
struct EventKitRoundTripTests {
    let gateway = EventKitGateway()

    @Test func markerSurvivesWriteAndRead() async throws {
        let list = try await gateway.createList(named: "Marqet Test \(UUID().uuidString.prefix(6))")
        do {
            let milk = try await gateway.createReminder(title: "Milch", notes: "laktosefrei", in: list.id)

            let assigned = try await gateway.setStore(named: "Aldi Süd", forReminder: milk.id)
            #expect(assigned.notes == "laktosefrei\n🛒 Aldi Süd")

            let fetched = try #require(try await gateway.openReminders(in: list.id).first { $0.id == milk.id })
            let parsed = StoreMarker.parse(fetched.notes)
            #expect(parsed.storeName == "Aldi Süd")
            #expect(parsed.userNotes == "laktosefrei")

            try await gateway.setStore(named: nil, forReminder: milk.id)
            let cleared = try #require(try await gateway.openReminders(in: list.id).first { $0.id == milk.id })
            #expect(cleared.notes == "laktosefrei")
        } catch {
            try? await gateway.removeList(id: list.id)
            throw error
        }
        try await gateway.removeList(id: list.id)
    }

    @Test func completionMovesReminderToCompleted() async throws {
        let list = try await gateway.createList(named: "Marqet Test \(UUID().uuidString.prefix(6))")
        do {
            let start = Date.now.addingTimeInterval(-60)
            let bread = try await gateway.createReminder(title: "Brot", notes: "🛒 Bäcker", in: list.id)

            try await gateway.setCompleted(true, reminder: bread.id)

            #expect(try await !gateway.openReminders(in: list.id).contains { $0.id == bread.id })
            #expect(try await gateway.completedReminders(in: list.id, since: start).contains { $0.id == bread.id })
        } catch {
            try? await gateway.removeList(id: list.id)
            throw error
        }
        try await gateway.removeList(id: list.id)
    }
}
