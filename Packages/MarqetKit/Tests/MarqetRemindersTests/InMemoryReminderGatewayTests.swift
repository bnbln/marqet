import Foundation
import MarqetCore
import MarqetReminders
import Testing

@Suite("InMemoryReminderGateway")
struct InMemoryReminderGatewayTests {
    @Test func markerRoundTrip() async throws {
        let gateway = InMemoryReminderGateway()
        let list = try await gateway.createList(named: "Einkaufen")
        let milk = try await gateway.createReminder(title: "Milch", notes: "laktosefrei", in: list.id)

        let assigned = try await gateway.setStore(named: "Aldi Süd", forReminder: milk.id)
        #expect(assigned.notes == "laktosefrei\n🛒 Aldi Süd")

        let moved = try await gateway.setStore(named: "Lidl", forReminder: milk.id)
        #expect(moved.notes == "laktosefrei\n🛒 Lidl")

        let cleared = try await gateway.setStore(named: nil, forReminder: milk.id)
        #expect(cleared.notes == "laktosefrei")
    }

    @Test func completionMovesBetweenOpenAndCompleted() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let gateway = InMemoryReminderGateway(now: start)
        let list = await gateway.seed(listTitle: "Einkaufen", reminders: [("Milch", nil), ("Brot", "🛒 Bäcker")])
        let milk = try #require(try await gateway.openReminders(in: list.id).first { $0.title == "Milch" })

        try await gateway.setCompleted(true, reminder: milk.id)

        #expect(try await gateway.openReminders(in: list.id).map(\.title) == ["Brot"])
        #expect(try await gateway.completedReminders(in: list.id, since: start).map(\.title) == ["Milch"])

        try await gateway.setCompleted(false, reminder: milk.id)
        #expect(try await gateway.openReminders(in: list.id).count == 2)
    }

    @Test func accessIsEnforced() async throws {
        let gateway = InMemoryReminderGateway(status: .notDetermined)
        await #expect(throws: ReminderGatewayError.accessDenied) { try await gateway.lists() }
        #expect(try await gateway.requestAccess())
        #expect(try await gateway.lists().isEmpty)
    }

    @Test func missingReminderThrows() async throws {
        let gateway = InMemoryReminderGateway()
        await #expect(throws: ReminderGatewayError.reminderNotFound) {
            try await gateway.setStore(named: "Aldi", forReminder: "does-not-exist")
        }
    }

    @Test func changesAreEmitted() async throws {
        let gateway = InMemoryReminderGateway()
        let list = try await gateway.createList(named: "Einkaufen")
        let stream = await gateway.changes()

        _ = try await gateway.createReminder(title: "Milch", notes: nil, in: list.id)

        var iterator = stream.makeAsyncIterator()
        let event: Void? = await iterator.next()
        #expect(event != nil)
    }
}
