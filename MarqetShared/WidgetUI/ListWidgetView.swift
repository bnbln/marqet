import AppIntents
import MarqetCore
import SwiftUI
import WidgetKit

/// "Liste": one card of the app as a widget – a store, the inbox, the next store or recently
/// completed items (KONZEPT-WIDGETS §4.2).
struct ListWidgetView: View {
    let snapshot: WidgetSnapshot
    let list: ShoppingListEntity.Kind
    var showsSections = true
    let family: WidgetFamily

    /// The card surface, as in the app.
    static let background = Color(.secondarySystemGroupedBackground)

    var body: some View {
        Group {
            if snapshot.status != .ready {
                WidgetSetupPrompt(compact: family == .systemSmall || family.isAccessory)
            } else if list == .completed {
                CompletedListView(snapshot: snapshot, family: family)
            } else if let page {
                if family.isAccessory {
                    AccessoryListView(page: page, trip: snapshot.trip, family: family)
                } else {
                    StoreListView(page: page, snapshot: snapshot, showsSections: showsSections, family: family)
                }
            } else {
                WidgetSetupPrompt(compact: true)
            }
        }
        .widgetURL(url)
    }

    private var page: WidgetSnapshot.Page? {
        switch list {
        case .automatic: snapshot.automaticPage
        case .inbox: snapshot.inbox
        case .store(let id): snapshot.page(forStore: id)
        case .completed: nil
        }
    }

    private var url: URL? {
        if list == .completed { return MarqetLink.completed.url }
        return page?.pageID.map { MarqetLink.page($0).url }
    }
}

// MARK: - Home Screen

private struct StoreListView: View {
    let page: WidgetSnapshot.Page
    let snapshot: WidgetSnapshot
    let showsSections: Bool
    let family: WidgetFamily

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var tint: Color {
        guard renderingMode == .fullColor else { return .primary }
        return page.store?.readableColor ?? .secondary
    }

    private var tripHere: ShoppingTrip? {
        guard let trip = snapshot.trip, trip.storeID == page.store?.id else { return nil }
        return trip
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if page.openCount == 0 {
                WidgetEmptyState(page: page, tint: tint, compact: family == .systemSmall)
                    .padding(.horizontal, 12)
            } else {
                switch family {
                case .systemSmall: small
                case .systemMedium: medium
                case .systemExtraLarge: grid(columns: 3, perColumn: 10)
                default:
                    if family.isExtraLargePortrait {
                        tall(lines: 18, footerCard: true)
                    } else {
                        tall(lines: 12, footerCard: false)
                    }
                }
            }
            if family != .systemSmall, family != .systemMedium {
                footer
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        switch family {
        case .systemSmall:
            WidgetCardHeader(page: page, badgeSize: 22, height: 40, trailing: .count)
        case .systemMedium:
            WidgetCardHeader(page: page, subtitle: subtitle, badgeSize: 26, height: 50, trailing: .add)
        default:
            WidgetCardHeader(page: page, subtitle: subtitle, badgeSize: 30, height: 54, trailing: .add)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let store = page.store, snapshot.presence?.storeID == store.id {
            // The list that matters right now (KONZEPT-WIDGETS §13).
            parts.append(String(localized: "Du bist hier"))
            parts.append(WidgetFormat.open(page.openCount))
        } else if let tripHere {
            parts.append(String(localized: "Einkauf läuft · \(tripHere.doneItemIDs.count) erledigt"))
        } else if page.isInbox {
            parts.append(page.openCount == 0 ? String(localized: "Alles sortiert") : String(localized: "\(page.openCount) zum Zuordnen"))
        } else {
            parts.append(WidgetFormat.open(page.openCount))
        }
        if let distance = page.distanceMeters { parts.append(WidgetFormat.distance(distance)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Sizes

    private var small: some View {
        let items = page.items
        let shown = items.count > 4 ? 3 : min(items.count, 4)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(items.prefix(shown)) { item in
                row(item, fontSize: 13).frame(height: 25)
            }
            MoreItemsLabel(count: items.count - shown, fontSize: 11)
                .padding(.leading, 31)
                .padding(.top, 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Two columns of three; with more items the last slot says how many are left. The inbox and
    /// short lists keep one column – suggestion chips need the width.
    @ViewBuilder
    private var medium: some View {
        if page.isInbox || page.items.count <= 3 {
            mediumSingleColumn
        } else {
            mediumTwoColumns
        }
    }

    private var mediumSingleColumn: some View {
        let items = page.items
        let shown = min(items.count, 3)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(items.prefix(shown)) { item in row(item, fontSize: 14).frame(height: items.count > 3 ? 32 : 36) }
            if items.count > shown {
                MoreItemsLabel(count: items.count - shown)
                    .frame(height: 20)
                    .padding(.leading, 32)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var mediumTwoColumns: some View {
        let items = page.items
        let shown = items.count > 6 ? 5 : items.count
        let visible = Array(items.prefix(shown))
        let left = Array(visible.prefix(3))
        let right = Array(visible.dropFirst(3))
        return HStack(alignment: .top, spacing: 10) {
            column(left)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(right) { item in row(item, fontSize: 14).frame(height: 36) }
                if items.count > shown {
                    MoreItemsLabel(count: items.count - shown)
                        .frame(height: 36)
                        .padding(.leading, 32)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func column(_ items: [WidgetSnapshot.Item]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in row(item, fontSize: 14).frame(height: 36) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tall(lines limit: Int, footerCard: Bool) -> some View {
        let (lines, hidden) = WidgetLine.lines(of: page, showsSections: showsSections, limit: limit)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line($0, fontSize: 15, height: 25) }
            MoreItemsLabel(count: hidden)
                .padding(.leading, 33)
                .padding(.top, 2)
            Spacer(minLength: 0)
            if footerCard, let card = page.store.flatMap({ snapshot.loyaltyCards(for: $0.id).first }) {
                LoyaltyStrip(card: card)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func grid(columns count: Int, perColumn: Int) -> some View {
        let (lines, hidden) = WidgetLine.lines(of: page, showsSections: showsSections, limit: count * perColumn)
        let columns = WidgetLine.columns(lines, count: count, perColumn: perColumn)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(columns.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(columns[index]) { line($0, fontSize: 15, height: 25) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            MoreItemsLabel(count: hidden)
                .padding(.leading, 33)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func line(_ line: WidgetLine, fontSize: CGFloat, height: CGFloat) -> some View {
        switch line {
        case .header(let category):
            WidgetSectionHeader(category: category, tint: tint)
                .frame(height: height - 3, alignment: .bottom)
                .padding(.leading, 4)
        case .item(let item):
            row(item, fontSize: fontSize).frame(height: height)
        }
    }

    private func row(_ item: WidgetSnapshot.Item, fontSize: CGFloat) -> some View {
        WidgetItemRow(
            item: item,
            tint: tint,
            fontSize: fontSize,
            showsNote: family != .systemSmall,
            accessory: page.isInbox && family != .systemSmall ? .suggestion : .none
        )
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            if page.isInbox {
                if page.openCount > 0 {
                    Link(destination: MarqetLink.triage.url) {
                        Label("Läden zuordnen", systemImage: "arrow.triangle.branch")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Color.primary.opacity(0.08), in: .capsule)
                    }
                    .foregroundStyle(.primary)
                }
            } else if let store = page.store {
                if tripHere != nil {
                    Button(intent: EndTripIntent()) {
                        Label("Einkauf beenden", systemImage: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Color.primary.opacity(0.08), in: .capsule)
                    }
                    .buttonStyle(.plain)
                } else if page.openCount > 0 {
                    Button(intent: StartTripIntent(storeID: store.id)) {
                        Label("Einkauf starten", systemImage: "cart.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(renderingMode == .fullColor ? store.foregroundOnColor : .primary)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(renderingMode == .fullColor ? AnyShapeStyle(store.headerGradient) : AnyShapeStyle(Color.primary.opacity(0.12)), in: .capsule)
                            .widgetAccentable()
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            if let pageID = page.pageID {
                Link(destination: MarqetLink.compose(pageID).url) {
                    Label("Hinzufügen", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 4)
    }
}

/// The store's customer card at the bottom of the tall widget – the list ends at the checkout.
private struct LoyaltyStrip: View {
    let card: LoyaltyCard

    var body: some View {
        Link(destination: MarqetLink.loyaltyCard(card.id).url) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(card.name, systemImage: "wallet.pass.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("An der Kasse zeigen")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                WidgetBarcode(payload: card.payload, symbology: card.symbology)
                    .frame(width: 118, height: 38)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.white, in: .rect(cornerRadius: 6, style: .continuous))
                    .privacySensitive()
            }
            .padding(10)
            .background(Color(hex: card.colorHex).opacity(0.14), in: .rect(cornerRadius: 14, style: .continuous))
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Completed

private struct CompletedListView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var tint: Color { renderingMode == .fullColor ? snapshot.accentColor : .primary }

    private var limit: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 3
        case .systemExtraLarge: 10
        default: family.isExtraLargePortrait ? 18 : 11
        }
    }

    var body: some View {
        if family.isAccessory {
            AccessoryCompletedView(snapshot: snapshot, family: family)
        } else {
            VStack(spacing: 0) {
                WidgetCardHeader(
                    page: WidgetSnapshot.Page(id: "completed", store: nil, state: nil, sections: []),
                    title: String(localized: "Zuletzt erledigt"),
                    subtitle: family == .systemSmall ? nil : String(localized: "Nochmal kaufen mit ↺"),
                    systemImage: "checkmark",
                    tint: snapshot.accentColor,
                    badgeSize: family == .systemSmall ? 22 : 26,
                    height: family == .systemSmall ? 40 : 46,
                    trailing: .none
                )
                if snapshot.recentlyCompleted.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 26))
                            .foregroundStyle(tint)
                        Text("In den letzten 7 Tagen nichts erledigt.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(snapshot.recentlyCompleted.prefix(limit)) { item in
                            WidgetCompletedRow(item: item, tint: tint, fontSize: family == .systemSmall ? 13 : 14)
                                .frame(height: family == .systemSmall ? 25 : 27)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                }
            }
        }
    }
}

// MARK: - Lock Screen

private struct AccessoryListView: View {
    let page: WidgetSnapshot.Page
    let trip: ShoppingTrip?
    let family: WidgetFamily

    private var name: String { page.store?.name ?? String(localized: "Inbox") }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryInline:
            Label("\(name): \(WidgetFormat.open(page.openCount))", systemImage: page.isInbox ? "tray" : "cart")
        default:
            rectangular
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .widgetAccentable()
                Spacer(minLength: 0)
                if page.openCount > 0 {
                    Text(page.openCount, format: .number)
                        .font(.headline.monospacedDigit())
                }
            }
            if page.openCount == 0 {
                Text(page.isInbox ? "Alles sortiert" : "Alles erledigt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(page.items.prefix(2)) { item in
                Text("○ \(item.title)")
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var circular: some View {
        if let trip, trip.storeID == page.store?.id {
            let done = trip.doneItemIDs.count
            let total = done + page.openCount
            Gauge(value: Double(done), in: 0...Double(max(total, 1))) {
                Image(systemName: "cart")
            } currentValueLabel: {
                Text(page.openCount, format: .number)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    Text(monogram)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(page.openCount, format: .number)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .widgetAccentable()
                }
                .padding(6)
            }
        }
    }

    private var monogram: String {
        guard let store = page.store else { return String(localized: "Inbox") }
        if case .monogram(let text) = store.symbol { return text }
        return String(store.name.prefix(4))
    }
}

private struct AccessoryCompletedView: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(snapshot.recentlyCompleted.count) erledigt", systemImage: "checkmark.circle")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text(snapshot.recentlyCompleted.count, format: .number)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
            }
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text("Zuletzt erledigt")
                    .font(.headline)
                    .widgetAccentable()
                ForEach(snapshot.recentlyCompleted.prefix(2)) { item in
                    Text("✓ \(item.title)")
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
