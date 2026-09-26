import Foundation
import MarqetCore

/// `ReminderGateway` without EventKit – for unit tests and SwiftUI previews.
public actor InMemoryReminderGateway: ReminderGateway {
    private var status: RemindersAuthorization
    private var listsByID: [String: ReminderList] = [:]
    private var reminders: [String: (listID: String, snapshot: ReminderSnapshot)] = [:]
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var clock: Date

    public init(status: RemindersAuthorization = .fullAccess, now: Date = .now) {
        self.status = status
        self.clock = now
    }

    /// Adds a list with reminders, e.g. for previews.
    @discardableResult
    public func seed(listTitle: String, reminders items: [(title: String, notes: String?)]) -> ReminderList {
        let list = makeList(title: listTitle)
        for item in items {
            insert(title: item.title, notes: item.notes, listID: list.id)
        }
        return list
    }

    // MARK: ReminderGateway

    public func authorizationStatus() -> RemindersAuthorization { status }

    public func requestAccess() -> Bool {
        if status == .notDetermined { status = .fullAccess }
        return status == .fullAccess
    }

    public func lists() throws -> [ReminderList] {
        try ensureAccess()
        return listsByID.values.sorted { $0.title < $1.title }
    }

    public func createList(named title: String) throws -> ReminderList {
        try ensureAccess()
        let list = makeList(title: title)
        notify()
        return list
    }

    public func removeList(id: String) throws {
        try ensureAccess()
        guard listsByID.removeValue(forKey: id) != nil else { throw ReminderGatewayError.listNotFound }
        reminders = reminders.filter { $0.value.listID != id }
        notify()
    }

    public func openReminders(in listID: String) throws -> [ReminderSnapshot] {
        try snapshots(in: listID).filter { !$0.isCompleted }
    }

    public func completedReminders(in listID: String, since date: Date) throws -> [ReminderSnapshot] {
        try snapshots(in: listID).filter { $0.isCompleted && ($0.completionDate ?? .distantPast) >= date }
    }

    public func createReminder(title: String, notes: String?, in listID: String) throws -> ReminderSnapshot {
        try ensureAccess()
        guard listsByID[listID] != nil else { throw ReminderGatewayError.listNotFound }
        let snapshot = insert(title: title, notes: notes, listID: listID)
        notify()
        return snapshot
    }

    public func updateTitle(_ title: String, ofReminder id: String) throws -> ReminderSnapshot {
        try mutate(id) { $0.title = title }
    }

    public func updateNotes(
        ofReminder id: String,
        _ transform: @Sendable (String?) -> String?
    ) throws -> ReminderSnapshot {
        try mutate(id) { $0.notes = transform($0.notes) }
    }

    public func setCompleted(_ isCompleted: Bool, reminder id: String) throws {
        let now = tick()
        try mutate(id) {
            $0.isCompleted = isCompleted
            $0.completionDate = isCompleted ? now : nil
        }
    }

    public func deleteReminder(id: String) throws {
        try ensureAccess()
        guard reminders.removeValue(forKey: id) != nil else { throw ReminderGatewayError.reminderNotFound }
        notify()
    }

    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    // MARK: Helpers

    private func ensureAccess() throws {
        guard status == .fullAccess else { throw ReminderGatewayError.accessDenied }
    }

    private func makeList(title: String) -> ReminderList {
        let list = ReminderList(id: UUID().uuidString, title: title, colorHex: "#FF9500", sourceTitle: "iCloud")
        listsByID[list.id] = list
        return list
    }

    @discardableResult
    private func insert(title: String, notes: String?, listID: String) -> ReminderSnapshot {
        let now = tick()
        let snapshot = ReminderSnapshot(
            id: UUID().uuidString, title: title, notes: notes,
            creationDate: now, lastModifiedDate: now
        )
        reminders[snapshot.id] = (listID, snapshot)
        return snapshot
    }

    private func snapshots(in listID: String) throws -> [ReminderSnapshot] {
        try ensureAccess()
        guard listsByID[listID] != nil else { throw ReminderGatewayError.listNotFound }
        return reminders.values
            .filter { $0.listID == listID }
            .map(\.snapshot)
            .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
    }

    @discardableResult
    private func mutate(_ id: String, _ change: (inout ReminderSnapshot) -> Void) throws -> ReminderSnapshot {
        try ensureAccess()
        guard var entry = reminders[id] else { throw ReminderGatewayError.reminderNotFound }
        change(&entry.snapshot)
        entry.snapshot.lastModifiedDate = tick()
        reminders[id] = entry
        notify()
        return entry.snapshot
    }

    /// Monotonic fake clock so creation order is deterministic in tests.
    private func tick() -> Date {
        clock = clock.addingTimeInterval(1)
        return clock
    }

    private func notify() {
        for continuation in continuations.values { continuation.yield() }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}
