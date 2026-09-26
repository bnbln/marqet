import MarqetCore
import SwiftUI

/// Newsstand-style shelf: brochure covers stand in rows of two to four on a floating ledge.
struct BrochureShelf: View {
    let entries: [StoreCatalog.Entry]
    let open: (StoreCatalog.Entry) -> Void

    @State private var width: CGFloat = 0

    private static let spacing: CGFloat = 16
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
        return max((width - Self.spacing * (columns - 1)) / columns, 0)
    }

    var body: some View {
        LazyVStack(spacing: 26) {
            ForEach(rows, id: \.first?.id) { row in
                ShelfRow(entries: row, coverWidth: coverWidth, spacing: Self.spacing, open: open)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

private struct ShelfRow: View {
    let entries: [StoreCatalog.Entry]
    let coverWidth: CGFloat
    let spacing: CGFloat
    let open: (StoreCatalog.Entry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(entries) { entry in
                    Button { open(entry) } label: {
                        BrochureCover(entry: entry)
                            .frame(width: coverWidth)
                    }
                    .buttonStyle(CoverButtonStyle())
                    .accessibilityLabel("Prospekt \(entry.name)")
                    .accessibilityHint("Öffnet die offizielle Angebotsseite von \(entry.name)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .zIndex(1)

            ShelfLedge()
                // Covers stand slightly into the ledge's top face.
                .padding(.top, -6)
                .padding(.horizontal, -8)
        }
    }
}

/// A modern ledge: a light top face, a slim front edge and a soft shadow below.
private struct ShelfLedge: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color(.systemGray5), Color(.systemGray4)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 12)

            Color(.systemGray3)
                .frame(height: 5)
                .overlay(alignment: .top) {
                    Color.white.opacity(0.35).frame(height: 0.5)
                }
        }
        .clipShape(.rect(cornerRadius: 4, style: .continuous))
        .background(alignment: .bottom) {
            Capsule()
                .fill(.black.opacity(0.18))
                .frame(height: 10)
                .padding(.horizontal, 14)
                .offset(y: 8)
                .blur(radius: 8)
        }
        .accessibilityHidden(true)
    }
}

/// A generated brochure cover in the retailer's colors.
private struct BrochureCover: View {
    let entry: StoreCatalog.Entry

    private var store: Store { entry.makeStore(sortIndex: 0) }

    private static let calendarWeek: Int = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = .current
        return calendar.component(.weekOfYear, from: .now)
    }()

    var body: some View {
        let store = store
        let foreground = store.foregroundOnColor

        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [store.color, store.color.mix(with: .black, by: 0.18)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                // Oversized decorative disc, like a cover graphic.
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(foreground.opacity(0.12))
                        .frame(width: width * 1.1, height: width * 1.1)
                        .offset(x: width * 0.4, y: width * 0.3)
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        StoreBadge(store: store, size: width * 0.3)
                        Spacer(minLength: 4)
                        Text("KW \(Self.calendarWeek)")
                            .font(.system(size: width * 0.09, weight: .bold, design: .rounded))
                            .foregroundStyle(foreground.opacity(0.8))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Text(entry.name)
                        .font(.system(size: width * 0.17, weight: .heavy, design: .rounded))
                        .foregroundStyle(foreground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Angebote")
                        .font(.system(size: width * 0.1, weight: .semibold, design: .rounded))
                        .foregroundStyle(foreground.opacity(0.75))
                        .padding(.top, 1)
                }
                .padding(width * 0.09)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Spine and a soft gloss sell the printed-paper feel.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.22), location: 0),
                        .init(color: .white.opacity(0.12), location: 0.035),
                        .init(color: .clear, location: 0.09),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                LinearGradient(
                    colors: [.white.opacity(0.16), .clear],
                    startPoint: .topTrailing, endPoint: .center
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(0.72, contentMode: .fit)
        .clipShape(.rect(cornerRadii: .init(topLeading: 2, bottomLeading: 2, bottomTrailing: 6, topTrailing: 6), style: .continuous))
        .overlay {
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 2, bottomLeading: 2, bottomTrailing: 6, topTrailing: 6), style: .continuous)
                .strokeBorder(.black.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.22), radius: 6, x: 2, y: 4)
        .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 1)
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
