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

private struct ItemChip: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .strokeBorder(Color.secondary, lineWidth: 1.2)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .frame(width: 84, height: 28)
        .background(Color(.tertiarySystemGroupedBackground), in: .capsule)
    }
}

// MARK: - Welcome: one list becomes store cards

/// The whole idea in two seconds: a mixed shopping list, and each item flies into its store.
struct SortingIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSorted = false
    /// Chips fade out before they go back to the list, so they never fly backwards.
    @State private var isVisible = true

    /// List position → store card; crossing paths make the sorting visible.
    private let items: [(title: LocalizedStringKey, shop: Int)] = [
        ("Zahnpasta", 1), ("Tomaten", 2), ("Milch", 0),
    ]
    private let shops = [Stage.supermarket, Stage.drugstore, Stage.market]

    var body: some View {
        scene
            .task(id: reduceMotion) {
                guard !reduceMotion else {
                    isSorted = true
                    return
                }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.3))
                    isSorted = true
                    try? await Task.sleep(for: .seconds(2.8))
                    withAnimation(.easeIn(duration: 0.3)) { isVisible = false }
                    try? await Task.sleep(for: .seconds(0.35))
                    isSorted = false
                    withAnimation(.easeOut(duration: 0.35)) { isVisible = true }
                }
            }
    }

    private var scene: some View {
        ZStack(alignment: .topLeading) {
            // The shopping list from Reminders.
            MiniCard {
                Label("Einkaufen", systemImage: "checklist")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .frame(width: Stage.size.width, height: 56, alignment: .topLeading)
            }

            // The store cards.
            ForEach(shops.indices, id: \.self) { index in
                MiniCard(cornerRadius: 16) {
                    VStack(spacing: 0) {
                        Image(systemName: shops[index].symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(shops[index].color)
                        Spacer()
                    }
                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                    .frame(width: cardWidth, height: 100)
                }
                .offset(x: CGFloat(index) * (cardWidth + 12), y: 84)
            }

            ForEach(items.indices, id: \.self) { index in
                ItemChip(title: items[index].title)
                    .position(isSorted ? cardSlot(items[index].shop) : listSlot(index))
                    // Staggered flight into the cards; the way back happens invisibly, without animation.
                    .animation(isSorted ? .spring(duration: 0.75, bounce: 0.28).delay(Double(index) * 0.18) : nil, value: isSorted)
                    .opacity(isVisible ? 1 : 0)
            }
        }
        .frame(width: Stage.size.width, height: Stage.size.height, alignment: .topLeading)
    }

    private var cardWidth: CGFloat { (Stage.size.width - 24) / 3 }

    private func listSlot(_ index: Int) -> CGPoint {
        CGPoint(x: 10 + 42 + CGFloat(index) * 94 + 4, y: 34)
    }

    private func cardSlot(_ shop: Int) -> CGPoint {
        CGPoint(x: CGFloat(shop) * (cardWidth + 12) + cardWidth / 2, y: 84 + 26 + 26)
    }
}

// MARK: - Access: the marker in the notes

/// Shows what Marqet writes: a reminder whose note gets the line "🛒 Markt".
struct MarkerIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            card(showsMarker: true)
        } else {
            PhaseAnimator([false, true]) { shows in
                card(showsMarker: shows)
            } animation: { shows in
                shows ? .spring(duration: 0.5, bounce: 0.3).delay(0.2) : .easeInOut(duration: 0.3).delay(2.2)
            }
        }
    }

    private func card(showsMarker: Bool) -> some View {
        MiniCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                row(title: "Tomaten", note: "reif", marker: showsMarker ? "🛒 Markt" : nil, color: Stage.market.color)
                Divider()
                row(title: "Milch", note: nil, marker: "🛒 Supermarkt", color: Stage.supermarket.color)
            }
            .padding(16)
            .frame(width: 260, alignment: .leading)
        }
        .frame(width: Stage.size.width, height: Stage.size.height)
    }

    private func row(title: LocalizedStringKey, note: LocalizedStringKey?, marker: LocalizedStringKey?, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .strokeBorder(Color.secondary, lineWidth: 1.5)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                if let marker {
                    Text(marker)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.12), in: .capsule)
                        .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                }
            }
        }
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

// MARK: - Siri: said, landed in the inbox

struct SiriIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            scene(landed: true)
        } else {
            PhaseAnimator([false, true]) { landed in
                scene(landed: landed)
            } animation: { landed in
                landed ? .spring(duration: 0.7, bounce: 0.25).delay(1.0) : .easeInOut(duration: 0.3).delay(2.2)
            }
        }
    }

    private func scene(landed: Bool) -> some View {
        ZStack(alignment: .top) {
            Image(systemName: "waveform")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !landed)
                .frame(height: 50)

            MiniCard(cornerRadius: 18) {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.fill")
                        Text("Inbox")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Color.gray)
                    Spacer()
                }
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .frame(width: 200, height: 80)
            }
            .offset(y: 78)

            ItemChip(title: "Milch")
                .offset(y: landed ? 78 + 28 + 12 : 52)
                .scaleEffect(landed ? 1 : 0.85)
                .opacity(landed ? 1 : 0.9)
        }
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
