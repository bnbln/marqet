import ActivityKit
import Foundation
import MarqetCore

/// "Du bist bei Aldi Süd": an update that lights up the Lock Screen and expands the Dynamic Island.
struct TripAlert: Sendable {
    let title: String
    let body: String

    var configuration: AlertConfiguration {
        AlertConfiguration(title: LocalizedStringResource(stringLiteral: title),
                           body: LocalizedStringResource(stringLiteral: body),
                           sound: .default)
    }
}

struct TripActivitySync: Sendable {
    /// Nothing left anywhere – the model ends the trip.
    var finished = false
    /// A Live Activity shows the trip right now.
    var isRunning = false
}

/// Starts, updates and ends the Live Activity "Einkauf" from the trip (KONZEPT-WIDGETS §5).
/// Only the app process may do that; widget buttons reach it through `LiveActivityIntent`.
///
/// Nonisolated on purpose: `Activity` is not `Sendable`, so it never leaves this function's region.
enum TripActivityController {
    /// After the last item the activity shows "Einkauf fertig" this long.
    static let finishedDismissal: TimeInterval = 10 * 60

    /// Brings the activity in line with the trip. `onDismiss` runs when the user swipes the
    /// activity away. iOS starts activities only while Marqet is in the foreground; in the
    /// background the result says none is running.
    static func sync(
        snapshot: WidgetSnapshot,
        trip: ShoppingTrip?,
        alert: TripAlert? = nil,
        onDismiss: @escaping @Sendable (UUID) async -> Void
    ) async -> TripActivitySync {
        let activities = Activity<ShoppingActivityAttributes>.activities
        guard let trip, let status = TripStatus.make(snapshot: snapshot, trip: trip) else {
            for activity in activities where activity.activityState == .active {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return TripActivitySync()
        }
        for activity in activities where activity.attributes.tripID != trip.id && activity.activityState == .active {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let content = ActivityContent(state: status, staleDate: trip.staleDate, relevanceScore: 1)
        let current = activities.first { $0.attributes.tripID == trip.id && $0.activityState == .active }

        if status.isFinished {
            await current?.end(content, dismissalPolicy: .after(.now.addingTimeInterval(finishedDismissal)))
            return TripActivitySync(finished: true, isRunning: false)
        }
        if let current {
            if let alert {
                await current.update(content, alertConfiguration: alert.configuration)
            } else if current.content.state != status || current.content.staleDate != content.staleDate {
                await current.update(content)
            }
            return TripActivitySync(isRunning: true)
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return TripActivitySync() }
        let attributes = ShoppingActivityAttributes(tripID: trip.id, listTitle: snapshot.listTitle)
        let started: Activity<ShoppingActivityAttributes>?
        if let alert {
            started = try? Activity.request(attributes: attributes, content: content, style: .standard,
                                            alertConfiguration: alert.configuration, start: .now)
        } else {
            started = try? Activity.request(attributes: attributes, content: content)
        }
        guard let activity = started else { return TripActivitySync() }
        let tripID = trip.id
        Task {
            for await state in activity.activityStateUpdates where state == .dismissed {
                await onDismiss(tripID)
            }
        }
        return TripActivitySync(isRunning: true)
    }
}
