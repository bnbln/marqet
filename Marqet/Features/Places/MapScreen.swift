import MapKit
import MarqetCore
import SwiftUI

/// "Karte" (KONZEPT §14.1): own stores with their open items, chains nearby to add, search.
struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var nearby: [PlaceResult] = []
    @State private var query = ""
    @State private var searchResults: [PlaceResult] = []
    @State private var selectedPlace: PlaceResult?
    @State private var selectedStoreID: Store.ID?
    @State private var isLoading = false

    private struct StorePin: Identifiable {
        let store: Store
        let location: StoreLocation
        var id: UUID { store.id }
    }

    private var storePins: [StorePin] {
        model.sortedStores.compactMap { store in
            model.relevantLocation(of: store.id).map { StorePin(store: store, location: $0) }
        }
    }

    /// Chains nearby the user has not added yet – shown faded with a plus.
    private var suggestions: [PlaceResult] {
        nearby.filter { model.chain(of: $0) != nil && model.existingStore(for: $0) == nil }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                UserAnnotation()
                ForEach(storePins) { pin in
                    Annotation(pin.store.name, coordinate: pin.location.coordinate.clCoordinate) {
                        Button { selectedStoreID = pin.store.id } label: {
                            StoreBadge(store: pin.store, size: 38)
                                .overlay(alignment: .topTrailing) { countBadge(model.openItemCount(of: pin.store.id)) }
                                .shadow(radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                ForEach(suggestions) { place in
                    Annotation(place.name, coordinate: place.coordinate.clCoordinate) {
                        Button { selectedPlace = place } label: {
                            if let chain = model.chain(of: place) {
                                StoreBadge(store: chain.makeStore(sortIndex: 0), size: 30)
                                    .opacity(0.55)
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.white, Color.accentColor)
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .overlay(alignment: .top) {
                if !searchResults.isEmpty { searchResultList }
            }
            .safeAreaInset(edge: .bottom) {
                if !storePins.isEmpty { storeStrip }
            }
            .searchable(text: $query, prompt: "Laden oder Adresse suchen")
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: query) { _, text in if text.isEmpty { searchResults = [] } }
            .navigationTitle("Karte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                if isLoading {
                    ToolbarItem(placement: .primaryAction) { ProgressView() }
                }
            }
            .task { await loadNearby() }
            .sheet(item: $selectedPlace) { place in
                PlaceActionSheet(place: place) { selectedPlace = nil }
                    .presentationDetents([.height(280)])
            }
            .sheet(item: Binding(get: { selectedStoreID.flatMap(model.store) }, set: { selectedStoreID = $0?.id })) { store in
                StoreOnMapSheet(store: store) { page in
                    selectedStoreID = nil
                    model.activePage = page
                    model.pageRequest = page
                    dismiss()
                }
                .presentationDetents([.height(260)])
            }
        }
    }

    private func countBadge(_ count: Int) -> some View {
        Group {
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(.red, in: .capsule)
                    .offset(x: 6, y: -6)
            }
        }
    }

    /// Own stores, nearest first, with distance – tap to fly there.
    private var storeStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(storePins.sorted { (model.travelMinutes(to: $0.store.id) ?? .infinity) < (model.travelMinutes(to: $1.store.id) ?? .infinity) }) { pin in
                    Button {
                        withAnimation {
                            position = .region(MKCoordinateRegion(center: pin.location.coordinate.clCoordinate, latitudinalMeters: 800, longitudinalMeters: 800))
                        }
                        selectedStoreID = pin.store.id
                    } label: {
                        HStack(spacing: 8) {
                            StoreBadge(store: pin.store, size: 24)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(pin.store.name).font(.subheadline.weight(.semibold))
                                if let distance = model.distanceText(to: pin.store.id) {
                                    Text(distance).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var searchResultList: some View {
        List(searchResults) { place in
            Button {
                selectedPlace = place
                withAnimation {
                    position = .region(MKCoordinateRegion(center: place.coordinate.clCoordinate, latitudinalMeters: 800, longitudinalMeters: 800))
                }
                searchResults = []
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).foregroundStyle(.primary)
                    if let address = place.address {
                        Text(address).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .frame(maxHeight: 320)
        .clipShape(.rect(cornerRadius: 20))
        .padding(12)
        .shadow(radius: 8)
    }

    private func loadNearby() async {
        isLoading = true
        defer { isLoading = false }
        guard let origin = await model.updateUserLocation() else { return }
        nearby = (try? await model.placeSearch.shops(near: origin)) ?? []
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        searchResults = (try? await model.placeSearch.search(text, near: model.userLocation)) ?? []
    }
}

/// Actions for a place: add it as a store (or as a branch of an existing one), open in Maps.
private struct PlaceActionSheet: View {
    let place: PlaceResult
    let onDone: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let existing = model.existingStore(for: place)
        let chain = model.chain(of: place)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if let store = existing ?? chain?.makeStore(sortIndex: 0) {
                    StoreBadge(store: store, size: 44)
                } else {
                    Image(systemName: place.suggestedType.defaultSymbol)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(Color(.tertiarySystemFill), in: .circle)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(.headline)
                    if let address = place.address {
                        Text(address).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                model.addStore(from: place)
                onDone()
            } label: {
                Label(existing == nil
                      ? "Als Laden hinzufügen"
                      : "Als Filiale von \(existing?.name ?? "") speichern",
                      systemImage: existing == nil ? "plus" : "mappin.and.ellipse")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            Button("In Karten öffnen", systemImage: "map") { place.openInMaps() }
                .frame(maxWidth: .infinity)
        }
        .padding(20)
    }
}

private struct StoreOnMapSheet: View {
    let store: Store
    let onShowCard: (PageID) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let location = model.relevantLocation(of: store.id)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                StoreBadge(store: store, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.name).font(.headline)
                    Text([location?.address, model.distanceText(to: store.id)].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(model.openItemCount(of: store.id)) offene Einträge")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Zur Card", systemImage: "rectangle.stack") { onShowCard(.store(store.id)) }
                    .buttonStyle(.glassProminent)
                if let location {
                    Button("Route", systemImage: "arrow.triangle.turn.up.right.diamond") {
                        PlaceResult(name: store.name, address: location.address, coordinate: location.coordinate,
                                    mapItemIdentifier: location.mapItemIdentifier, suggestedType: store.type).openInMaps()
                    }
                    .buttonStyle(.glass)
                }
            }
            .controlSize(.large)
        }
        .padding(20)
    }
}

extension PlaceResult {
    func openInMaps() {
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
