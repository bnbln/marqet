import MarqetCore
import SwiftUI

/// The card view of "Zuordnen" (KONZEPT §7.4), the default: the items as a stack on top, the stores
/// as a grid below, "Vorschläge übernehmen" pinned to the bottom.
/// - Drag the top card down: it shrinks on the way and lands on the store it is dropped on.
/// - Swipe it left: later. Swipe it right: the suggested store (later without one).
/// - A tap on a store sends the card there as well (fast, and for VoiceOver).
/// The grid fills its last row with chains the user does not have yet – clearly cheaper ones
/// first, then usual stores for the kind of product. Dropping on one adds it.
struct TriageCards: View {
    @Binding var showsAddStore: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppAccentPalette.storageKey) private var accentPaletteKey = AppAccentPalette.leaf.rawValue

    /// Resting frame of the top card; the card itself is drawn above everything at this frame.
    @State private var slot: CGRect = .zero
    @State private var targets: [TriageTarget: CGRect] = [:]
    @State private var bottomBarTop: CGFloat = .infinity
    @State private var columns = 4

    @State private var translation: CGSize = .zero
    /// Point of the card the finger holds; the card shrinks towards it.
    @State private var anchor: UnitPoint = .center
    @State private var isDragging = false
    /// Final size while flying into a store tile.
    @State private var landingScale: CGFloat?
    @State private var hovered: TriageTarget?
    /// The card has left; hidden until the queue moves on, so it never jumps back.
    @State private var leaving: ShoppingItem.ID?
    /// A card is on its way out; the next one takes input once it has left, not after saving.
    @State private var isFlying = false

    static let space = "triage"
    private static let tileMinimum: CGFloat = 84
    private static let tileSpacing: CGFloat = 10

    private var accentColor: Color {
        AppAccentPalette(rawValue: accentPaletteKey)?.color ?? AppAccentPalette.leaf.color
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                // iPad and the open Duo: the stack on the left, the stores on the right.
                AdaptiveSplit {
                    VStack(spacing: 44) {
                        deck.frame(maxWidth: 440, maxHeight: 320)
                        gestureHint
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } secondary: {
                    grid
                }
            } else {
                VStack(spacing: 0) {
                    deck
                        .frame(height: 200)
                        .padding(.horizontal, 28)
                        .padding(.top, 8)
                        .padding(.bottom, 36)
                    gestureHint
                    grid
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .coordinateSpace(.named(Self.space))
        .overlay(alignment: .topLeading) { topCard }
        .animation(.snappy, value: model.triageQueue.first?.id)
        .onChange(of: model.triageQueue.first?.id) { leaving = nil }
        .sensoryFeedback(trigger: hovered) { _, new in new == nil ? nil : .selection }
    }

    // MARK: Stack

    /// The cards behind the top one, peeking out below it. The top one is only a slot here.
    private var deck: some View {
        let queue = Array(model.triageQueue.prefix(3).enumerated())
        let lift = min(1, hypot(translation.width, translation.height) / 160)
        return ZStack {
            ForEach(queue.reversed(), id: \.element.id) { index, item in
                if index == 0 {
                    Color.clear
                        .contentShape(.rect)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { slot = $0 }
                        .gesture(dragGesture(for: item))
                        .accessibilityElement()
                        .accessibilityLabel(item.title)
                        .accessibilityHint("Nach unten auf einen Laden ziehen, zur Seite wischen für später")
                        .accessibilityAction(named: "Später") { model.triageSkip(item) }
                } else {
                    // The next card grows into place while the top one is lifted.
                    let step = CGFloat(index) - (index == 1 ? lift : 0)
                    TriageItemCard(item: item)
                        .scaleEffect(1 - step * 0.06, anchor: .bottom)
                        .offset(y: step * 14)
                        .opacity(index == 2 ? 0.6 : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
        }
    }

    /// How the stack works, until the first step of the session.
    @ViewBuilder
    private var gestureHint: some View {
        if model.triage?.history.isEmpty == true {
            Text("Auf einen Laden ziehen · zur Seite wischen für später")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .transition(.opacity)
        }
    }

    /// The top card, above grid and bar so it can travel onto any store.
    @ViewBuilder
    private var topCard: some View {
        if let item = model.triageQueue.first, item.id != leaving, slot != .zero {
            let down = min(1, max(0, translation.height) / (slot.height * 1.3))
            let scale = landingScale ?? (1 - 0.62 * down)
            let sideways = min(1, abs(translation.width) / 110) * (1 - down)
            TriageItemCard(item: item, hint: swipeHint(for: item, toRight: translation.width > 0), hintOpacity: sideways)
                .frame(width: slot.width, height: slot.height)
                .scaleEffect(scale, anchor: anchor)
                .rotationEffect(.degrees(translation.width / 22 * (1 - down)), anchor: .bottom)
                .opacity(landingScale == nil ? 1 : 0)
                .offset(x: slot.minX + translation.width, y: slot.minY + translation.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .id(item.id)
                .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
        }
    }

    private func swipeHint(for item: ShoppingItem, toRight: Bool) -> SwipeHint {
        if toRight, let suggestion = model.suggestion(for: item), let store = model.store(suggestion.storeID) {
            return SwipeHint(title: store.name, symbol: "arrow.right", color: store.readableColor, isTrailing: false)
        }
        return SwipeHint(title: String(localized: "Später"), symbol: toRight ? "arrow.turn.up.right" : "arrow.turn.up.left",
                         color: .secondary, isTrailing: !toRight)
    }

    private func dragGesture(for item: ShoppingItem) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    anchor = UnitPoint(x: (value.startLocation.x - slot.minX) / max(slot.width, 1),
                                       y: (value.startLocation.y - slot.minY) / max(slot.height, 1))
                }
                translation = value.translation
                hovered = value.location.y < bottomBarTop ? target(at: value.location) : nil
            }
            .onEnded { value in
                isDragging = false
                if let hovered {
                    land(item, on: hovered)
                    return
                }
                let dx = value.translation.width
                if abs(dx) > value.translation.height, abs(dx) > 110 || abs(value.predictedEndTranslation.width) > 240 {
                    swipe(item, toRight: dx > 0)
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: 0.3)) { translation = .zero }
                }
            }
    }

    private func target(at point: CGPoint) -> TriageTarget? {
        targets.first { $0.value.contains(point) }?.key
    }

    /// Shrinks the card into the tile, then assigns.
    private func land(_ item: ShoppingItem, on target: TriageTarget) {
        guard let frame = targets[target], !isFlying, item.id != leaving else { return }
        isFlying = true
        let scale: CGFloat = 0.14
        let pivot = CGPoint(x: slot.minX + anchor.x * slot.width, y: slot.minY + anchor.y * slot.height)
        let end = CGSize(width: frame.midX - pivot.x - (slot.midX - pivot.x) * scale,
                         height: frame.midY - pivot.y - (slot.midY - pivot.y) * scale)
        hovered = target
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.3)) {
            translation = end
            landingScale = scale
        } completion: {
            leave(item) { await assign(item, to: target) }
        }
    }

    private func swipe(_ item: ShoppingItem, toRight: Bool) {
        guard !isFlying, item.id != leaving else { return }
        isFlying = true
        let distance = (slot.width + 240) * (toRight ? 1 : -1)
        withAnimation(.smooth(duration: 0.25)) {
            translation = CGSize(width: distance, height: translation.height + 60)
        } completion: {
            leave(item) {
                if toRight { await model.triageAcceptSuggestion(for: item) } else { model.triageSkip(item) }
            }
        }
    }

    private func leave(_ item: ShoppingItem, _ action: @escaping @MainActor () async -> Void) {
        leaving = item.id
        isFlying = false
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            translation = .zero
            landingScale = nil
            hovered = nil
            anchor = .center
        }
        Task {
            await action()
            if leaving == item.id { leaving = nil }
        }
    }

    private func assign(_ item: ShoppingItem, to target: TriageTarget) async {
        switch target {
        case .store(let id):
            if let store = model.store(id) { await model.triageAssign(item, to: store) }
        case .new(let key):
            if let entry = model.catalog?.entry(forKey: key) { await model.triageAssign(item, toNew: entry) }
        }
    }

    /// Tap on a tile: the card flies there from its resting place.
    private func send(to target: TriageTarget) {
        guard let item = model.triageQueue.first, !isDragging else { return }
        anchor = .center
        land(item, on: target)
    }

    // MARK: Stores

    private var grid: some View {
        let item = model.triageQueue.first
        let suggestion = item.flatMap(model.suggestion(for:))
        let prices = item.flatMap(model.priceHint(for:))
        let fillers = item.map(fillers(for:)) ?? []
        return ScrollView {
            VStack(spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileMinimum, maximum: 140), spacing: Self.tileSpacing)],
                          spacing: Self.tileSpacing) {
                    ForEach(model.sortedStores) { store in
                        ownTile(store, suggestion: suggestion?.storeID == store.id ? suggestion : nil, prices: prices)
                    }
                    ForEach(fillers) { filler in
                        fillerTile(filler)
                    }
                    Button {
                        showsAddStore = true
                    } label: {
                        AddStoreTile(fill: Color(.secondarySystemGroupedBackground))
                    }
                    .buttonStyle(.plain)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    columns = max(1, Int((width + Self.tileSpacing) / (Self.tileMinimum + Self.tileSpacing)))
                }
                if prices != nil || fillers.contains(where: { $0.price != nil }) {
                    OpenPricesAttribution()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .scrollDisabled(isDragging)
        .scrollIndicators(.hidden)
    }

    /// Enough chains to fill the last row; one more row when cheaper ones would not fit.
    private func fillers(for item: ShoppingItem) -> [TriageFiller] {
        let occupied = model.sortedStores.count + 1
        let remainder = (columns - occupied % columns) % columns
        let candidates = model.triageFillers(for: item, limit: remainder + columns)
        let cheaper = candidates.count(where: \.isCheaper)
        return Array(candidates.prefix(cheaper > remainder ? remainder + columns : remainder))
    }

    private func ownTile(_ store: Store, suggestion: StoreSuggestion?, prices: StorePriceHint?) -> some View {
        let target = TriageTarget.store(store.id)
        let isHovered = hovered == target
        let price = prices?.price(of: store.id)
        // A habit keeps its label; otherwise the tile shows the price (tag on the cheapest).
        let showsLabel = suggestion != nil && (suggestion?.source != .price || price == nil)
        return Button {
            send(to: target)
        } label: {
            StoreTile(
                store: store,
                caption: showsLabel ? suggestion?.label : price?.shortText,
                captionSymbol: showsLabel ? suggestion?.symbol : (prices?.isCheapest(store.id) == true ? "tag.fill" : nil),
                highlight: isHovered || suggestion != nil ? store.readableColor : nil,
                fill: Color(.secondarySystemGroupedBackground)
            )
        }
        .buttonStyle(.plain)
        .modifier(DropTarget(target: target, isHovered: isHovered, frames: $targets))
        .accessibilityHint(suggestion == nil ? "" : String(localized: "Vorschlag"))
        .accessibilityValue(price?.displayText ?? "")
    }

    private func fillerTile(_ filler: TriageFiller) -> some View {
        let target = TriageTarget.new(filler.id)
        let isHovered = hovered == target
        return Button {
            send(to: target)
        } label: {
            StoreTile(
                store: filler.store,
                caption: filler.price?.shortText,
                captionSymbol: filler.isCheaper ? "tag.fill" : nil,
                highlight: isHovered ? filler.store.readableColor : nil,
                fill: .clear
            )
            .overlay {
                if !isHovered {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .padding(7)
            }
        }
        .buttonStyle(.plain)
        .modifier(DropTarget(target: target, isHovered: isHovered, frames: $targets))
        .accessibilityLabel("\(filler.entry.name) hinzufügen")
        .accessibilityHint(filler.isCheaper ? String(localized: "Günstiger als deine Läden") : "")
        .accessibilityValue(filler.price?.displayText ?? "")
    }

    // MARK: Bottom

    private var bottomBar: some View {
        let count = model.triageSuggestions.count
        return VStack(spacing: 4) {
            LastStepLine()
            if count > 0 {
                Button {
                    Task { await model.triageAcceptAllSuggestions() }
                } label: {
                    Label(count == 1 ? "1 Vorschlag übernehmen" : "\(count) Vorschläge übernehmen", systemImage: "sparkles")
                        .font(.headline)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassEffect(.regular.tint(accentColor).interactive(), in: .capsule)
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 8)
        .animation(.snappy, value: count)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { bottomBarTop = $0 }
    }
}

// MARK: - Parts

enum TriageTarget: Hashable {
    case store(Store.ID)
    /// A catalog chain the user does not have yet.
    case new(String)
}

/// Reports a tile's frame for dropping and lifts it while the card hovers over it.
private struct DropTarget: ViewModifier {
    let target: TriageTarget
    let isHovered: Bool
    @Binding var frames: [TriageTarget: CGRect]

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.08 : 1)
            .animation(.snappy(duration: 0.2), value: isHovered)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(TriageCards.space)) } action: { frames[target] = $0 }
            .onDisappear { frames[target] = nil }
    }
}

struct SwipeHint {
    let title: String
    let symbol: String
    let color: Color
    /// Left swipe: the stamp sits on the right edge, away from the finger.
    let isTrailing: Bool
}

/// One item as a big card: name, quantity as in the list, note and category. No price here –
/// prices belong to the stores below.
struct TriageItemCard: View {
    let item: ShoppingItem
    var hint: SwipeHint?
    var hintOpacity: Double = 0
    @Environment(AppModel.self) private var model

    var body: some View {
        let parts = ItemTitleParts(item.title)
        let category = model.category(of: item)
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if let prefix = parts.prefix { QuantityTag(value: prefix, font: .title3.weight(.semibold)) }
                Text(parts.name)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                if let suffix = parts.suffix { QuantityTag(value: suffix, font: .title3.weight(.semibold)) }
            }
            if let notes = item.userNotes {
                Text(notes)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            Label(category.displayName, systemImage: category.symbol)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cardSurface()
        .overlay(alignment: hint?.isTrailing == true ? .topTrailing : .topLeading) {
            if let hint, hintOpacity > 0 {
                Label(hint.title, systemImage: hint.symbol)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(hint.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(hint.color, lineWidth: 2))
                    .rotationEffect(.degrees(hint.isTrailing ? 8 : -8))
                    .padding(18)
                    .opacity(hintOpacity)
            }
        }
    }
}
