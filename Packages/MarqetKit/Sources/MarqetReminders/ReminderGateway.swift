import Foundation
import MarqetCore

public enum RemindersAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case restricted
    /// Not enough for Marqet – it has to read the list.
    case writeOnly
    case fullAccess
}

public enum ReminderGatewayError: LocalizedError, Sendable, Equatable {
    case accessDenied
    case listNotFound
    case reminderNotFound
    case noSourceForNewList

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            String(localized: "Marqet hat keinen Zugriff auf deine Erinnerungen.")
        case .listNotFound:
            String(localized: "Die Erinnerungsliste wurde nicht gefunden.")
        case .reminderNotFound:
            String(localized: "Der Eintrag wurde nicht gefunden. Er wurde vielleicht auf einem anderen Gerät gelöscht.")
        case .noSourceForNewList:
            String(localized: "Es konnte kein Account gefunden werden, in dem eine neue Liste angelegt werden kann.")
        }
    }
}

/// All access to Apple Reminders goes through this protocol (KONZEPT §9.3).
/// Implementations serialize writes so rapid check-offs never get lost.
public protocol ReminderGateway: Sendable {
    func authorizationStatus() async -> RemindersAuthorization
    /// Asks for full access. Returns `true` if granted.
    func requestAccess() async throws -> Bool

    func lists() async throws -> [ReminderList]
    func createList(named title: String) async throws -> ReminderList
    func removeList(id: String) async throws

    func openReminders(in listID: String) async throws -> [ReminderSnapshot]
    func completedReminders(in listID: String, since date: Date) async throws -> [ReminderSnapshot]

    func createReminder(title: String, notes: String?, in listID: String) async throws -> ReminderSnapshot
    func updateTitle(_ title: String, ofReminder id: String) async throws -> ReminderSnapshot
    /// Refreshes the reminder first, then applies `transform` to the *current* notes – so concurrent
    /// edits made in the Reminders app are not overwritten (KONZEPT §4.3).
    func updateNotes(ofReminder id: String, _ transform: @Sendable (String?) -> String?) async throws -> ReminderSnapshot
    func setCompleted(_ isCompleted: Bool, reminder id: String) async throws
    func deleteReminder(id: String) async throws

    /// Emits whenever the reminder database changed (in this app or elsewhere).
    func changes() async -> AsyncStream<Void>
}

extension ReminderGateway {
    /// Writes (or removes, if `storeName` is `nil`) the `🛒 <store>` marker line.
    @discardableResult
    public func setStore(named storeName: String?, forReminder id: String) async throws -> ReminderSnapshot {
        try await updateNotes(ofReminder: id) { notes in
            StoreMarker.write(storeName: storeName, into: notes)
        }
    }
}
