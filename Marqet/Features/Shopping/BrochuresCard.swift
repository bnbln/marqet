import MarqetCore
import SwiftUI

/// First page of the deck: the central collection of official retailer brochures.
struct BrochuresCard: View {
    /// Full screen in `BrochuresScreen` instead of a card in the pager.
    var isExpanded = false

    @Environment(AppModel.self) private var model
    @Environment(\.cardZoomNamespace) private var zoomNamespace
    @State private var selectedLeaflet: LeafletDestination?
    /// The user's finger is on the shelf – only then does pulling up open the card full screen
    /// (KONZEPT §6.3: same "pull up to focus" gesture as the store cards).
    @State private var isDraggingShelf = false

    private var entries: [StoreCatalog.Entry] {
        let alphabetical = (model.catalog?.entries(for: model.region) ?? [])
            .filter { $0.leafletURL != nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard model.userLocation != nil else { return alphabetical }
        return alphabetical.enumerated().sorted { lhs, rhs in
            let left = distance(for: lhs.element)
            let right = distance(for: rhs.element)
            switch (left, right) {
            case let (left?, right?) where left != right: return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Angebote")
                        .font(.title2.bold())
                    Text("Prospekte und gemeldete Preisfunde")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
                .onTapGesture { model.focus(.brochures) }
            }

            ScrollView {
                if entries.isEmpty && model.offerPriceFinds.isEmpty {
                    ContentUnavailableView(
                        "Keine Angebote verfügbar",
                        systemImage: "newspaper",
                        description: Text("Für deine Region sind noch keine offiziellen Angebotsseiten hinterlegt.")
                    )
                } else {
                    BrochureShelf(entries: entries, priceFinds: model.offerPriceFinds) { entry in
                        if let url = entry.leafletURL { selectedLeaflet = LeafletDestination(url: url) }
                    }
                }
                if model.isRefreshingPrices {
                    ProgressView("Preise werden geladen")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else if model.locationAuthorization != .authorized && model.openPricesEnabled {
                    Button("Lokale Preisfunde anzeigen", systemImage: "location") {
                        Task {
                            if await model.updateUserLocation() != nil {
                                await model.refreshPrices(includeOffers: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else if model.userLocation != nil && model.offerPriceFinds.isEmpty && model.openPricesEnabled {
                    Text("In deiner Umgebung gibt es noch keine belegten Preisfunde.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                if let error = model.priceRefreshError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .scrollIndicators(.visible)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if model.composerTarget != nil { model.endComposer() }
                    }
            }
            // Pulling the shelf up opens the card full screen, same gesture as the store cards.
            .onScrollPhaseChange { _, phase in
                isDraggingShelf = phase == .interacting
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 36
            } action: { _, pulledUp in
                if pulledUp, isDraggingShelf, !isExpanded { model.focus(.brochures) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(BrochuresCardChrome(isExpanded: isExpanded))
        .modifier(CardZoomSource(page: .brochures, namespace: isExpanded ? nil : zoomNamespace))
        .sheet(item: $selectedLeaflet) { destination in
            SafariView(url: destination.url).ignoresSafeArea()
        }
        .task {
            await model.refreshNearbyCatalogDistancesIfNeeded()
        }
        .task(id: model.activePage == .brochures || isExpanded) {
            if model.activePage == .brochures || isExpanded {
                Task { await model.refreshPrices(includeOffers: true) }
            }
        }
    }

    private func distance(for entry: StoreCatalog.Entry) -> Double? {
        guard let origin = model.userLocation,
              let store = model.stores.first(where: { $0.catalogKey == entry.key }),
              let location = model.relevantLocation(of: store.id) else {
            return model.nearbyCatalogDistances[entry.key]
        }
        return location.coordinate.distance(to: origin)
    }
}

private struct LeafletDestination: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Card look in the pager, edge-to-edge surface full screen (mirrors `StoreCard`'s `CardChrome`).
private struct BrochuresCardChrome: ViewModifier {
    let isExpanded: Bool

    func body(content: Content) -> some View {
        if isExpanded {
            content.background(Color(.secondarySystemGroupedBackground))
        } else {
            content.cardSurface()
        }
    }
}

/// The `.brochures` card full screen – reached the same way as a store card (pull up on the
/// shelf, or tap its header) and zooming from the same `matchedTransitionSource`.
struct BrochuresScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BrochuresCard(isExpanded: true)
                .navigationTitle("Angebote")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityLabel("Schließen")
                    }
                }
        }
        .tint(.primary)
    }
}
