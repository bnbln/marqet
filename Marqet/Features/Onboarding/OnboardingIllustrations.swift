import SwiftUI

// Illustrations on the onboarding stage (300 × 184 pt). Neutral store colors and symbols, no
// brand logos. With Reduce Motion each shows its final state without moving.

private enum Stage {
    static let size = CGSize(width: OnboardingMetrics.stageWidth, height: OnboardingMetrics.stageHeight)

    struct Shop {
        let symbol: String
        let color: Color
    }

    static let supermarket = Shop(symbol: "cart.fill", color: Color(red: 0.12, green: 0.37, blue: 0.75))
    static let drugstore = Shop(symbol: "drop.fill", color: Color(red: 0.84, green: 0.2, blue: 0.42))
    static let market = Shop(symbol: "carrot.fill", color: Color(red: 0.18, green: 0.62, blue: 0.27))
}

/// A white mini card with a soft shadow – the look of a Marqet card, scaled down.
private struct MiniCard<Content: View>: View {
    var cornerRadius: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
    }
}

// MARK: - Welcome and access

/// A list points to three stores; small glass map pins appear once around them.
struct SortingIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealedPins = 0
    private let shops = [Stage.supermarket, Stage.drugstore, Stage.market]
    private let storePositions: [CGPoint] = [
        CGPoint(x: 46, y: 52), CGPoint(x: 132, y: 65), CGPoint(x: 86, y: 122),
    ]

    var body: some View {
        VStack(spacing: 4) {
            Color.clear.frame(height: 34)

            HStack(spacing: 12) {
                Image(systemName: "checklist")
                    .frame(width: 60)
                Image(systemName: "arrow.right")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                ZStack {
                    ForEach(shops.indices, id: \.self) { index in
                        Image(systemName: shops[index].symbol)
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(shops[index].color)
                            .frame(width: 54, height: 54)
                            .background(shops[index].color.opacity(0.12), in: .circle)
                            .position(storePositions[index])

                        FloatingPinBubble(
                            color: shops[index].color,
                            index: index,
                            isVisible: index < revealedPins
                        )
                            .position(x: storePositions[index].x + 18, y: storePositions[index].y - 23)
                    }
                }
                .frame(width: 160, height: 154)
            }
            .font(.system(size: 42, weight: .regular))
            .foregroundStyle(.tint)
            .frame(width: Stage.size.width, height: 154)
        }
        .frame(width: Stage.size.width, height: Stage.size.height)
        .sensoryFeedback(trigger: revealedPins) { previous, current in
            !reduceMotion && current > previous ? .impact(weight: .light, intensity: 0.7) : nil
        }
        .task(id: reduceMotion) {
            if reduceMotion {
                revealedPins = shops.count
            } else {
                revealedPins = 0
                try? await Task.sleep(for: .milliseconds(320))
                for count in 1...shops.count {
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.54)) {
                        revealedPins = count
                    }
                    try? await Task.sleep(for: .milliseconds(240))
                }
            }
        }
    }
}

/// A small continuous drift starts after the spring settles, with a different rhythm per pin.
private struct FloatingPinBubble: View {
    let color: Color
    let index: Int
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false
    @State private var isFloating = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(color.opacity(0.45), lineWidth: 1.2)
                .frame(width: 28, height: 28)
                .scaleEffect(burst ? 1.55 : 0.7)
                .opacity(isVisible && !reduceMotion && !burst ? 0.7 : 0)

            Image(systemName: "mappin")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .glassEffect(.regular, in: .circle)
                .overlay(Circle().strokeBorder(color.opacity(0.18)))
                .offset(y: isFloating ? -3 : 2)
                .rotationEffect(.degrees(isFloating ? 2.5 : -2.5))
                .animation(
                    .easeInOut(duration: 1.35 + Double(index) * 0.23).repeatForever(autoreverses: true),
                    value: isFloating
                )
        }
        .scaleEffect(isVisible ? 1 : 0.12)
        .opacity(isVisible ? 1 : 0)
        .task(id: isVisible && !reduceMotion) {
            guard isVisible && !reduceMotion else {
                burst = false
                isFloating = false
                return
            }
            burst = false
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.6)) { burst = true }
            try? await Task.sleep(for: .milliseconds(520))
            guard !Task.isCancelled else { return }
            isFloating = true
        }
    }
}

/// A plain Reminders symbol keeps the permission step visually quiet.
struct MarkerIllustration: View {
    var body: some View {
        Image(systemName: "checklist")
            .font(.system(size: 64, weight: .light))
            .foregroundStyle(.tint)
            .frame(width: Stage.size.width, height: Stage.size.height)
    }
}

// MARK: - List: pick the shopping list

struct ListIllustration: View {
    var body: some View {
        MiniCard(cornerRadius: 18) {
            VStack(spacing: 0) {
                row("Einkaufen", color: .green, selected: true)
                Divider().padding(.leading, 34)
                row("Familie", color: .orange, selected: false)
                Divider().padding(.leading, 34)
                row("Arbeit", color: .blue, selected: false)
            }
            .padding(.vertical, 6)
            .frame(width: 240)
        }
        .frame(width: Stage.size.width, height: Stage.size.height)
    }

    private func row(_ title: LocalizedStringKey, color: Color, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(title).font(.subheadline.weight(selected ? .semibold : .regular))
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tint)
                    .symbolEffect(.bounce, options: .repeat(.periodic(delay: 2.5)))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }
}

// MARK: - Stores: tap order becomes card order

struct StoresIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let shops = [Stage.supermarket, Stage.drugstore, Stage.market]

    var body: some View {
        if reduceMotion {
            scene(count: 3)
        } else {
            PhaseAnimator([0, 1, 2, 3]) { count in
                scene(count: count)
            } animation: { count in
                count == 0 ? .easeInOut(duration: 0.3).delay(1.6) : .spring(duration: 0.4, bounce: 0.4).delay(0.35)
            }
        }
    }

    private func scene(count: Int) -> some View {
        HStack(spacing: 22) {
            ForEach(shops.indices, id: \.self) { index in
                Image(systemName: shops[index].symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(shops[index].color, in: .circle)
                    .overlay(alignment: .topTrailing) {
                        if index < count {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor, in: .circle)
                                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                                .offset(x: 6, y: -6)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .scaleEffect(index < count ? 1 : 0.9)
                    .opacity(index < count ? 1 : 0.55)
            }
        }
        .frame(width: Stage.size.width, height: Stage.size.height)
    }
}

// MARK: - Siri

struct SiriIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 64, weight: .light))
            .foregroundStyle(.tint)
            .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            .frame(width: Stage.size.width, height: Stage.size.height)
    }
}

#Preview("Sortieren") {
    SortingIllustration().padding().background(Color(.systemGroupedBackground))
}

#Preview("Alle") {
    ScrollView {
        VStack(spacing: 24) {
            SortingIllustration()
            MarkerIllustration()
            ListIllustration()
            StoresIllustration()
            SiriIllustration()
        }
    }
    .background(Color(.systemGroupedBackground))
}
