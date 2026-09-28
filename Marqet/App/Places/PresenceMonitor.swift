import CoreLocation
import Foundation
import MarqetCore
import UserNotifications

/// Watches circles around the branches of stores worth a stop (KONZEPT-WIDGETS §13).
///
/// iOS keeps watching while Marqet is closed and relaunches it in the background on an arrival:
/// `start()` then recreates the monitor under the same name and the waiting event arrives.
@MainActor
final class PresenceMonitor {
    static let shared = PresenceMonitor()
    /// Letters and digits only – CoreLocation asserts on anything else (dots crash `CLMonitor.init`).
    static let monitorName = "MarqetStores"

    /// `true` = arrived, `false` = left. Set by the app model before `start()`.
    var handler: (@MainActor (Geofence, Bool, Date) async -> Void)?

    private var monitor: CLMonitor?
    /// Declares that Marqet needs "Immer" for as long as it watches branches.
    private var session: CLServiceSession?
    private var listening: Task<Void, Never>?

    var isRunning: Bool { monitor != nil }

    func start() async {
        guard monitor == nil else { return }
        session = CLServiceSession(authorization: .always)
        let monitor = await CLMonitor(Self.monitorName)
        self.monitor = monitor
        let events = await monitor.events
        listening = Task { [weak self] in
            do {
                for try await event in events {
                    guard let fence = Geofence(identifier: event.identifier) else { continue }
                    switch event.state {
                    case .satisfied: await self?.handler?(fence, true, event.date)
                    case .unsatisfied: await self?.handler?(fence, false, event.date)
                    default: continue
                    }
                }
            } catch {
                // The sequence ends when the monitor goes away; nothing to recover.
            }
        }
    }

    /// Replaces the watched circles; unchanged ones keep their state.
    func update(_ fences: [Geofence]) async {
        guard let monitor else { return }
        let wanted = Dictionary(fences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let current = Set(await monitor.identifiers)
        for identifier in current where wanted[identifier] == nil {
            await monitor.remove(identifier)
        }
        for (identifier, fence) in wanted where !current.contains(identifier) {
            let condition = CLMonitor.CircularGeographicCondition(center: fence.center.clCoordinate, radius: fence.radius)
            await monitor.add(condition, identifier: identifier, assuming: .unsatisfied)
        }
    }

    /// Switched off: forget every circle, so iOS stops waking Marqet.
    func stop() async {
        if let monitor {
            for identifier in await monitor.identifiers { await monitor.remove(identifier) }
        }
        listening?.cancel()
        listening = nil
        monitor = nil
        session?.invalidate()
        session = nil
    }
}

/// "Du bist bei Aldi Süd": the notification when no Live Activity can start (iOS starts them only
/// from the foreground). "Einkauf starten" opens Marqet on the store and starts it.
enum ArrivalNotifier {
    static let category = "arrival"
    static let startAction = "start-trip"
    static let storeKey = "storeID"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    static func registerCategory() {
        let start = UNNotificationAction(identifier: startAction, title: String(localized: "Einkauf starten"), options: [.foreground])
        let arrival = UNNotificationCategory(identifier: category, actions: [start], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([arrival])
    }

    static func notifyArrival(at store: Store, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Du bist bei \(store.name)")
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = category
        content.userInfo = [storeKey: store.id.uuidString]
        content.relevanceScore = 1
        let request = UNNotificationRequest(identifier: identifier(for: store.id), content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Left the store: the notification is no longer true.
    static func withdraw(for storeID: Store.ID) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier(for: storeID)])
    }

    private static func identifier(for storeID: Store.ID) -> String {
        "arrival-\(storeID.uuidString)"
    }
}

/// Taps on arrival notifications: open the store, and with "Einkauf starten" start the trip.
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationResponder()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        guard content.categoryIdentifier == ArrivalNotifier.category,
              let raw = content.userInfo[ArrivalNotifier.storeKey] as? String,
              let storeID = UUID(uuidString: raw) else { return }
        let startsTrip = response.actionIdentifier == ArrivalNotifier.startAction
        await Self.open(storeID: storeID, startsTrip: startsTrip)
    }

    /// With the app open the pager already jumped to the store – no banner on top of it.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }

    @MainActor
    private static func open(storeID: Store.ID, startsTrip: Bool) async {
        guard let model = AppModel.active else { return }
        if startsTrip { await model.startTrip(at: storeID) }
        model.open(.page(.store(storeID)))
    }
}
