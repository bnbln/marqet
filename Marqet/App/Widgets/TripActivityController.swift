import ActivityKit
import Foundation
import MarqetCore

/// Starts, updates and ends the Live Activity "Einkauf" from the trip (KONZEPT-WIDGETS §5).
/// Only the app process may do that; widget buttons reach it through `LiveActivityIntent`.
///
/// Nonisolated on purpose: `Activity` is not `Sendable`, so it never leaves this function's region.
enum TripActivityController {
    /// After the last item the activity shows "Einkauf fertig" this long.
    static let finishedDismissal: TimeInterval = 10 * 60

    /// Brings the activity in line with the trip. Returns `true` when the trip is finished
    /// (nothing left anywhere) – the model then ends it. `onDismiss` runs when the user swipes the
    /// activity away.
    static func sync(
        snapshot: WidgetSnapshot,
        trip: ShoppingTrip?,
        onDismiss: @escaping @Sendable (UUID) async -> Void
    ) async -> Bool {
        let activities = Activity<ShoppingActivityAttributes>.activities
        guard let trip, let status = TripStatus.make(snapshot: snapshot, trip: trip) else {
            for activity in activities where activity.activityState == .active {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return false
        }
        for activity in activities where activity.attributes.tripID != trip.id && activity.activityState == .active {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let content = ActivityContent(state: status, staleDate: trip.staleDate, relevanceScore: 1)
        let current = activities.first { $0.attributes.tripID == trip.id && $0.activityState == .active }

        if status.isFinished {
            await current?.end(content, dismissalPolicy: .after(.now.addingTimeInterval(finishedDismissal)))
            return true
        }
        if let current {
            if current.content.state != status || current.content.staleDate != content.staleDate {
                await current.update(content)
            }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = ShoppingActivityAttributes(tripID: trip.id, listTitle: snapshot.listTitle)
            if let activity = try? Activity.request(attributes: attributes, content: content) {
                let tripID = trip.id
                Task {
                    for await state in activity.activityStateUpdates where state == .dismissed {
                        await onDismiss(tripID)
                    }
                }
            }
        }
        return false
    }
}
