import MarqetCore
import SwiftUI
import WidgetKit

/// Einstellungen › Widgets & Live-Aktivität (KONZEPT-WIDGETS §10): the Live Activity switch and a
/// gallery of every widget with the user's own lists – the same views as on the Home Screen.
struct WidgetSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var snapshot = WidgetSnapshot.sampleWithoutTrip

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                Toggle("Beim Abhaken automatisch starten", isOn: $model.autoStartsTrip)
                tripButton
            } header: {
                Text("Live-Aktivität „Einkauf“")
            } footer: {
                Text("Zeigt auf dem Sperrbildschirm und in der Dynamic Island die nächsten Einträge im Laufweg, den Fortschritt und deine Kundenkarte. Sie wandert mit, wenn du im nächsten Laden abhakst, und endet von selbst, wenn alles erledigt ist oder 30 Minuten nichts passiert.")
            }

            if let status = tripPreview {
                Section("Sperrbildschirm") {
                    TripLockScreenView(status: status)
                        .background(status.store.color)
                        .clipShape(.rect(cornerRadius: 24, style: .continuous))
                        .allowsHitTesting(false)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }

            GallerySection(title: "Liste", detail: "Ein Laden, die Inbox, der nächste Laden oder zuletzt Erledigtes – abhaken direkt im Widget.") {
                WidgetPreviewTile(family: .systemSmall, background: ListWidgetView.background) {
                    ListWidgetView(snapshot: snapshot, list: .automatic, family: .systemSmall)
                }
                WidgetPreviewTile(family: .systemMedium, background: ListWidgetView.background) {
                    ListWidgetView(snapshot: snapshot, list: .automatic, family: .systemMedium)
                }
                WidgetPreviewTile(family: .systemMedium, background: ListWidgetView.background) {
                    ListWidgetView(snapshot: snapshot, list: .inbox, family: .systemMedium)
                }
                WidgetPreviewTile(family: .systemLarge, background: ListWidgetView.background) {
                    ListWidgetView(snapshot: snapshot, list: .automatic, family: .systemLarge)
                }
                WidgetPreviewTile(family: .systemSmall, background: ListWidgetView.background) {
                    ListWidgetView(snapshot: snapshot, list: .completed, family: .systemSmall)
                }
            }

            GallerySection(title: "Überblick", detail: "Alle Läden wie die Cards in der App, mit „Einkauf starten“.") {
                WidgetPreviewTile(family: .systemSmall, background: OverviewWidgetView.background) {
                    OverviewWidgetView(snapshot: snapshot, family: .systemSmall)
                }
                WidgetPreviewTile(family: .systemMedium, background: OverviewWidgetView.background) {
                    OverviewWidgetView(snapshot: snapshot, family: .systemMedium)
                }
                WidgetPreviewTile(family: .systemLarge, background: OverviewWidgetView.background) {
                    OverviewWidgetView(snapshot: snapshot, family: .systemLarge)
                }
            }

            if #available(iOS 27.0, *) {
                GallerySection(title: "Extragroß", detail: "Eine ganze Seite des Home-Bildschirms – ideal auf dem aufgeklappten iPhone Duo.") {
                    WidgetPreviewTile(family: .systemExtraLargePortrait, background: ListWidgetView.background) {
                        ListWidgetView(snapshot: snapshot, list: .automatic, family: .systemExtraLargePortrait)
                    }
                    WidgetPreviewTile(family: .systemExtraLargePortrait, background: OverviewWidgetView.background) {
                        OverviewWidgetView(snapshot: snapshot, family: .systemExtraLargePortrait)
                    }
                }
            }

            GallerySection(title: "Kundenkarte & Angebote", detail: "Der Barcode für die Kasse und die Prospekte deiner Läden.") {
                let card = snapshot.automaticLoyaltyCard
                WidgetPreviewTile(family: .systemSmall, background: LoyaltyCardWidgetView.background(for: card)) {
                    LoyaltyCardWidgetView(snapshot: snapshot, card: card, family: .systemSmall)
                }
                WidgetPreviewTile(family: .systemMedium, background: LoyaltyCardWidgetView.background(for: card)) {
                    LoyaltyCardWidgetView(snapshot: snapshot, card: card, family: .systemMedium)
                }
                WidgetPreviewTile(family: .systemMedium, background: OffersWidgetView.background) {
                    OffersWidgetView(snapshot: snapshot, family: .systemMedium)
                }
                WidgetPreviewTile(family: .systemLarge, background: OffersWidgetView.background) {
                    OffersWidgetView(snapshot: snapshot, family: .systemLarge)
                }
            }

            GallerySection(title: "Sperrbildschirm", detail: "Klein und einfarbig – für den nächsten Laden, alle Läden oder die Kundenkarte.") {
                WidgetPreviewTile(family: .accessoryRectangular, background: Color.black.opacity(0.75)) {
                    ListWidgetView(snapshot: snapshot, list: .automatic, family: .accessoryRectangular)
                }
                WidgetPreviewTile(family: .accessoryCircular, background: Color.black.opacity(0.75)) {
                    OverviewWidgetView(snapshot: snapshot, family: .accessoryCircular)
                }
                WidgetPreviewTile(family: .accessoryRectangular, background: Color.black.opacity(0.75)) {
                    OverviewWidgetView(snapshot: snapshot, family: .accessoryRectangular)
                }
            }

            Section {
                Label("Home-Bildschirm gedrückt halten, „Bearbeiten“ › „Widget hinzufügen“ und nach Marqet suchen.", systemImage: "plus.square.on.square")
                Label("Widget gedrückt halten › „Widget bearbeiten“: Liste, Reihenfolge oder Kundenkarte wählen.", systemImage: "slider.horizontal.3")
                Label("Kontrollzentrum: „Eintrag hinzufügen“, „Kundenkarte“ und „Einkauf“ – auch für die Aktionstaste.", systemImage: "switch.2")
            } header: {
                Text("So geht’s")
            }
            .font(.subheadline)
        }
        .navigationTitle("Widgets & Live-Aktivität")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.items) {
            let own = model.makeWidgetSnapshot()
            // Without own lists yet, the demo shop shows what the widgets can do.
            snapshot = own.status == .ready && own.totalOpenCount > 0 ? own : .sampleWithoutTrip
        }
    }

    @ViewBuilder
    private var tripButton: some View {
        if let trip = model.trip, let store = model.store(trip.storeID) {
            Button("Einkauf bei \(store.name) beenden", systemImage: "cart.badge.minus", role: .destructive) {
                Task { await model.endTrip() }
            }
        } else {
            Button("Einkauf jetzt starten", systemImage: "cart") {
                Task { await model.startTrip(at: nil) }
            }
            .disabled(!model.stores.contains { model.openItemCount(of: $0.id) > 0 })
        }
    }

    /// The running trip, or what one would look like at the next store.
    private var tripPreview: TripStatus? {
        let trip = snapshot.trip ?? snapshot.automaticPage?.store.map { ShoppingTrip(storeID: $0.id) }
        return trip.flatMap { TripStatus.make(snapshot: snapshot, trip: $0) }
    }
}

/// A vertical gallery: tiles keep their Home Screen size and scale down to the row if needed.
private struct GallerySection<Content: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        Section {
            WidgetFlow(spacing: 16) {
                content
            }
            .padding(.vertical, 12)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .textCase(nil)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Lays tiles out like the Home Screen grid: side by side while they fit, otherwise one per row,
/// scaled down (never up) when a tile is wider than the row.
private struct WidgetFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 364
        let rows = rows(for: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let scale = row.scale
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width * scale, height: size.height * scale))
                x += size.width * scale + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var scale: CGFloat = 1
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, needed > width {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.indices.append(index)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows.map { row in
            var row = row
            row.scale = min(1, width / max(row.width, 1))
            row.height *= row.scale
            return row
        }
    }
}

/// A widget at its Home Screen size with the system's corner radius. Buttons stay inert here.
struct WidgetPreviewTile<Content: View, Background: View>: View {
    let family: WidgetFamily
    let background: Background
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / size.width, 1)
            tile
                .scaleEffect(scale, anchor: .topLeading)
        }
        .frame(idealWidth: size.width, idealHeight: size.height)
    }

    private var tile: some View {
        content
            .frame(width: size.width, height: size.height)
            .background(background)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .environment(\.colorScheme, family.isAccessory ? .dark : colorScheme)
            .foregroundStyle(family.isAccessory ? Color.white : Color.primary)
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .allowsHitTesting(false)
            .accessibilityElement(children: .contain)
    }

    @Environment(\.colorScheme) private var colorScheme

    /// iPhone 6.3" sizes.
    private var size: CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemMedium: CGSize(width: 364, height: 170)
        case .systemLarge: CGSize(width: 364, height: 382)
        case .accessoryRectangular: CGSize(width: 172, height: 76)
        case .accessoryCircular: CGSize(width: 76, height: 76)
        case .accessoryInline: CGSize(width: 250, height: 24)
        default: family.isExtraLargePortrait ? CGSize(width: 364, height: 594) : CGSize(width: 715, height: 330)
        }
    }

    private var cornerRadius: CGFloat {
        switch family {
        case .accessoryCircular: 38
        case .accessoryRectangular, .accessoryInline: 14
        default: 24
        }
    }
}
