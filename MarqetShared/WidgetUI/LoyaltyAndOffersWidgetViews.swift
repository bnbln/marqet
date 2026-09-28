import AppIntents
import MarqetCore
import SwiftUI
import WidgetKit

// MARK: - Kundenkarte (KONZEPT-WIDGETS §4.4)

struct LoyaltyCardWidgetView: View {
    let snapshot: WidgetSnapshot
    let card: LoyaltyCard?
    let family: WidgetFamily

    @Environment(\.widgetRenderingMode) private var renderingMode

    static func background(for card: LoyaltyCard?) -> some View {
        let color = Color(hex: card?.colorHex ?? "#56657A")
        return LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var foreground: Color {
        guard renderingMode == .fullColor, let card else { return .primary }
        return RGBColor(hex: card.colorHex)?.prefersDarkForeground == true ? .black.opacity(0.85) : .white
    }

    var body: some View {
        Group {
            if let card {
                switch family {
                case .systemMedium: medium(card)
                case .accessoryRectangular, .accessoryCircular, .accessoryInline: accessory(card)
                default: small(card)
                }
            } else {
                empty
            }
        }
        .widgetURL(card.map { MarqetLink.loyaltyCard($0.id).url })
    }

    private func stores(of card: LoyaltyCard) -> [Store] {
        card.storeIDs.compactMap(snapshot.store)
    }

    /// "Kundenkarte" – the store logos above already say whose. Without a store the card's own
    /// name is the only hint.
    private func title(of card: LoyaltyCard) -> String {
        stores(of: card).isEmpty ? card.name : String(localized: "Kundenkarte")
    }

    private func small(_ card: LoyaltyCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .widgetAccentable()
                Spacer()
                StoreStack(stores: stores(of: card), size: 24)
            }
            Spacer(minLength: 0)
            Text(title(of: card))
                .font(.system(size: 19, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .widgetAccentable()
            HStack(spacing: 4) {
                Image(systemName: "barcode")
                Text(maskedNumber(card))
                    .privacySensitive()
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .opacity(0.75)
            .padding(.top, 6)
        }
        .foregroundStyle(foreground)
        .padding(16)
    }

    private func medium(_ card: LoyaltyCard) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                // Logos on top, as in the small widget: they name the brand.
                HStack(alignment: .top) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .widgetAccentable()
                    Spacer(minLength: 4)
                    StoreStack(stores: stores(of: card), size: 22)
                }
                Spacer(minLength: 0)
                Text(title(of: card))
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .widgetAccentable()
            }
            .foregroundStyle(foreground)
            .frame(width: 110, alignment: .leading)

            VStack(spacing: 6) {
                WidgetBarcode(payload: card.payload, symbology: card.symbology)
                    .frame(maxWidth: WidgetBarcodeLayout.isSquare(card.symbology) ? 96 : .infinity, maxHeight: .infinity)
                Text(card.payload)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .privacySensitive()
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white, in: .rect(cornerRadius: 14, style: .continuous))
        }
        .padding(14)
    }

    @ViewBuilder
    private func accessory(_ card: LoyaltyCard) -> some View {
        switch family {
        case .accessoryInline:
            Label(card.name, systemImage: "wallet.pass")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 22, weight: .semibold))
            }
        default:
            HStack(spacing: 8) {
                Image(systemName: "wallet.pass.fill")
                    .font(.title2)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text(card.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("An der Kasse zeigen")
                        .font(.caption)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "wallet.pass")
                .font(.system(size: family.isAccessory ? 18 : 28))
            if !family.isAccessory {
                Text("Keine Kundenkarte")
                    .font(.system(size: 14, weight: .semibold))
                Text("Scanne sie einmal in Marqet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(family.isAccessory ? .primary : foreground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "•••• 3931": enough to tell cards apart, not enough to copy from a glance.
    private func maskedNumber(_ card: LoyaltyCard) -> String {
        let tail = card.payload.filter { !$0.isWhitespace }.suffix(4)
        return "•••• \(tail)"
    }
}

enum WidgetBarcodeLayout {
    static func isSquare(_ symbology: BarcodeSymbology) -> Bool {
        symbology == .qr || symbology == .aztec
    }
}

/// Overlapping badges of the stores a card belongs to.
private struct StoreStack: View {
    let stores: [Store]
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(stores.prefix(3)) { store in
                WidgetBadge(store: store, size: size)
                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.2))
            }
            if stores.count > 3 {
                Text("+\(stores.count - 3)")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .frame(width: size, height: size)
                    .background(.white.opacity(0.25), in: .circle)
            }
        }
    }
}

// MARK: - Angebote (KONZEPT-WIDGETS §4.5)

struct OffersWidgetView: View {
    let snapshot: WidgetSnapshot
    /// `nil`: own stores first, then chains nearby.
    var storeID: Store.ID?
    let family: WidgetFamily

    static let background = Color(.systemGroupedBackground)

    private var brochures: [WidgetSnapshot.Brochure] {
        guard let storeID, let store = snapshot.store(storeID) else { return snapshot.brochures }
        let own = snapshot.brochures.filter { $0.storeID == storeID || $0.key == store.catalogKey }
        return own + snapshot.brochures.filter { brochure in !own.contains(brochure) }
    }

    var body: some View {
        Group {
            if brochures.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("Keine Prospekte für deine Region")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                switch family {
                case .systemSmall: small
                case .systemLarge: shelf(columns: 3, rows: 2)
                default: shelf(columns: 4, rows: 1)
                }
            }
        }
        .widgetURL(url)
    }

    private var url: URL {
        if family == .systemSmall, let first = brochures.first { return MarqetLink.offer(catalogKey: first.key).url }
        return MarqetLink.offers.url
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Angebote")
                .font(.system(size: 15, weight: .bold))
            Spacer(minLength: 0)
            Text("KW \(WidgetFormat.calendarWeek)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var small: some View {
        let brochure = brochures[0]
        return VStack(alignment: .leading, spacing: 8) {
            title
            HStack(alignment: .bottom, spacing: 10) {
                BrochureCoverView(brochure: brochure)
                    .frame(width: 66, height: 89)
                VStack(alignment: .leading, spacing: 2) {
                    Text(brochure.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    Text(brochure.openCount > 0 ? "\(brochure.openCount) auf der Liste" : "Prospekt")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func shelf(columns: Int, rows: Int) -> some View {
        let shown = Array(brochures.prefix(columns * rows))
        return VStack(alignment: .leading, spacing: 8) {
            title
            VStack(spacing: 10) {
                ForEach(0..<rows, id: \.self) { row in
                    let slice = Array(shown.dropFirst(row * columns).prefix(columns))
                    if !slice.isEmpty {
                        HStack(alignment: .bottom, spacing: 12) {
                            ForEach(slice) { brochure in
                                Link(destination: MarqetLink.offer(catalogKey: brochure.key).url) {
                                    VStack(spacing: 4) {
                                        BrochureCoverView(brochure: brochure)
                                            .aspectRatio(BrochureCoverView.aspectRatio, contentMode: .fit)
                                        if rows > 1 {
                                            Text(brochure.name)
                                                .font(.system(size: 11, weight: .medium))
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            ForEach(0..<(columns - slice.count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                        .background(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.quaternarySystemFill))
                                .frame(height: 36)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            if rows > 1 {
                Text("Offizielle Angebotsseiten der Händler")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .padding(14)
    }
}

/// A leaflet cover: tinted page with the retailer's badge, a brand-colored spine and a hint of
/// pages behind – the widget version of the shelf in the Angebote card.
struct BrochureCoverView: View {
    let brochure: WidgetSnapshot.Brochure
    static let aspectRatio: CGFloat = 0.74

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let color = Color(hex: brochure.colorHex)
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 3, bottomTrailing: 7, topTrailing: 7), style: .continuous)
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                shape.fill(Color.white.opacity(colorScheme == .dark ? 0.55 : 0.8))
                    .offset(x: 3, y: -2)
                shape.fill(pageColor(color))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(renderingMode == .fullColor ? color : Color.primary.opacity(0.4))
                            .frame(width: max(width * 0.07, 3))
                    }
                    .overlay {
                        VStack(spacing: width * 0.06) {
                            WidgetBadge(store: brochure.store, size: width * 0.46)
                                .padding(.top, width * 0.14)
                            Rectangle()
                                .fill(renderingMode == .fullColor ? color.opacity(0.35) : Color.primary.opacity(0.2))
                                .frame(width: width * 0.5, height: 2)
                            Text("KW \(WidgetFormat.calendarWeek)")
                                .font(.system(size: max(width * 0.12, 8), weight: .bold, design: .rounded))
                                .foregroundStyle(renderingMode == .fullColor ? color : .primary)
                                .widgetAccentable()
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, width * 0.07)
                    }
                    .clipShape(shape)
                    .shadow(color: .black.opacity(0.14), radius: 3, y: 2)
                // How much is on the list there – calm, in the store color, not a red alert badge.
                if brochure.openCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "cart.fill")
                        Text(brochure.openCount, format: .number)
                    }
                    .font(.system(size: max(width * 0.11, 8), weight: .bold, design: .rounded))
                    .foregroundStyle(renderingMode == .fullColor ? brochure.store.foregroundOnColor : .primary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(renderingMode == .fullColor ? color : Color.primary.opacity(0.2), in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, width * 0.1)
                    .padding(.leading, width * 0.07)
                    .accessibilityLabel("\(brochure.openCount) auf der Liste")
                }
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prospekt \(brochure.name)")
    }

    private func pageColor(_ color: Color) -> Color {
        if renderingMode != .fullColor { return Color.primary.opacity(0.1) }
        return colorScheme == .dark ? Color(white: 0.92) : .white
    }
}
