import AppIntents
import MarqetCore
import SwiftUI
import WidgetKit

// Building blocks of every Marqet widget: the card's colored header, rows with a check circle,
// badges that survive the tinted and clear Home Screen (KONZEPT-WIDGETS §4.6).

extension WidgetSnapshot {
    var accentColor: Color { Color(hex: accentHex) }
}

extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
    }

    /// iOS 27: the 4 × 6 widget that fills a Home Screen page (KONZEPT-WIDGETS §1.1).
    var isExtraLargePortrait: Bool {
        if #available(iOS 27.0, *) { return self == .systemExtraLargePortrait }
        return false
    }

    /// Families of Home Screen widgets that grow with the content.
    static var systemFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        if #available(iOS 27.0, *) { families.append(.systemExtraLargePortrait) }
        return families
    }
}

enum WidgetFormat {
    /// "650 m" below a kilometre, "1,2 km" above – like the store cards.
    static func distance(_ meters: Double) -> String {
        let rounded = meters < 1_000 ? (meters / 10).rounded() * 10 : meters
        return Measurement(value: rounded, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road,
                                    numberFormatStyle: .number.precision(.fractionLength(meters < 1_000 ? 0...0 : 0...1))))
            // "550 m" never breaks between number and unit.
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    static func open(_ count: Int) -> String {
        count == 0 ? String(localized: "leer") : String(localized: "\(count) offen")
    }

    /// ISO calendar week, printed on brochure covers ("KW 40").
    static var calendarWeek: Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = .current
        return calendar.component(.weekOfYear, from: .now)
    }
}

// MARK: - Colors

/// A store color that stays visible on black – the Dynamic Island and dark accessory backgrounds.
extension Store {
    var colorOnDark: Color {
        let base = RGBColor(hex: colorHex) ?? RGBColor(red: 0.557, green: 0.557, blue: 0.576)
        let adjusted = base.adjusted(forContrast: 3.2, on: .black)
        return Color(.sRGB, red: adjusted.red, green: adjusted.green, blue: adjusted.blue)
    }

    var headerGradient: LinearGradient {
        LinearGradient(colors: [color, color.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Badge

/// The store badge; on the tinted or clear Home Screen a one-color monogram, because logos
/// would turn into gray blobs.
struct WidgetBadge: View {
    let store: Store?
    var size: CGFloat = 26
    /// Symbol for pages without a store (inbox, completed).
    var systemImage = "tray.fill"

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if let store, renderingMode == .fullColor {
            StoreBadge(store: store, size: size)
        } else {
            ZStack {
                Circle().fill(.white.opacity(renderingMode == .fullColor ? 0.22 : 0.18))
                if let store {
                    Text(monogram(of: store))
                        .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .padding(size * 0.12)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: size * 0.44, weight: .semibold))
                }
            }
            .frame(width: size, height: size)
            .widgetAccentable()
            .accessibilityHidden(true)
        }
    }

    private func monogram(of store: Store) -> String {
        if case .monogram(let text) = store.symbol { return text }
        return String(store.name.prefix(1))
    }
}

// MARK: - Header

/// The card's colored header, like `StoreCardHeader` in the app.
struct WidgetCardHeader: View {
    enum Trailing {
        case none
        case count
        /// "+" opens the composer on this card.
        case add
    }

    let page: WidgetSnapshot.Page
    var title: String? = nil
    var subtitle: String? = nil
    var systemImage = "tray.fill"
    var tint: Color? = nil
    var badgeSize: CGFloat = 26
    var height: CGFloat = 46
    var trailing: Trailing = .count

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var name: String { title ?? page.store?.name ?? String(localized: "Inbox") }
    private var foreground: Color {
        renderingMode == .fullColor ? (page.store?.foregroundOnColor ?? .white) : .primary
    }

    var body: some View {
        HStack(spacing: 10) {
            WidgetBadge(store: page.store, size: badgeSize, systemImage: systemImage)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: badgeSize > 26 ? 17 : 15, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .widgetAccentable()
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.85)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            switch trailing {
            case .none:
                EmptyView()
            case .count:
                if page.openCount > 0 {
                    Text(page.openCount, format: .number)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .widgetAccentable()
                }
            case .add:
                if let pageID = page.pageID {
                    Link(destination: MarqetLink.compose(pageID).url) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(renderingMode == .fullColor ? 0.22 : 0.14), in: .circle)
                    }
                    .accessibilityLabel("Eintrag hinzufügen")
                }
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 16)
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if renderingMode == .fullColor {
                if let store = page.store {
                    store.headerGradient
                } else {
                    let base = tint ?? Color(.systemGray)
                    LinearGradient(colors: [base, base.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            } else {
                Color.primary.opacity(0.08)
            }
        }
    }
}

// MARK: - Rows

/// One item with its check circle. The circle is its own button, so the rest of the row can
/// open the card.
struct WidgetItemRow: View {
    enum Accessory {
        case none
        /// Learned store for inbox items: tap assigns.
        case suggestion
    }

    let item: WidgetSnapshot.Item
    let tint: Color
    var fontSize: CGFloat = 14
    var showsNote = false
    var accessory: Accessory = .none

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: CheckItemIntent(itemID: item.id)) {
                Image(systemName: "circle")
                    .font(.system(size: fontSize + 4, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(width: fontSize + 10, height: fontSize + 10)
                    .contentShape(.rect)
                    .widgetAccentable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.title) abhaken")

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(item.title)
                    .font(.system(size: fontSize))
                    .lineLimit(1)
                    .layoutPriority(1)
                if showsNote, let note = item.note {
                    Text(note)
                        .font(.system(size: fontSize - 2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }
            Spacer(minLength: 0)
            if accessory == .suggestion, let suggestion = item.suggestion {
                SuggestionChip(itemID: item.id, suggestion: suggestion)
            }
        }
        .invalidatableContent()
    }
}

/// "→ Rewe": the learned store for an inbox item (KONZEPT #16, free).
struct SuggestionChip: View {
    let itemID: String
    let suggestion: WidgetSnapshot.Suggestion

    var body: some View {
        let color = Color(hex: suggestion.colorHex)
        Button(intent: AssignItemIntent(itemID: itemID, storeID: suggestion.storeID)) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                Text(suggestion.storeName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: .capsule)
            .widgetAccentable()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zu \(suggestion.storeName) zuordnen")
    }
}

/// A checked item in "Zuletzt erledigt" with "Nochmal kaufen".
struct WidgetCompletedRow: View {
    let item: WidgetSnapshot.Item
    let tint: Color
    var fontSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: fontSize + 4))
                .foregroundStyle(tint)
                .frame(width: fontSize + 10, height: fontSize + 10)
                .widgetAccentable()
            Text(item.title)
                .font(.system(size: fontSize))
                .strikethrough()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(intent: RestoreItemIntent(itemID: item.id)) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: fontSize - 1, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: fontSize + 12, height: fontSize + 10)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.title) nochmal kaufen")
        }
        .invalidatableContent()
    }
}

/// A category section header inside grocery stores.
struct WidgetSectionHeader: View {
    let category: ItemCategory
    let tint: Color

    var body: some View {
        Label(category.displayName, systemImage: category.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .labelStyle(CompactLabelStyle())
            .widgetAccentable()
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - States

/// No access, no list or onboarding not finished.
struct WidgetSetupPrompt: View {
    var compact = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cart.badge.questionmark")
                .font(.system(size: compact ? 24 : 32))
                .foregroundStyle(.secondary)
            Text("Öffne Marqet, um deine Einkaufsliste zu verbinden.")
                .font(compact ? .caption : .subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Empty card states, worded like the app (KONZEPT §7.2).
struct WidgetEmptyState: View {
    let page: WidgetSnapshot.Page
    let tint: Color
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 22 : 30, weight: .regular))
                .foregroundStyle(tint)
                .widgetAccentable()
            Text(title)
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if !compact, let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbol: String {
        if page.isInbox { return "tray" }
        return page.state == .shoppedEmpty ? "checkmark.seal.fill" : "cart.badge.plus"
    }

    private var title: String {
        guard let store = page.store else { return String(localized: "Alles sortiert") }
        return page.state == .shoppedEmpty
            ? String(localized: "Alles erledigt bei \(store.name)")
            : String(localized: "Noch leer")
    }

    private var detail: String? {
        if page.isInbox { return String(localized: "Einträge ohne Laden landen hier.") }
        return page.state == .shoppedEmpty ? nil : String(localized: "Tippe +, um etwas hinzuzufügen.")
    }
}

// MARK: - Layout helpers

/// One line of a list widget: a section header or an item.
enum WidgetLine: Identifiable {
    case header(ItemCategory)
    case item(WidgetSnapshot.Item)

    var id: String {
        switch self {
        case .header(let category): "header:\(category.rawValue)"
        case .item(let item): item.id
        }
    }

    var isHeader: Bool {
        if case .header = self { true } else { false }
    }

    /// Lines of a page within a budget; a header never ends a column without its items.
    static func lines(of page: WidgetSnapshot.Page, showsSections: Bool, limit: Int) -> (lines: [WidgetLine], hidden: Int) {
        var lines: [WidgetLine] = []
        for section in page.sections {
            if showsSections, let category = section.category, page.sections.count > 1 {
                lines.append(.header(category))
            }
            lines += section.items.map(WidgetLine.item)
        }
        var kept = Array(lines.prefix(limit))
        while kept.last?.isHeader == true { kept.removeLast() }
        let shownItems = kept.count { !$0.isHeader }
        return (kept, page.openCount - shownItems)
    }

    /// Splits lines into columns top to bottom, moving a header at a column's end to the next one.
    static func columns(_ lines: [WidgetLine], count: Int, perColumn: Int) -> [[WidgetLine]] {
        var columns: [[WidgetLine]] = []
        var current: [WidgetLine] = []
        for line in lines {
            if current.count == perColumn || (current.count == perColumn - 1 && line.isHeader) {
                columns.append(current)
                current = []
                if columns.count == count { break }
            }
            current.append(line)
        }
        if !current.isEmpty, columns.count < count { columns.append(current) }
        return columns
    }
}

/// "+ 6 weitere" below a list.
struct MoreItemsLabel: View {
    let count: Int
    var fontSize: CGFloat = 12

    var body: some View {
        if count > 0 {
            Text(count == 1 ? "+ 1 weiterer" : "+ \(count) weitere")
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
