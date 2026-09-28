import AppIntents
import MarqetCore
import SwiftUI
import WidgetKit

// The Live Activity "Einkauf" (KONZEPT-WIDGETS §5.2): Lock Screen, Dynamic Island, Watch and CarPlay.

/// Lock Screen and StandBy: the store's colored header as the whole banner.
struct TripLockScreenView: View {
    let status: TripStatus

    private var store: Store { status.store }
    private var foreground: Color { store.foregroundOnColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                WidgetBadge(store: store, size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                    Text(progressText)
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.85)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 4)
                if status.hasLoyaltyCard {
                    Link(destination: MarqetLink.storeLoyaltyCards(store.id).url) {
                        Image(systemName: "wallet.pass.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.22), in: .circle)
                    }
                    .accessibilityLabel("Kundenkarte zeigen")
                }
                Button(intent: EndTripIntent()) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.22), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Einkauf beenden")
            }

            ProgressBar(progress: status.progress, color: foreground)
                .frame(height: 5)

            if status.isStoreDone {
                doneRow
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 2) {
                    ForEach(status.next.prefix(4)) { line in
                        TripLineButton(line: line, color: foreground, fontSize: 14)
                            .frame(height: 26)
                    }
                }
            }

            if !status.stops.isEmpty, !status.isStoreDone {
                Text("Danach: " + status.stops.map { "\($0.name) \($0.count)" }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.8)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(foreground)
        .padding(14)
    }

    private var title: String {
        status.isFinished ? String(localized: "Einkauf fertig") : String(localized: "Einkauf bei \(store.name)")
    }

    private var progressText: String {
        if status.isStoreDone { return String(localized: "Alles erledigt bei \(store.name)") }
        return String(localized: "\(status.doneCount) von \(status.totalCount) erledigt · noch \(status.openCount)")
    }

    @ViewBuilder
    private var doneRow: some View {
        if let next = status.stops.first {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20))
                Button(intent: NextStoreIntent(storeID: next.storeID)) {
                    HStack(spacing: 6) {
                        Text("Weiter zu \(next.name)")
                        Text(next.count, format: .number)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .background(.white.opacity(0.25), in: .capsule)
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(.white.opacity(0.22), in: .capsule)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        } else {
            Label("Alles erledigt – gut eingekauft!", systemImage: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .semibold))
        }
    }
}

/// A check circle with the item title – checking off from the Lock Screen.
struct TripLineButton: View {
    let line: TripStatus.Line
    let color: Color
    var fontSize: CGFloat = 14

    var body: some View {
        Button(intent: CheckItemIntent(itemID: line.id)) {
            HStack(spacing: 7) {
                Image(systemName: "circle")
                    .font(.system(size: fontSize + 3))
                Text(line.title)
                    .font(.system(size: fontSize, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(color)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(line.title) abhaken")
    }
}

struct ProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.25))
                Capsule().fill(color)
                    .frame(width: max(proxy.size.width * progress, progress > 0 ? 5 : 0))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A ring in the store color with the number of open items.
struct TripRing: View {
    let status: TripStatus
    var size: CGFloat = 22
    var showsCount = true

    var body: some View {
        ZStack {
            Circle().stroke(status.store.colorOnDark.opacity(0.3), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: status.progress)
                .stroke(status.store.colorOnDark, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if status.isStoreDone {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(status.store.colorOnDark)
            } else if showsCount {
                Text(status.openCount, format: .number)
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Noch \(status.openCount) offen")
    }
}

/// Compact trailing: the ring – or, with the Dynamic Island narrow in landscape (iOS 27),
/// just the number.
struct TripCompactTrailing: View {
    let status: TripStatus

    var body: some View {
        if #available(iOS 27.0, *) {
            LimitedWidthAwareTrailing(status: status)
        } else {
            TripRing(status: status)
        }
    }
}

@available(iOS 27.0, *)
private struct LimitedWidthAwareTrailing: View {
    let status: TripStatus
    @Environment(\.isDynamicIslandLimitedInWidth) private var isLimitedInWidth

    var body: some View {
        if isLimitedInWidth {
            Text(status.openCount, format: .number)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(status.store.colorOnDark)
        } else {
            TripRing(status: status)
        }
    }
}

/// Expanded Dynamic Island, bottom region: progress, the next two items, card and next/end.
/// The buttons keep clear of the island's rounded bottom corners.
struct TripExpandedBottom: View {
    let status: TripStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressBar(progress: status.progress, color: status.store.colorOnDark)
                .frame(height: 4)
            if status.isStoreDone {
                Text(status.isFinished ? "Alles erledigt – gut eingekauft!" : "Alles erledigt bei \(status.store.name)")
                    .font(.system(size: 14, weight: .semibold))
            } else {
                HStack(spacing: 12) {
                    ForEach(status.next.prefix(2)) { line in
                        TripLineButton(line: line, color: .white, fontSize: 14)
                    }
                }
            }
            HStack(spacing: 8) {
                if status.hasLoyaltyCard {
                    Link(destination: MarqetLink.storeLoyaltyCards(status.store.id).url) {
                        Label("Kundenkarte", systemImage: "wallet.pass.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(.white.opacity(0.16), in: .capsule)
                    }
                }
                Spacer(minLength: 0)
                if status.isStoreDone, let next = status.stops.first {
                    // Label shortened to the store: the capsule sits close to the corner.
                    Button(intent: NextStoreIntent(storeID: next.storeID)) {
                        Label("Weiter zu \(next.name)", systemImage: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(status.store.colorOnDark.opacity(0.35), in: .capsule)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(intent: EndTripIntent()) {
                        Label("Beenden", systemImage: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(.white.opacity(0.16), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .foregroundStyle(.white)
    }
}

/// Expanded Dynamic Island, trailing region: open items, or a check when this store is done.
struct TripExpandedTrailing: View {
    let status: TripStatus

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if status.isStoreDone {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(status.store.colorOnDark)
                Text("erledigt")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text(status.openCount, format: .number)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(status.store.colorOnDark)
                    .contentTransition(.numericText())
                Text("offen")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Apple Watch Smart Stack and CarPlay (`.small` activity family).
struct TripSmallView: View {
    let status: TripStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                WidgetBadge(store: status.store, size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(status.store.name)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Text(status.isStoreDone ? "Alles erledigt" : "\(status.openCount) offen")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                TripRing(status: status, size: 26)
            }
            if let line = status.next.first {
                TripLineButton(line: line, color: .primary, fontSize: 13)
            }
        }
        .padding(10)
    }
}
