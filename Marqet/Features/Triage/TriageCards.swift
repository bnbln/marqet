import MarqetCore
import SwiftUI

/// The card view of "Zuordnen" (KONZEPT §7.4), the default: a stack of items between the header
/// and the stores, which sit docked at the bottom above "Vorschläge übernehmen".
/// - Drag the top card down: it shrinks on the way and lands on the store it is dropped on.
/// - Swipe it left: later. Swipe it right: the suggested store (later without one).
/// - A tap on a store sends the card there as well (fast, and for VoiceOver).
/// The grid fills its last row with chains the user does not have yet – clearly cheaper ones
/// first, then usual stores for the kind of product. Dropping on one adds it.
///
/// Animation: every card of the stack is one view that keeps its identity while it moves up
/// (third → second → top). A card that leaves is handed to a separate flight layer at its exact
/// pose and finishes its way there, while the stack already steps forward below it. The model
/// learns about the step when the flight ends, so tiles and prices stay put while it flies.
struct TriageCards: View {
    @Binding var showsAddStore: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Resting frame of the top card; all cards are drawn in one layer relative to it.
    @State private var slot: CGRect = .zero
    @State private var targets: [TriageTarget: CGRect] = [:]
    @State private var bottomBarTop: CGFloat = .infinity
    @State private var containerSize: CGSize = .zero
    @State private var gridHeight: CGFloat = 0
    @State private var columns = 4

    /// Where the stores sit; the card shrinks as the finger gets close to them.
    @State private var storesFrame: CGRect = .zero

    // The finger on the top card.
    @State private var dragStart: CGPoint = .zero
    @State private var translation: CGSize = .zero
    /// Point of the card the finger holds: the card shrinks towards it.
    @State private var anchor: UnitPoint = .center
    @State private var isDragging = false
    @State private var hovered: TriageTarget?

    /// Cards on their way out, above the stack until their flight ends.
    @State private var departures: [Departure] = []
    /// Items whose card has left; out of the stack before the model catches up.
    @State private var gone: Set<ShoppingItem.ID> = []
    /// Bumps a tile when a card lands in it.
    @State private var landings: [TriageTarget: Int] = [:]
    @State private var landingFeedback = 0

    static let space = "triage"
    private static let tileMinimum: CGFloat = 84
    private static let tileSpacing: CGFloat = 10
    /// Width : height of a card – almost square, a little taller.
    private static let cardAspect: CGFloat = 1 / 1.12
    private static let stackDepth = 3

    /// The stack moving up one card.
    private var stepForward: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.78)
    }

    private var stack: [ShoppingItem] {
        model.triageQueue.filter { !gone.contains($0.id) }
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                // iPad and the open Duo: the stack on the left, the stores on the right.
                AdaptiveSplit {
                    VStack(spacing: 0) {
                        deckArea
                        gestureHint
                    }
                    .padding(.vertical, 20)
                } secondary: {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        stores
                    }
                }
            } else {
                VStack(spacing: 0) {
                    deckArea
                    gestureHint
                    stores
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .coordinateSpace(.named(Self.space))
        .overlay(alignment: .topLeading) { cardLayer }
        .animation(stepForward, value: stack.map(\.id))
        .onChange(of: model.triageQueue.map(\.id)) { _, ids in gone.formIntersection(ids) }
        .sensoryFeedback(trigger: hovered) { _, new in new == nil ? nil : .selection }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: landingFeedback)
    }

    // MARK: Stack

    /// Room for the stack between header and stores; only a slot for gestures, the cards are
    /// drawn in `cardLayer`.
    private var deckArea: some View {
        Color.clear
            .aspectRatio(Self.cardAspect, contentMode: .fit)
            .frame(maxWidth: 420)
            .overlay { gestureSlot }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { slot = $0 }
            .padding(.horizontal, 36)
            .padding(.top, 12)
            // The cards behind peek out below.
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var gestureSlot: some View {
        if let item = stack.first {
            Color.clear
                .contentShape(.rect)
                .gesture(dragGesture(for: item))
                .accessibilityElement()
                .accessibilityLabel(item.title)
                .accessibilityHint("Nach unten auf einen Laden ziehen, zur Seite wischen für später")
                .accessibilityAction(named: "Später") { model.triageSkip(item) }
        }
    }

    /// How the stack works, until the first step of the session. Fades but keeps its place, so
    /// the stack does not move after the first card.
    private var gestureHint: some View {
        Text("Auf einen Laden ziehen · zur Seite wischen für später")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .opacity(model.triage?.history.isEmpty == true ? 1 : 0)
            .animation(.easeOut(duration: 0.3), value: model.triage?.history.isEmpty)
            .accessibilityHidden(model.triage?.history.isEmpty != true)
    }

    /// Stack and departing cards, above grid and bar so a card can travel onto any store.
    private var cardLayer: some View {
        let cards = Array(stack.prefix(Self.stackDepth).enumerated())
        return ZStack {
            if slot != .zero {
                ForEach(cards, id: \.element.id) { index, item in
                    stackCard(item, index: index)
                }
                ForEach(departures) { departure in
                    DepartingCard(departure: departure, width: slot.width, onLanded: finish)
                        .zIndex(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // Pose of the top card while the finger holds it.

    private var finger: CGPoint {
        CGPoint(x: dragStart.x + translation.width, y: dragStart.y + translation.height)
    }

    /// 0 at the stack, 1 once the finger reaches the stores. Measured as distance, so it works
    /// with the stores below (iPhone) as well as beside the stack (iPad, Duo inside).
    private var approach: CGFloat {
        guard translation != .zero, storesFrame != .zero else { return 0 }
        let start = distance(from: dragStart, to: storesFrame)
        guard start > 1 else { return 1 }
        let t = min(1, max(0, 1 - distance(from: finger, to: storesFrame) / start))
        return t * t * (3 - 2 * t)
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
    }

    private var restPose: CardPose {
        CardPose(center: CGPoint(x: slot.midX, y: slot.midY), height: slot.height, scale: 1, rotation: 0, opacity: 1)
    }

    /// The point the finger grabbed stays under the finger. Close to the stores the card turns
    /// into a small square, smaller than a tile, showing just the name.
    private var livePose: CardPose {
        guard isDragging || translation != .zero, slot != .zero else { return restPose }
        let progress = approach
        let tileSide = targets.values.map(\.width).min() ?? 88
        let small = min(1, tileSide * 0.8 / max(slot.width, 1))
        let height = slot.height + (slot.width - slot.height) * progress
        let scale = 1 + (small - 1) * progress
        // Tilts like a card held at one point: grabbed high, it turns with the finger; grabbed
        // low, against it. Straightens out near the stores.
        let direction: Double = anchor.y < 0.6 ? 1 : -1
        return CardPose(
            center: CGPoint(x: finger.x - (anchor.x - 0.5) * slot.width * scale,
                            y: finger.y - (anchor.y - 0.5) * height * scale),
            height: height,
            scale: scale,
            rotation: Double(translation.width) / 18 * direction * Double(1 - progress),
            opacity: 1,
            compact: Double(progress)
        )
    }

    /// How far the next cards have moved up while the top one is lifted.
    private var lift: CGFloat {
        min(1, hypot(translation.width, translation.height) / 220)
    }

    private func stackCard(_ item: ShoppingItem, index: Int) -> some View {
        let isTop = index == 0
        let depth = isTop ? 0 : CGFloat(index) - lift
        let scale = 1 - depth * 0.055
        // Cards behind peek out below the top one, anchored at their bottom edge.
        let pose = isTop ? livePose : CardPose(
            center: CGPoint(x: slot.midX, y: slot.maxY + depth * 13 - slot.height * scale / 2),
            height: slot.height, scale: scale, rotation: 0, opacity: 1
        )
        let sideways = min(1, abs(translation.width) / 110) * (1 - approach)
        return TriageItemCard(
            item: item,
            hint: isTop ? swipeHint(for: item, toRight: translation.width > 0) : nil,
            hintOpacity: isTop ? sideways : 0,
            compact: pose.compact
        )
        .modifier(Posed(pose: pose, width: slot.width))
        .zIndex(Double(Self.stackDepth - index))
        // New cards rise from behind the stack; a leaving card is replaced by its flight at the
        // same pose, so it goes without a transition.
        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.88, anchor: .bottom)),
                                removal: .identity))
    }

    private func swipeHint(for item: ShoppingItem, toRight: Bool) -> SwipeHint {
        if toRight, let suggestion = model.suggestion(for: item), let store = model.store(suggestion.storeID) {
            return SwipeHint(title: store.name, symbol: "arrow.right", color: store.readableColor, isTrailing: false)
        }
        return SwipeHint(title: String(localized: "Später"), symbol: toRight ? "arrow.turn.up.right" : "arrow.turn.up.left",
                         color: .secondary, isTrailing: !toRight)
    }

    private func dragGesture(for item: ShoppingItem) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStart = value.startLocation
                    anchor = UnitPoint(x: (value.startLocation.x - slot.minX) / max(slot.width, 1),
                                       y: (value.startLocation.y - slot.minY) / max(slot.height, 1))
                }
                translation = value.translation
                hovered = value.location.y < bottomBarTop ? target(at: value.location) : nil
            }
            .onEnded { value in
                isDragging = false
                if let hovered, let frame = targets[hovered] {
                    land(item, on: hovered, frame: frame)
                    return
                }
                let dx = value.translation.width
                let flick = value.predictedEndTranslation.width
                if abs(dx) > value.translation.height, abs(dx) > 110 || abs(flick) > 260 {
                    swipe(item, toRight: (abs(flick) > abs(dx) ? flick : dx) > 0, velocity: value.predictedEndTranslation)
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) {
                        translation = .zero
                        hovered = nil
                    }
                }
            }
    }

    private func target(at point: CGPoint) -> TriageTarget? {
        targets.first { $0.value.contains(point) }?.key
    }

    // MARK: Leaving

    /// Shrinks the card into the tile, then assigns.
    private func land(_ item: ShoppingItem, on target: TriageTarget, frame: CGRect) {
        let pose = livePose
        // A small square, centered in the tile, fading on arrival.
        let end = CardPose(center: CGPoint(x: frame.midX, y: frame.midY), height: slot.width,
                           scale: min(pose.scale, frame.width * 0.6 / max(slot.width, 1)), rotation: 0, opacity: 0,
                           compact: 1)
        depart(item, to: end,
               flight: reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.32, dampingFraction: 0.86),
               duration: reduceMotion ? 0.18 : 0.32, landsIn: target) {
            await assign(item, to: target)
        }
    }

    /// Throws the card off screen in the direction of the swipe, keeping its momentum.
    private func swipe(_ item: ShoppingItem, toRight: Bool, velocity: CGSize) {
        var end = livePose
        let direction: CGFloat = toRight ? 1 : -1
        end.center.x += direction * (containerSize.width + slot.width)
        end.center.y += max(-120, min(120, (velocity.height - translation.height) * 0.4))
        end.rotation = Double(direction) * (anchor.y < 0.6 ? 24 : -24)
        depart(item, to: end, flight: .easeOut(duration: 0.32), duration: 0.32, landsIn: nil) {
            if toRight { await model.triageAcceptSuggestion(for: item) } else { model.triageSkip(item) }
        }
    }

    /// Tap on a tile: the card flies there from its resting place.
    private func send(to target: TriageTarget) {
        guard let item = stack.first, !isDragging, let frame = targets[target] else { return }
        anchor = .center
        land(item, on: target, frame: frame)
    }

    /// Hands the top card to the flight layer at its current pose; the stack steps forward at once.
    private func depart(_ item: ShoppingItem, to end: CardPose, flight: Animation, duration: Double,
                        landsIn target: TriageTarget?, action: @escaping @MainActor () async -> Void) {
        guard !gone.contains(item.id) else { return }
        departures.append(Departure(item: item, start: livePose, end: end, flight: flight,
                                    duration: duration, target: target, action: action))
        withAnimation(stepForward) {
            gone.insert(item.id)
            translation = .zero
            hovered = nil
        }
        anchor = .center
    }

    private func finish(_ departure: Departure) {
        departures.removeAll { $0.id == departure.id }
        if let target = departure.target {
            landings[target, default: 0] += 1
            landingFeedback += 1
        }
        Task {
            await departure.action()
            gone.remove(departure.item.id)
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

    // MARK: Stores

    /// Docked at the bottom; scrolls only when there are more stores than fit.
    private var stores: some View {
        let limit = sizeClass == .regular ? containerSize.height : max(220, containerSize.height * 0.48)
        return ScrollView {
            grid
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // Only grows during a round: an item with fewer tiles must not resize the stack.
                    gridHeight = max(gridHeight, height)
                }
                .frame(minHeight: min(gridHeight, limit), alignment: .bottom)
        }
        .frame(height: gridHeight == 0 ? nil : min(gridHeight, limit))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { storesFrame = $0 }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(isDragging)
        .scrollIndicators(.hidden)
    }

    private var grid: some View {
        // The card on top of the stack, even while the previous one is still in the air.
        let item = stack.first
        let suggestion = item.flatMap(model.suggestion(for:))
        let prices = item.flatMap(model.priceHint(for:))
        let fillers = item.map(fillers(for:)) ?? []
        return VStack(spacing: 12) {
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
            // Keeps its line while an item has no prices, so the grid does not jump.
            OpenPricesAttribution()
                .opacity(prices != nil || fillers.contains(where: { $0.price != nil }) ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        // Free room for the floating last-step pill above the button.
        .padding(.bottom, 48)
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
        .modifier(DropTarget(target: target, isHovered: isHovered, landings: landings[target, default: 0], frames: $targets))
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
        .modifier(DropTarget(target: target, isHovered: isHovered, landings: landings[target, default: 0], frames: $targets))
        .accessibilityLabel("\(filler.entry.name) hinzufügen")
        .accessibilityHint(filler.isCheaper ? String(localized: "Günstiger als deine Läden") : "")
        .accessibilityValue(filler.price?.displayText ?? "")
    }

    // MARK: Bottom

    private var bottomBar: some View {
        let count = model.triageSuggestions.count
        return VStack(spacing: 4) {
            if count > 0 {
                TriageWideButton(title: count == 1 ? String(localized: "1 Vorschlag übernehmen")
                                                   : String(localized: "\(count) Vorschläge übernehmen"),
                                 symbol: "sparkles") {
                    Task { await model.triageAcceptAllSuggestions() }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        // The last step floats above the button instead of taking room, so the stores never move.
        .overlay(alignment: .top) {
            LastStepLine()
                .alignmentGuide(.top) { $0[.bottom] }
                .allowsHitTesting(false)
        }
        .animation(.snappy, value: count)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { bottomBarTop = $0 }
    }
}

// MARK: - Flight

/// Where and how a card is drawn, in the triage coordinate space. Width stays the slot width;
/// the height morphs to a square on the way to the stores.
struct CardPose: Equatable {
    var center: CGPoint
    var height: CGFloat
    var scale: CGFloat
    var rotation: Double
    var opacity: Double
    /// 0 = the full card, 1 = just the name, for the small square over the stores.
    var compact: Double = 0
}

private struct Posed: ViewModifier {
    let pose: CardPose
    let width: CGFloat

    // The layout keeps its width and only scales, so no text ever wraps anew while it shrinks.
    func body(content: Content) -> some View {
        content
            .frame(width: width, height: pose.height)
            .scaleEffect(pose.scale)
            .rotationEffect(.degrees(pose.rotation))
            .position(pose.center)
    }
}

/// A card that has left the stack, from the pose it had to where it goes.
struct Departure: Identifiable {
    let id = UUID()
    let item: ShoppingItem
    let start: CardPose
    let end: CardPose
    let flight: Animation
    let duration: Double
    /// The tile it lands in; `nil` when swiped away.
    let target: TriageTarget?
    let action: @MainActor () async -> Void
}

/// Starts at the pose it took over from the stack and flies on once it is on screen – set in
/// the same update as its insertion, SwiftUI would draw the end pose right away.
private struct DepartingCard: View {
    let departure: Departure
    let width: CGFloat
    let onLanded: (Departure) -> Void
    @State private var isFlying = false
    @State private var isFaded = false

    var body: some View {
        let pose = isFlying ? departure.end : departure.start
        TriageItemCard(item: departure.item, compact: pose.compact)
            .modifier(Posed(pose: pose, width: width))
            // A landing card fades only at the very end, inside the tile.
            .opacity(isFaded ? departure.end.opacity : 1)
            .transition(.identity)
            .onAppear {
                withAnimation(departure.flight) {
                    isFlying = true
                } completion: {
                    onLanded(departure)
                }
                if departure.end.opacity < 1 {
                    withAnimation(.easeIn(duration: departure.duration * 0.35).delay(departure.duration * 0.6)) {
                        isFaded = true
                    }
                }
            }
    }
}

// MARK: - Parts

enum TriageTarget: Hashable {
    case store(Store.ID)
    /// A catalog chain the user does not have yet.
    case new(String)
}

/// Reports a tile's frame for dropping, lifts it while a card hovers over it and bumps it when
/// one lands.
private struct DropTarget: ViewModifier {
    let target: TriageTarget
    let isHovered: Bool
    let landings: Int
    @Binding var frames: [TriageTarget: CGRect]

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.08 : 1)
            .animation(.snappy(duration: 0.2), value: isHovered)
            .keyframeAnimator(initialValue: 1.0, trigger: landings) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(0.9, duration: 0.1, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
            }
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

/// The full-width button at the thumb, as everywhere else in the app.
struct TriageWideButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void
    @AppStorage(AppAccentPalette.storageKey) private var accentPaletteKey = AppAccentPalette.leaf.rawValue

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title).contentTransition(.numericText())
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .glassEffect(.regular.tint(AppAccentPalette(rawValue: accentPaletteKey)?.color ?? AppAccentPalette.leaf.color).interactive(),
                     in: .capsule)
        .padding(.horizontal, 20)
    }
}

/// One item as a big card: name, quantity as in the list, note and category. No price here –
/// prices belong to the stores below. On its way into a store the card is scaled down; it then
/// cross-fades to just the name in a large font, so the name stays readable on the small square.
/// Both layers keep their layout, so nothing reflows while the card shrinks.
struct TriageItemCard: View {
    let item: ShoppingItem
    var hint: SwipeHint?
    var hintOpacity: Double = 0
    var compact: Double = 0
    @Environment(AppModel.self) private var model

    var body: some View {
        let parts = ItemTitleParts(item.title)
        let category = model.category(of: item)
        ZStack {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    if let prefix = parts.prefix { QuantityTag(value: prefix, font: .title3.weight(.semibold)) }
                    Text(parts.name)
                        .font(.largeTitle.bold())
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                    if let suffix = parts.suffix { QuantityTag(value: suffix, font: .title3.weight(.semibold)) }
                }
                if let notes = item.userNotes {
                    Text(notes)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Label(category.displayName, systemImage: category.symbol)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .opacity(1 - min(1, compact / 0.4))

            // Scaled to the small square, this reads like body text.
            Text(parts.name)
                .font(.system(size: 96, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.2)
                .padding(28)
                .opacity(min(1, max(0, (compact - 0.4) / 0.3)))
        }
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
