import MapKit
import MarqetCore
import SwiftUI

/// "Karte" (KONZEPT §14.1): the user's stores with all their branches around the visible area,
/// chains not added yet, and a search.
struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Places found around the visible area: branches of own stores and shops nearby.
    @State private var found: [PlaceResult] = []
    @State private var lastLoad: (center: GeoPoint, radius: Double)?
    @State private var loadTask: Task<Void, Never>?
    @State private var query = ""
    @State private var searchResults: [PlaceResult] = []
    @State private var selectedPin: MapPin?
    @State private var isLoading = false

    private static let initialRadius: Double = 2_500

    var body: some View {
        let pins = model.mapPins(found: found)
        NavigationStack {
            Map(position: $position) {
                UserAnnotation()
                ForEach(pins) { pin in
                    Annotation(title(of: pin), coordinate: pin.coordinate.clCoordinate) {
                        // Annotation content does not inherit the environment – pass what the pin shows.
                        Button { selectedPin = pin } label: {
                            PinView(pin: pin, openCount: pin.store.map { model.openItemCount(of: $0.id) } ?? 0, chainStore: chainStore(of: pin))
                        }
                            .buttonStyle(.plain)
                    }
                    .annotationTitles(isOwn(pin) ? .automatic : .hidden)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                let region = context.region
                let radius = min(region.span.latitudeDelta * 111_000, region.span.longitudeDelta * 111_000 * cos(region.center.latitude * .pi / 180)) / 2
                scheduleLoad(center: GeoPoint(latitude: region.center.latitude, longitude: region.center.longitude), radius: radius)
            }
            .overlay(alignment: .top) {
                if !searchResults.isEmpty { searchResultList }
            }
            .safeAreaInset(edge: .bottom) {
                storeStrip(pins: pins)
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
            .task {
                if let origin = await model.updateUserLocation() {
                    scheduleLoad(center: origin, radius: Self.initialRadius, immediately: true)
                }
            }
            .sheet(item: $selectedPin) { pin in
                PinSheet(pin: pin) { page in
                    selectedPin = nil
                    if let page {
                        model.activePage = page
                        model.pageRequest = page
                        dismiss()
                    }
                }
                .presentationDetents([.height(300)])
            }
        }
    }

    private func title(of pin: MapPin) -> String {
        pin.store?.name ?? pin.place?.name ?? ""
    }

    private func chainStore(of pin: MapPin) -> Store? {
        guard case .suggestion(_, let key) = pin.kind else { return nil }
        return model.catalog?.entry(forKey: key)?.makeStore(sortIndex: 0)
    }

    private func isOwn(_ pin: MapPin) -> Bool {
        if case .saved = pin.kind { true } else { false }
    }

    // MARK: Loading

    /// Loads again only when the map moved noticeably or zoomed – MapKit throttles searches.
    private func scheduleLoad(center: GeoPoint, radius: Double, immediately: Bool = false) {
        let radius = min(max(radius, 800), 8_000)
        if let lastLoad, !immediately {
            let moved = center.distance(to: lastLoad.center)
            let zoomed = max(radius, lastLoad.radius) / min(radius, lastLoad.radius)
            guard moved > lastLoad.radius * 0.4 || zoomed > 1.8 else { return }
        }
        loadTask?.cancel()
        loadTask = Task {
            if !immediately { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled else { return }
            await load(center: center, radius: radius)
        }
    }

    private func load(center: GeoPoint, radius: Double) async {
        lastLoad = (center, radius)
        isLoading = true
        defer { isLoading = false }
        var results = (try? await model.placeSearch.shops(near: center)) ?? []
        for store in model.storesForBranchSearch() {
            guard !Task.isCancelled else { return }
            let chain = store.catalogKey.flatMap { model.catalog?.entry(forKey: $0) }
            results += (try? await model.placeSearch.branches(of: store, chain: chain, near: center, radius: radius)) ?? []
        }
        // Keep what was found elsewhere, so panning back does not empty the map.
        var seen = Set(results.map(\.id))
        found = results + found.filter { seen.insert($0.id).inserted }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        let center = lastLoad?.center ?? model.userLocation
        searchResults = (try? await model.placeSearch.search(text, near: center)) ?? []
    }

    // MARK: Store strip

    /// Own stores, nearest branch first, with distance – tap to fly there.
    @ViewBuilder
    private func storeStrip(pins: [MapPin]) -> some View {
        let nearest = nearestPinPerStore(pins)
        if !nearest.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(nearest) { pin in
                        if let store = pin.store {
                            Button {
                                fly(to: pin.coordinate)
                                selectedPin = pin
                            } label: {
                                HStack(spacing: 8) {
                                    StoreBadge(store: store, size: 24)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(store.name).font(.subheadline.weight(.semibold))
                                        if let distance = model.distanceText(to: pin.coordinate) {
                                            Text(distance).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .glassEffect(.regular.interactive(), in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func nearestPinPerStore(_ pins: [MapPin]) -> [MapPin] {
        let origin = model.userLocation ?? lastLoad?.center
        var best: [Store.ID: (pin: MapPin, meters: Double)] = [:]
        for pin in pins {
            guard let store = pin.store else { continue }
            let meters = origin.map { pin.coordinate.distance(to: $0) } ?? 0
            if meters < best[store.id]?.meters ?? .infinity { best[store.id] = (pin, meters) }
        }
        return best.values.sorted { $0.meters < $1.meters }.map(\.pin)
    }

    private func fly(to point: GeoPoint) {
        withAnimation {
            position = .region(MKCoordinateRegion(center: point.clCoordinate, latitudinalMeters: 900, longitudinalMeters: 900))
        }
    }

    private var searchResultList: some View {
        List(searchResults) { place in
            Button {
                fly(to: place.coordinate)
                selectedPin = model.mapPin(for: place)
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
}

// MARK: - Pins

private struct PinView: View {
    let pin: MapPin
    let openCount: Int
    /// The chain as a store, for suggestion pins.
    let chainStore: Store?

    var body: some View {
        switch pin.kind {
        case .saved(let location):
            if let store = pin.store {
                StoreBadge(store: store, size: location.isPreferred ? 40 : 34)
                    .padding(2)
                    .background(.white, in: .circle)
                    .overlay(alignment: .topTrailing) { CountBadge(count: openCount) }
                    .shadow(radius: 3, y: 1)
            }
        case .branch:
            if let store = pin.store {
                StoreBadge(store: store, size: 30)
                    .shadow(radius: 2, y: 1)
            }
        case .suggestion:
            if let chainStore {
                StoreBadge(store: chainStore, size: 28)
                    .opacity(0.55)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white, Color.accentColor)
                    }
            }
        case .place:
            Image(systemName: "mappin.circle.fill")
                .font(.title)
                .foregroundStyle(.white, .red)
        }
    }
}

private struct CountBadge: View {
    let count: Int

    var body: some View {
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

// MARK: - Sheet

/// Actions for a pin: go to the card, save a branch, add a chain or place as a store, route.
private struct PinSheet: View {
    let pin: MapPin
    /// Called when done; a page means "show this card".
    let onDone: (PageID?) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.store?.name ?? pin.place?.name ?? "").font(.headline)
                    Text([address, model.distanceText(to: pin.coordinate)].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let store = pin.store {
                Text("\(model.openItemCount(of: store.id)) offene Einträge")
                    .foregroundStyle(.secondary)
            }
            actions
                .controlSize(.large)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var address: String? {
        switch pin.kind {
        case .saved(let location): location.address
        case .branch(let place), .suggestion(let place, _), .place(let place): place.address
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let store = pin.store {
            StoreBadge(store: store, size: 44)
        } else if case .suggestion(_, let key) = pin.kind, let chain = model.catalog?.entry(forKey: key) {
            StoreBadge(store: chain.makeStore(sortIndex: 0), size: 44)
        } else {
            Image(systemName: pin.place?.suggestedType.defaultSymbol ?? "mappin")
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: .circle)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch pin.kind {
        case .saved(let location):
            HStack(spacing: 12) {
                if let store = pin.store {
                    Button("Zur Card", systemImage: "rectangle.stack") { onDone(.store(store.id)) }
                        .buttonStyle(.glassProminent)
                }
                routeButton
            }
            if !location.isPreferred {
                Button("Als bevorzugte Filiale", systemImage: "star") {
                    model.setPreferredLocation(location)
                    onDone(nil)
                }
            }
        case .branch(let place):
            if let store = pin.store {
                Button {
                    model.addLocation(place, to: store.id)
                    onDone(nil)
                } label: {
                    Label("Als meine Filiale merken", systemImage: "mappin.and.ellipse").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                HStack(spacing: 12) {
                    Button("Zur Card", systemImage: "rectangle.stack") { onDone(.store(store.id)) }
                        .buttonStyle(.glass)
                    routeButton
                }
            }
        case .suggestion(let place, _), .place(let place):
            Button {
                model.addStore(from: place)
                onDone(nil)
            } label: {
                Label("Als Laden hinzufügen", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            routeButton
        }
    }

    private var routeButton: some View {
        Button("Route", systemImage: "arrow.triangle.turn.up.right.diamond") {
            let name = pin.store?.name ?? pin.place?.name ?? ""
            PlaceResult(name: name, address: address, coordinate: pin.coordinate, mapItemIdentifier: nil, suggestedType: .other).openInMaps()
        }
        .buttonStyle(.glass)
    }
}

extension PlaceResult {
    func openInMaps() {
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
