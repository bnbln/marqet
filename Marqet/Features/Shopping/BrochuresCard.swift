import MarqetCore
import SwiftUI

/// First page of the deck: the central collection of official retailer brochures.
struct BrochuresCard: View {
    @Environment(AppModel.self) private var model
    @State private var selectedLeaflet: LeafletDestination?

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
            VStack(alignment: .leading, spacing: 4) {
                Text("Angebote")
                    .font(.title2.bold())
                Text("Offizielle Angebotsseiten der Händler")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "Keine Angebote verfügbar",
                        systemImage: "newspaper",
                        description: Text("Für deine Region sind noch keine offiziellen Angebotsseiten hinterlegt.")
                    )
                } else {
                    BrochureShelf(entries: entries) { entry in
                        if let url = entry.leafletURL { selectedLeaflet = LeafletDestination(url: url) }
                    }
                    .padding(.bottom, 4)
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

        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
        .sheet(item: $selectedLeaflet) { destination in
            SafariView(url: destination.url).ignoresSafeArea()
        }
        .task {
            await model.refreshNearbyCatalogDistancesIfNeeded()
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
