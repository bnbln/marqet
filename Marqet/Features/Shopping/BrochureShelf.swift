import MarqetCore
import SwiftUI

/// Newsstand-style shelf: brochure covers stand in rows of two to four in soft shelf trays.
struct BrochureShelf: View {
    let entries: [StoreCatalog.Entry]
    var priceFinds: [PriceUpdateService.PriceFind] = []
    let open: (StoreCatalog.Entry) -> Void

    @Environment(AppModel.self) private var model

    @State private var width: CGFloat = 0

    private static let spacing: CGFloat = 16
    /// The tray reaches this far past the outer covers (the scroll view clips anything wider).
    static let trayInset: CGFloat = 10
    private static let minimumCoverWidth: CGFloat = 92

    /// Three covers on a phone card, two on very narrow widths, four on wide ones.
    private var columns: Int {
        guard width > 0 else { return 3 }
        let fitting = Int((width + Self.spacing) / (Self.minimumCoverWidth + Self.spacing))
        return min(max(fitting, 2), 4)
    }

    private var rows: [[StoreCatalog.Entry]] {
        stride(from: 0, to: entries.count, by: columns).map {
            Array(entries[$0 ..< min($0 + columns, entries.count)])
        }
    }

    private var coverWidth: CGFloat {
        let columns = CGFloat(columns)
        return max((width - 2 * Self.trayInset - Self.spacing * (columns - 1)) / columns, 0)
    }

    var body: some View {
        LazyVStack(spacing: 22) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                ShelfRow(entries: row, coverWidth: coverWidth, spacing: Self.spacing, open: open)
                if index < priceFinds.count {
                    PriceFindCard(find: priceFinds[index], storeName: model.catalog?.entry(forKey: priceFinds[index].store)?.name ?? priceFinds[index].store,
                                  currencyCode: model.region.currencyCode)
                }
            }
            ForEach(Array(priceFinds.dropFirst(rows.count))) { find in
                PriceFindCard(find: find, storeName: model.catalog?.entry(forKey: find.store)?.name ?? find.store,
                              currencyCode: model.region.currencyCode)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

private struct PriceFindCard: View {
    let find: PriceUpdateService.PriceFind
    let storeName: String
    let currencyCode: String

    private var amount: String {
        let price = find.amount.formatted(.currency(code: currencyCode))
        return switch find.unit {
        case .kilogram: "\(price)/kg"
        case .liter: "\(price)/l"
        case .piece: "\(price)/Stk."
        case nil: price
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(find.kind == .observedDiscount ? "Gemeldeter Angebotspreis" : "Preisführer", systemImage: "tag.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
                if let discount = find.discountPercent {
                    Text("−\(discount) %")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(find.title).font(.headline).lineLimit(2)
                    Text(storeName).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(amount).font(.headline.monospacedDigit())
            }
            HStack {
                Group {
                    if find.kind == .observedDiscount {
                        Text("Open Prices · gesehen am \(find.date)")
                    } else {
                        Text("Open Prices · Daten bis \(find.date)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Spacer()
                if let url = find.sourceURL { Link("Beleg", destination: url).font(.caption) }
            }
            Text("Community-Meldung · Preis vor Ort prüfen")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct ShelfRow: View {
    let entries: [StoreCatalog.Entry]
    let coverWidth: CGFloat
    let spacing: CGFloat
    let open: (StoreCatalog.Entry) -> Void

    private var coverHeight: CGFloat { coverWidth / BrochureCover.aspectRatio }
    /// How far the covers stand above the tray's bottom edge.
    private static let floorInset: CGFloat = 14

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(entries) { entry in
                Button { open(entry) } label: {
                    BrochureCover(entry: entry)
                        .frame(width: coverWidth, height: coverHeight)
                }
                .buttonStyle(CoverButtonStyle())
                .accessibilityLabel("Prospekt \(entry.name)")
                .accessibilityHint("Öffnet die offizielle Angebotsseite von \(entry.name)")
            }
        }
        .padding(.horizontal, BrochureShelf.trayInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Self.floorInset)
        .background(alignment: .bottom) {
            ShelfTray()
                .frame(height: coverHeight * 0.42 + Self.floorInset)
        }
    }
}

/// A soft recessed tray the covers stand in, with a slightly brighter front lip.
private struct ShelfTray: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.quaternarySystemFill))
            .overlay(alignment: .bottom) {
                UnevenRoundedRectangle(
                    cornerRadii: .init(bottomLeading: 18, bottomTrailing: 18),
                    style: .continuous
                )
                .fill(Color(.tertiarySystemFill))
                .frame(height: 8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

/// A clean paper cover: the retailer's logo on a lightly tinted page, a brand-colored spine
/// and a hint of pages behind it.
private struct BrochureCover: View {
    let entry: StoreCatalog.Entry

    static let aspectRatio: CGFloat = 0.74
    private static let corners = RectangleCornerRadii(topLeading: 3, bottomLeading: 3, bottomTrailing: 8, topTrailing: 8)

    @Environment(\.colorScheme) private var colorScheme

    private static let calendarWeek: Int = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = .current
        return calendar.component(.weekOfYear, from: .now)
    }()

    var body: some View {
        let store = entry.makeStore(sortIndex: 0)
        let shape = UnevenRoundedRectangle(cornerRadii: Self.corners, style: .continuous)

        GeometryReader { proxy in
            let width = proxy.size.width
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                StoreBadge(store: store, size: width * 0.42)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                Spacer(minLength: 0)

                VStack(spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: max(width * 0.11, 12), weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("KW \(Self.calendarWeek)")
                        .font(.system(size: max(width * 0.08, 10), weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.bottom, width * 0.1)
            }
            .padding(.leading, width * 0.05)
            .padding(.horizontal, width * 0.08)
            .frame(width: width, height: proxy.size.height)
        }
        .background(paper(for: store), in: shape)
        // Brand-colored spine, like the bound edge of a brochure.
        .overlay(alignment: .leading) {
            store.color
                .frame(width: 5)
                .overlay(alignment: .trailing) { Color.black.opacity(0.12).frame(width: 0.5) }
        }
        // Gentle page curvature: a touch of light across the paper.
        .overlay {
            LinearGradient(
                colors: [.white.opacity(colorScheme == .dark ? 0.04 : 0.35), .clear, .black.opacity(0.03)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
        // Pages peeking out behind the cover.
        .background {
            shape.fill(pageEdge).offset(x: 2.5, y: -1.5).padding(.vertical, 2)
        }
        .shadow(color: .black.opacity(0.14), radius: 1, y: 1)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.12), radius: 12, y: 8)
    }

    private func paper(for store: Store) -> Color {
        colorScheme == .dark
            ? store.color.mix(with: Color(white: 0.16), by: 0.82)
            : store.color.mix(with: .white, by: 0.9)
    }

    private var pageEdge: Color {
        colorScheme == .dark ? Color(white: 0.24) : Color(white: 0.93)
    }
}

/// Covers lift off the shelf when pressed.
private struct CoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.04 : 1, anchor: .bottom)
            .offset(y: configuration.isPressed ? -4 : 0)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

#Preview {
    let entries = (try? StoreCatalog.bundled())?.entries(for: .germany).filter { $0.leafletURL != nil } ?? []
    ScrollView {
        BrochureShelf(entries: entries) { _ in }
            .padding(20)
    }
    .background(Color(.secondarySystemGroupedBackground))
}
