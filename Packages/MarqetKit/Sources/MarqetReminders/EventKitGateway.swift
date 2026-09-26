import CoreGraphics
import EventKit
import Foundation
import MarqetCore

/// `ReminderGateway` backed by EventKit.
///
/// Holds the app's single `EKEventStore`. `EKReminder` objects never leave this actor –
/// callers only see `ReminderSnapshot` values. Actor isolation serializes all writes.
public actor EventKitGateway: ReminderGateway {
    private let store = EKEventStore()

    public init() {}

    // MARK: Authorization

    public nonisolated func authorizationStatus() -> RemindersAuthorization {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess: .fullAccess
        @unknown default: .denied
        }
    }

    public func requestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: Lists

    public func lists() throws -> [ReminderList] {
        try ensureAccess()
        return store.calendars(for: .reminder)
            .map(ReminderList.init)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func createList(named title: String) throws -> ReminderList {
        try ensureAccess()
        let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first { $0.sourceType == .calDAV }
            ?? store.sources.first { $0.sourceType == .local }
        guard let source else { throw ReminderGatewayError.noSourceForNewList }

        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = title
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return ReminderList(calendar)
    }

    public func removeList(id: String) throws {
        let calendar = try calendar(withID: id)
        try store.removeCalendar(calendar, commit: true)
    }

    // MARK: Reading

    public func openReminders(in listID: String) async throws -> [ReminderSnapshot] {
        let calendar = try calendar(withID: listID)
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [calendar]
        )
        return await fetch(predicate)
    }

    public func completedReminders(in listID: String, since date: Date) async throws -> [ReminderSnapshot] {
        let calendar = try calendar(withID: listID)
        let predicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: date, ending: nil, calendars: [calendar]
        )
        return await fetch(predicate)
    }

    private func fetch(_ predicate: NSPredicate) async -> [ReminderSnapshot] {
        await withCheckedContinuation { continuation in
            // Snapshots are created inside the completion handler, so no EKReminder crosses threads.
            _ = store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(ReminderSnapshot.init))
            }
        }
    }

    // MARK: Writing

    public func createReminder(title: String, notes: String?, in listID: String) throws -> ReminderSnapshot {
        let calendar = try calendar(withID: listID)
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = title
        reminder.notes = notes
        try store.save(reminder, commit: true)
        return ReminderSnapshot(reminder)
    }

    public func updateTitle(_ title: String, ofReminder id: String) throws -> ReminderSnapshot {
        let reminder = try freshReminder(withID: id)
        reminder.title = title
        try store.save(reminder, commit: true)
        return ReminderSnapshot(reminder)
    }

    public func updateNotes(
        ofReminder id: String,
        _ transform: @Sendable (String?) -> String?
    ) throws -> ReminderSnapshot {
        let reminder = try freshReminder(withID: id)
        reminder.notes = transform(reminder.notes)
        try store.save(reminder, commit: true)
        return ReminderSnapshot(reminder)
    }

    public func setCompleted(_ isCompleted: Bool, reminder id: String) throws {
        let reminder = try freshReminder(withID: id)
        reminder.isCompleted = isCompleted
        try store.save(reminder, commit: true)
    }

    public func deleteReminder(id: String) throws {
        let reminder = try freshReminder(withID: id)
        try store.remove(reminder, commit: true)
    }

    // MARK: Change notifications

    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let token = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: nil
        ) { _ in
            continuation.yield()
        }
        let observer = ObserverToken(token)
        continuation.onTermination = { _ in
            NotificationCenter.default.removeObserver(observer.token)
        }
        return stream
    }

    // MARK: Helpers

    private func ensureAccess() throws {
        guard authorizationStatus() == .fullAccess else { throw ReminderGatewayError.accessDenied }
    }

    private func calendar(withID id: String) throws -> EKCalendar {
        try ensureAccess()
        guard let calendar = store.calendar(withIdentifier: id) else { throw ReminderGatewayError.listNotFound }
        return calendar
    }

    /// Looks up the reminder and refreshes it, so writes start from the latest synced state.
    private func freshReminder(withID id: String) throws -> EKReminder {
        try ensureAccess()
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, reminder.refresh() else {
            throw ReminderGatewayError.reminderNotFound
        }
        return reminder
    }
}

private final class ObserverToken: @unchecked Sendable {
    // Only touched in `onTermination` to unregister – NotificationCenter is thread-safe.
    let token: any NSObjectProtocol
    init(_ token: any NSObjectProtocol) { self.token = token }
}

extension ReminderSnapshot {
    init(_ reminder: EKReminder) {
        self.init(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            creationDate: reminder.creationDate,
            lastModifiedDate: reminder.lastModifiedDate
        )
    }
}

extension ReminderList {
    init(_ calendar: EKCalendar) {
        self.init(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            colorHex: calendar.cgColor?.hexString,
            sourceTitle: calendar.source?.title ?? "",
            allowsModifications: calendar.allowsContentModifications
        )
    }
}

extension CGColor {
    fileprivate var hexString: String? {
        guard
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
            let components = converted(to: sRGB, intent: .defaultIntent, options: nil)?.components,
            components.count >= 3
        else { return nil }
        let bytes = components.prefix(3).map { Int(($0 * 255).rounded()).clamped(to: 0...255) }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
