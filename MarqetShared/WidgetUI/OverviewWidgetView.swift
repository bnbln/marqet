import AppIntents
import MarqetCore
import SwiftUI
import WidgetKit

/// "Überblick": all stores with open items – the pager as a widget (KONZEPT-WIDGETS §4.3).
struct OverviewWidgetView: View {
    let snapshot: WidgetSnapshot
    var order: OverviewOrder = .app
    var showsInbox = true
    let family: WidgetFamily

    /// Gray like the pager background; the mini cards sit on it like the store cards.
    static let background = Color(.systemGroupedBackground)

    var body: some View {
        Group {
            if snapshot.status != .ready {
                WidgetSetupPrompt(compact: family == .systemSmall || family.isAccessory)
            } else {
                switch family {
                case .systemSmall: SmallOverview(model: model)
                case .systemMedium: MiniPager(model: model, slots: 4)
                case .systemLarge: LargeOverview(model: model)
                case .systemExtraLarge: CardGrid(model: model, columns: 4, rows: 2, itemsPerCard: 5)
                case .accessoryCircular, .accessoryRectangular, .accessoryInline: AccessoryOverview(model: model, family: family)
                default:
                    if family.isExtraLargePortrait {
                        CardGrid(model: model, columns: 2, rows: 3, itemsPerCard: 5)
                    } else {
                        LargeOverview(model: model)
                    }
                }
            }
        }
        .widgetURL(model.link)
    }

    private var model: OverviewModel {
        OverviewModel(snapshot: snapshot, order: order, showsInbox: showsInbox)
    }
}

/// Stores in the configured order plus the numbers and where a tap goes.
struct OverviewModel {
    let snapshot: WidgetSnapshot
    let stores: [WidgetSnapshot.Page]
    let inbox: WidgetSnapshot.Page?

    init(snapshot: WidgetSnapshot, order: OverviewOrder, showsInbox: Bool) {
        self.snapshot = snapshot
        let active = snapshot.activeStorePages
        switch order {
        case .app:
            stores = active
        case .count:
            stores = active.enumerated().sorted { lhs, rhs in
                lhs.element.openCount == rhs.element.openCount ? lhs.offset < rhs.offset : lhs.element.openCount > rhs.element.openCount
            }.map(\.element)
        case .distance:
            stores = active.enumerated().sorted { lhs, rhs in
                switch (lhs.element.distanceMeters, rhs.element.distanceMeters) {
                case let (l?, r?) where l != r: l < r
                case (_?, nil): true
                case (nil, _?): false
                default: lhs.offset < rhs.offset
                }
            }.map(\.element)
        }
        inbox = showsInbox ? snapshot.inbox.flatMap { $0.openCount > 0 ? $0 : nil } : nil
    }

    var storeTotal: Int { stores.reduce(0) { $0 + $1.openCount } }
    var total: Int { storeTotal + (inbox?.openCount ?? 0) }

    /// Mini cards: inbox first (as in the pager), then the stores.
    var cards: [WidgetSnapshot.Page] { (inbox.map { [$0] } ?? []) + stores }

    /// The store the "Einkauf starten" button goes to: where the user is, else the running trip,
    /// else the first one.
    var nextStore: WidgetSnapshot.Page? {
        if let presence = snapshot.presence, let page = stores.first(where: { $0.store?.id == presence.storeID }) { return page }
        if let trip = snapshot.trip, let page = stores.first(where: { $0.store?.id == trip.storeID }) { return page }
        return stores.first
    }

    /// Where a tap outside a card or row goes: the one card that is meant, else Home – never
    /// the inbox just because it comes first.
    var link: URL {
        if stores.count == 1, let pageID = stores[0].pageID { return MarqetLink.page(pageID).url }
        if stores.isEmpty, inbox != nil { return MarqetLink.page(.unsorted).url }
        return MarqetLink.home.url
    }
}

/// The widget's header band in the Marqet accent color with the cart of the app icon, so the
/// widget reads as Marqet at a glance – like the store headers of the other widgets.
private struct OverviewHeader: View {
    enum Size { case small, medium, large }

    let model: OverviewModel
    var size: Size = .large

    var body: some View {
        WidgetCardHeader(
            page: WidgetSnapshot.Page(id: "overview", store: nil, state: nil, sections: []),
            title: String(localized: "Einkaufen"),
            systemImage: "cart.fill",
            tint: model.snapshot.accentColor,
            badgeSize: size == .small ? 22 : (size == .medium ? 26 : 30),
            height: height,
            trailing: size == .small ? .none : .count,
            count: model.total
        )
    }

    var height: CGFloat { Self.height(for: size) }

    static func height(for size: Size) -> CGFloat {
        switch size {
        case .small: 40
        case .medium: 44
        case .large: 50
        }
    }
}

// MARK: - Small

private struct SmallOverview: View {
    let model: OverviewModel

    var body: some View {
        VStack(spacing: 0) {
            OverviewHeader(model: model, size: .small)
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                // Store items only; the inbox has its own line below.
                Text(onlyInbox ? model.total : model.storeTotal, format: .number)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                ColorBar(stores: model.stores)
                    .frame(height: 8)
                    .padding(.top, 4)
                if let inbox = model.inbox, !onlyInbox {
                    Label("\(inbox.openCount)", systemImage: "tray.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .labelStyle(CompactLabelStyle())
                        .padding(.top, 8)
                        .accessibilityLabel("\(inbox.openCount) in der Inbox")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
    }

    private var onlyInbox: Bool { model.stores.isEmpty && model.inbox != nil }
}

/// Segments in the store colors, each as wide as its share of the open items.
private struct ColorBar: View {
    let stores: [WidgetSnapshot.Page]
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        GeometryReader { proxy in
            let total = max(stores.reduce(0) { $0 + $1.openCount }, 1)
            let spacing: CGFloat = 2
            let available = proxy.size.width - spacing * CGFloat(max(stores.count - 1, 0))
            HStack(spacing: spacing) {
                if stores.isEmpty {
                    Capsule().fill(Color.primary.opacity(0.1))
                }
                ForEach(stores) { page in
                    Rectangle()
                        .fill(renderingMode == .fullColor ? (page.store?.color ?? .gray) : Color.primary.opacity(0.6))
                        .frame(width: max(available * CGFloat(page.openCount) / CGFloat(total), 3))
                }
            }
            .clipShape(.capsule)
            .widgetAccentable()
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Mini cards

/// A store card in miniature: colored head, count, name, first item.
private struct MiniCard: View {
    let page: WidgetSnapshot.Page
    var itemCount = 0
    var fillsHeight = true
    var compact = false

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var tint: Color {
        guard renderingMode == .fullColor else { return .primary }
        return page.store?.readableColor ?? .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(page.openCount, format: .number)
                        .font(.system(size: compact ? 20 : (itemCount > 0 ? 22 : 26), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .widgetAccentable()
                    if itemCount > 0 {
                        Text(page.store?.name ?? String(localized: "Inbox"))
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                if itemCount == 0 {
                    Text(page.store?.name ?? String(localized: "Inbox"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if !compact, let first = page.items.first {
                        Text(first.title)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    ForEach(page.items.prefix(itemCount)) { item in
                        WidgetItemRow(item: item, tint: tint, fontSize: 13)
                            .frame(height: 23)
                    }
                    MoreItemsLabel(count: page.openCount - itemCount, fontSize: 11)
                        .padding(.leading, 29)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)
            .padding(.bottom, 7)
            if fillsHeight { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
    }

    private var head: some View {
        HStack(spacing: 5) {
            WidgetBadge(store: page.store, size: 20)
            Spacer(minLength: 0)
            if let meters = page.distanceMeters {
                Text(WidgetFormat.distance(meters))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(renderingMode == .fullColor ? (page.store?.foregroundOnColor ?? .white) : .primary)
        .padding(.horizontal, 7)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background {
            if renderingMode == .fullColor {
                if let store = page.store {
                    store.headerGradient
                } else {
                    LinearGradient(colors: [Color(.systemGray), Color(.systemGray).opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            } else {
                Color.primary.opacity(0.08)
            }
        }
    }
}

/// Medium: up to four mini cards side by side, like the pager.
private struct MiniPager: View {
    let model: OverviewModel
    let slots: Int

    var body: some View {
        let cards = model.cards
        VStack(spacing: 0) {
            OverviewHeader(model: model, size: .medium)
            if cards.isEmpty {
                AllDoneView(model: model)
            } else {
                let overflow = cards.count > slots
                let shown = overflow ? Array(cards.prefix(slots - 1)) : cards
                HStack(spacing: 8) {
                    ForEach(shown) { page in
                        if let pageID = page.pageID {
                            Link(destination: MarqetLink.page(pageID).url) {
                                MiniCard(page: page, compact: true)
                            }
                        }
                    }
                    if overflow {
                        // Several stores behind one tile: Home, where all cards are.
                        Link(destination: MarqetLink.home.url) {
                            MoreStoresTile(pages: Array(cards.dropFirst(slots - 1)))
                        }
                    } else {
                        ForEach(0..<(slots - shown.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .padding(10)
            }
        }
    }
}

private struct MoreStoresTile: View {
    let pages: [WidgetSnapshot.Page]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: -6) {
                ForEach(pages.prefix(3)) { page in
                    WidgetBadge(store: page.store, size: 22)
                        .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
                }
            }
            Text("+\(pages.count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pages.count == 1 ? "1 weiterer Laden" : "\(pages.count) weitere Läden")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
    }
}

private struct AllDoneView: View {
    let model: OverviewModel

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30))
                .foregroundStyle(model.snapshot.accentColor)
                .widgetAccentable()
            Text("Alles erledigt")
                .font(.system(size: 15, weight: .semibold))
            Link(destination: MarqetLink.compose(.unsorted).url) {
                Label("Eintrag hinzufügen", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.snapshot.accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Large

private struct LargeOverview: View {
    let model: OverviewModel

    /// Space around the list and the button – the button keeps clear of the rounded corners.
    private static let inset: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            // Header, insets, list padding, the button with its gap and the overflow label.
            let reserved = OverviewHeader.height(for: .large) + 12 + 8 + 16 + 44 + Self.inset + 18
            let rowBudget = max(1, Int((geometry.size.height - reserved) / 41))
            let storeLimit = max(0, min(5, rowBudget - (model.inbox == nil ? 0 : 1)))
            let rows = Array(model.stores.prefix(storeLimit))
            VStack(spacing: 0) {
                OverviewHeader(model: model, size: .large)
                if model.cards.isEmpty {
                    AllDoneView(model: model)
                } else {
                    VStack(spacing: 0) {
                        ForEach(rows) { page in
                            StoreRow(page: page)
                            if page.id != rows.last?.id || model.inbox != nil {
                                Divider().padding(.leading, 44)
                            }
                        }
                        if let inbox = model.inbox {
                            InboxRow(page: inbox)
                        }
                        if model.stores.count > rows.count {
                            Link(destination: MarqetLink.home.url) {
                                Text("+ \(model.stores.count - rows.count) weitere Läden")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 44)
                                    .frame(height: 18)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    Spacer(minLength: 16)
                    TripButton(model: model)
                        .padding(.horizontal, Self.inset)
                        .padding(.bottom, Self.inset)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }
}

private struct StoreRow: View {
    let page: WidgetSnapshot.Page
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if let store = page.store, let pageID = page.pageID {
            Link(destination: MarqetLink.page(pageID).url) {
                HStack(spacing: 10) {
                    WidgetBadge(store: store, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.name)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(page.items.prefix(4).map(\.title).joined(separator: ", "))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(page.openCount, format: .number)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(renderingMode == .fullColor ? store.foregroundOnColor : .primary)
                            .padding(.horizontal, 8)
                            .frame(minWidth: 26, minHeight: 20)
                            .background(renderingMode == .fullColor ? store.color : Color.primary.opacity(0.15), in: .capsule)
                            .widgetAccentable()
                        if let meters = page.distanceMeters {
                            Text(WidgetFormat.distance(meters))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 40)
            }
            .foregroundStyle(.primary)
        }
    }
}

private struct InboxRow: View {
    let page: WidgetSnapshot.Page

    var body: some View {
        HStack(spacing: 10) {
            // Badge, name and count open the inbox; only the button starts triage.
            Link(destination: MarqetLink.page(.unsorted).url) {
                HStack(spacing: 10) {
                    WidgetBadge(store: nil, size: 30)
                        .background(Color(.systemGray), in: .circle)
                        .foregroundStyle(.white)
                    Text("Inbox")
                        .font(.system(size: 15, weight: .semibold))
                    Text(page.openCount, format: .number)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                }
                .contentShape(.rect)
            }
            Link(destination: MarqetLink.triage.url) {
                Text("Zuordnen")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Color.primary.opacity(0.08), in: .capsule)
            }
        }
        .frame(height: 40)
        .foregroundStyle(.primary)
    }
}

/// "Einkauf bei Aldi starten" – or the running trip with "Beenden".
private struct TripButton: View {
    let model: OverviewModel
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if let trip = model.snapshot.trip, let store = model.snapshot.store(trip.storeID) {
            HStack(spacing: 10) {
                WidgetBadge(store: store, size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Einkauf bei \(store.name)")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text("\(trip.doneItemIDs.count) erledigt · läuft")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button(intent: EndTripIntent()) {
                    Text("Beenden")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Color.primary.opacity(0.08), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        } else if let page = model.nextStore, let store = page.store {
            Button(intent: StartTripIntent(storeID: store.id)) {
                HStack(spacing: 8) {
                    Image(systemName: "cart.fill")
                    Text("Einkauf bei \(store.name) starten")
                        .lineLimit(1)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(renderingMode == .fullColor ? store.foregroundOnColor : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(renderingMode == .fullColor ? AnyShapeStyle(store.headerGradient) : AnyShapeStyle(Color.primary.opacity(0.12)),
                            in: .capsule)
                .widgetAccentable()
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Extra large

/// iOS 27 extra large (portrait) and iPad: mini cards with checkable items – the whole trip on
/// one Home Screen page.
private struct CardGrid: View {
    let model: OverviewModel
    let columns: Int
    let rows: Int
    let itemsPerCard: Int

    var body: some View {
        GeometryReader { geometry in
            let available = geometry.size.height - OverviewHeader.height(for: .large) - 32 - 44 - 16
            let cardHeight = max(1, (available - CGFloat(rows - 1) * 10) / CGFloat(rows))
            let visibleItems = min(itemsPerCard, max(0, Int((cardHeight - 30 - 27 - 12 - 16) / 23)))
            VStack(spacing: 0) {
                OverviewHeader(model: model, size: .large)
                let cards = Array(model.cards.prefix(columns * rows))
                if cards.isEmpty {
                    AllDoneView(model: model)
                } else {
                    VStack(spacing: 0) {
                        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                            ForEach(0..<rows, id: \.self) { row in
                                GridRow {
                                    ForEach(0..<columns, id: \.self) { column in
                                        let index = row * columns + column
                                        if index < cards.count {
                                            MiniCard(page: cards[index], itemCount: visibleItems, compact: cardHeight < 105)
                                                .frame(height: cardHeight)
                                        } else {
                                            Color.clear.frame(height: cardHeight)
                                        }
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 16)
                        TripButton(model: model)
                    }
                    .padding(16)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }
}

// MARK: - Lock Screen

private struct AccessoryOverview: View {
    let model: OverviewModel
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            if let first = model.stores.first, let name = first.store?.name {
                Label("\(model.total) offen · \(name) \(first.openCount)", systemImage: "cart")
            } else {
                Label("Alles erledigt", systemImage: "cart")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(model.total, format: .number)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .widgetAccentable()
                }
            }
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text(model.stores.count == 1 ? "\(model.total) offen" : "\(model.total) offen · \(model.stores.count) Läden")
                    .font(.headline)
                    .widgetAccentable()
                Text(model.stores.prefix(3).compactMap { page in page.store.map { "\($0.name) \(page.openCount)" } }.joined(separator: " · "))
                    .font(.caption)
                    .lineLimit(2)
                if let inbox = model.inbox {
                    Text("Inbox \(inbox.openCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
