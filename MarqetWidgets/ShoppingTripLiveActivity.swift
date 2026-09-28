import ActivityKit
import MarqetCore
import SwiftUI
import WidgetKit

/// The Live Activity "Einkauf" (KONZEPT-WIDGETS §5): Lock Screen, Dynamic Island (also landscape,
/// iOS 27), StandBy, Apple Watch Smart Stack and CarPlay via the small family.
struct ShoppingTripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingActivityAttributes.self) { context in
            TripActivityContent(status: context.state)
                .activityBackgroundTint(context.state.store.color)
                .activitySystemActionForegroundColor(context.state.store.foregroundOnColor)
                .widgetURL(MarqetLink.trip.url)
        } dynamicIsland: { context in
            let status = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WidgetBadge(store: status.store, size: 40)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TripExpandedTrailing(status: status)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(status.store.name)
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(1)
                        if status.isOnTheWay {
                            Text(TripStatusText.short(status))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TripExpandedBottom(status: status)
                        .padding(.top, 4)
                }
            } compactLeading: {
                WidgetBadge(store: status.store, size: 22)
            } compactTrailing: {
                TripCompactTrailing(status: status)
            } minimal: {
                TripRing(status: status, size: 22)
            }
            .keylineTint(status.store.colorOnDark)
            .widgetURL(MarqetLink.trip.url)
        }
        .supplementalActivityFamilies([.small])
    }
}

/// Lock Screen and StandBy use the banner, Watch and CarPlay the small layout.
private struct TripActivityContent: View {
    let status: TripStatus
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small: TripSmallView(status: status)
        default: TripLockScreenView(status: status)
        }
    }
}

// MARK: - Previews

extension ShoppingActivityAttributes {
    static let preview = ShoppingActivityAttributes(tripID: UUID(), listTitle: "Einkaufen")
}

#Preview("Sperrbildschirm", as: .content, using: ShoppingActivityAttributes.preview) {
    ShoppingTripLiveActivity()
} contentStates: {
    WidgetSnapshot.sample.sampleTripStatus!
}

#Preview("Dynamic Island", as: .dynamicIsland(.expanded), using: ShoppingActivityAttributes.preview) {
    ShoppingTripLiveActivity()
} contentStates: {
    WidgetSnapshot.sample.sampleTripStatus!
}
