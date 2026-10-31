import MapKit
import MarqetCore
import SwiftUI

/// "Meine Läden" always: saved branches prominent, other branches of own stores and shops the user
/// does not have (catalog chains, Apple Maps) muted. "Nur meine Läden" hides the shops.
struct MapScreen: View {
    let focusedStoreID: Store.ID?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Places found around the visible area: branches of stores with open list items.
    @State private var found: [PlaceResult] = []
    @State private var discovered: [PlaceResult] = []
    @State private var lastLoad: (center: GeoPoint, radius: Double)?
    @State private var loadTask: Task<Void, Never>?
    @State private var query = ""
    @State private var searchResults: [PlaceResult] = []
    @State private var selectedPin: MapPin?
    @State private var isLoading = false
    @State private var shouldFrameDiscovery = true
    /// Pins for the current data, rebuilt only when places, stores or items change – matching
    /// hundreds of places against the catalog on every frame made the map sluggish.
    @State private var pins: [MapPin] = []
    @State private var openCounts: [Store.ID: Int] = [:]
    /// Suggestion pins show the chain as a store; built once per chain.
    @State private var chainStores: [String: Store] = [:]
    /// Single pins and cluster bubbles for the visible area.
    @State private var markers: [MapMarker] = []
    @State private var visibleRect: MKMapRect?
    @State private var mapWidth: CGFloat = 390
    @State private var selection: String?
    /// Zoomed out beyond a city: no searches, only what is already known (in clusters).
    @State private var isTooFarOut = false
    /// `false` (default): own stores plus muted shops around them. A new key on purpose – the old
    /// "Läden mit Einträgen" default hid even saved branches of stores with an empty list.
    @AppStorage("mapShowsOnlyMyStores") private var showsOnlyMyStores = false
    @AppStorage("mapShopCategory") private var shopCategory: NearbyShopCategory = .groceries

    private static let initialRadius: Double = 2_500
    /// Above this radius the map stops searching for shops (MapKit results get meaningless).
    private static let maximumLoadRadius: Double = 12_000

    init(focusedStoreID: Store.ID? = nil) {
        self.focusedStoreID = focusedStoreID
    }

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selection) {
                UserAnnotation()
                ForEach(markers) { marker in
                    switch marker {
                    case .pin(let pin):
                        // No buttons inside annotations: MapKit's own selection keeps pinch and
                        // pan working when a finger lands on a pin.
                        Annotation(title(of: pin), coordinate: pin.coordinate.clCoordinate) {
                            // Annotation content does not inherit the environment – pass what the pin shows.
                            PinView(pin: pin, openCount: pin.store.map { openCounts[$0.id] ?? 0 } ?? 0, chainStore: chainStore(of: pin),
                                    isMuted: isMuted(pin))
                        }
                        .annotationTitles(showsTitle(of: pin) ? .automatic : .hidden)
                        .tag(marker.id)
                    case .cluster(let cluster):
                        Annotation("", coordinate: cluster.coordinate.clCoordinate) {
                            ClusterView(stores: clusterStores(cluster), count: cluster.pins.count)
                        }
                        .annotationTitles(.hidden)
                        .tag(marker.id)
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { mapWidth = $0 }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRect = context.rect
                rebuildMarkers()
                let region = context.region
                let radius = min(region.span.latitudeDelta * 111_000, region.span.longitudeDelta * 111_000 * cos(region.center.latitude * .pi / 180)) / 2
                isTooFarOut = radius > Self.maximumLoadRadius
                guard !isTooFarOut else { return }
                scheduleLoad(center: GeoPoint(latitude: region.center.latitude, longitude: region.center.longitude), radius: radius)
            }
            .onChange(of: pinInputs, initial: true) { rebuildPins() }
            .onChange(of: pins) { rebuildMarkers() }
            .onChange(of: mapWidth) { rebuildMarkers() }
            .onChange(of: selection) { _, id in
                guard let id else { return }
                selection = nil
                switch markers.first(where: { $0.id == id }) {
                case .pin(let pin): selectedPin = pin
                case .cluster(let cluster): withAnimation(.smooth) { position = .rect(cluster.zoomRect) }
                case nil: break
                }
            }
            .overlay(alignment: .top) {
                if !searchResults.isEmpty {
                    searchResultList
                } else if isTooFarOut {
                    Label("Zoome näher heran, um Geschäfte zu laden", systemImage: "plus.magnifyingglass")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
            .animation(.snappy, value: isTooFarOut)
            #if DEBUG
            .overlay(alignment: .topLeading) {
                // Not in App Store screenshots (scripts/screenshots passes `-screenshots`).
                if ProcessInfo.processInfo.arguments.contains("-demo-map"),
                   !ProcessInfo.processInfo.arguments.contains("-screenshots") {
                    Text("mine=\(showsOnlyMyStores) category=\(shopCategory.rawValue) found=\(found.count) shops=\(discovered.count) pins=\(pins.count) markers=\(markers.count)")
                        .font(.caption2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(5)
                        .background(.yellow)
                }
            }
            #endif
            .safeAreaInset(edge: .bottom) {
                storeStrip(pins: pins)
            }
            .searchable(text: $query, prompt: "Laden oder Adresse suchen")
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: query) { _, text in if text.isEmpty { searchResults = [] } }
            .navigationTitle("In der Nähe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Schließen")
                }
                ToolbarItem(placement: .primaryAction) { filterMenu }
                if isLoading {
                    ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                }
            }
            .task {
                let origin = await model.updateUserLocation()
                if let focusedStoreID, let location = model.relevantLocation(of: focusedStoreID) {
                    // Stay on the store's branch instead of framing the shops found around it.
                    shouldFrameDiscovery = false
                    fly(to: location.coordinate)
                    scheduleLoad(center: location.coordinate, radius: Self.initialRadius, immediately: true)
                } else if let origin {
                    scheduleLoad(center: origin, radius: Self.initialRadius, immediately: true)
                }
            }
            .onChange(of: showsOnlyMyStores) {
                found = []
                discovered = []
                shouldFrameDiscovery = true
                guard let lastLoad, !isTooFarOut else { return }
                scheduleLoad(center: lastLoad.center, radius: lastLoad.radius, immediately: true)
            }
            .onChange(of: shopCategory) {
                found = []
                discovered = []
                shouldFrameDiscovery = true
                guard !showsOnlyMyStores, let lastLoad, !isTooFarOut else { return }
                scheduleLoad(center: lastLoad.center, radius: lastLoad.radius, immediately: true)
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
            }
        }
        .tint(Color(uiColor: .label))
    }

    // MARK: Pins

    /// Everything the pins depend on; the pins are rebuilt only when this changes.
    private var pinInputs: PinInputs {
        PinInputs(
            found: found,
            discovered: discovered,
            showsOnlyMyStores: showsOnlyMyStores,
            shopCategory: shopCategory,
            locations: model.locations,
            stores: model.stores.map(\.id),
            openCounts: Dictionary(model.items.lazy.filter { !$0.isCompleted }.compactMap(\.storeID).map { ($0, 1) }, uniquingKeysWith: +)
        )
    }

    private struct PinInputs: Equatable {
        let found: [PlaceResult]
        let discovered: [PlaceResult]
        let showsOnlyMyStores: Bool
        let shopCategory: NearbyShopCategory
        let locations: [StoreLocation]
        let stores: [Store.ID]
        let openCounts: [Store.ID: Int]
    }

    private func rebuildPins() {
        let inputs = pinInputs
        openCounts = inputs.openCounts
        var chains = chainStores
        pins = model.mapPins(found: found + discovered, includeUnmatched: !showsOnlyMyStores).filter { pin in
            // Own stores always show, whatever the shop category.
            if pin.store != nil { return true }
            if showsOnlyMyStores { return false }
            if case .suggestion(_, let key) = pin.kind, let chain = model.catalog?.entry(forKey: key) {
                if chains[key] == nil { chains[key] = chain.makeStore(sortIndex: 0) }
                return shopCategory.includes(chain.type)
            }
            return true
        }
        chainStores = chains
    }

    private func rebuildMarkers() {
        guard let visibleRect else {
            markers = pins.map(MapMarker.pin)
            return
        }
        markers = MapClustering.markers(for: pins, in: visibleRect, viewWidth: mapWidth)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Anzeigen", selection: $showsOnlyMyStores) {
                Label("Meine Läden und Geschäfte", systemImage: "storefront").tag(false)
                Label("Nur meine Läden", systemImage: "star").tag(true)
            }
            Picker("Geschäfte", selection: $shopCategory) {
                ForEach(NearbyShopCategory.allCases, id: \.self) { category in
                    Text(category.title).tag(category)
                }
            }
            .disabled(showsOnlyMyStores)
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
        }
        .accessibilityValue(showsOnlyMyStores ? String(localized: "Nur meine Läden") : shopCategory.title)
    }

    private func title(of pin: MapPin) -> String {
        pin.store?.name ?? pin.place?.name ?? ""
    }

    private func chainStore(of pin: MapPin) -> Store? {
        guard case .suggestion(_, let key) = pin.kind else { return nil }
        return chainStores[key]
    }

    /// Everything that is not a saved branch of an own store recedes: other branches of a store
    /// that already has a saved one (another Rewe next to the favourite), and shops the user does
    /// not have. A store without any saved branch shows its found branches in full.
    private func isMuted(_ pin: MapPin) -> Bool {
        switch pin.kind {
        case .saved, .place: false
        case .suggestion: true
        case .branch: pin.store.map { !model.locations(of: $0.id).isEmpty } ?? true
        }
    }

    /// Names only for own branches and search results – dozens of labels would cover the map.
    private func showsTitle(of pin: MapPin) -> Bool {
        switch pin.kind {
        case .saved, .place: true
        case .branch, .suggestion: false
        }
    }

    /// Up to three different stores for the bubble's badges, own stores first.
    private func clusterStores(_ cluster: MapCluster) -> [Store] {
        var seen = Set<String>()
        let own = cluster.pins.compactMap(\.store)
        let chains = cluster.pins.compactMap(chainStore(of:))
        return Array((own + chains).filter { seen.insert($0.catalogKey ?? $0.id.uuidString).inserted }.prefix(3))
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
        if !showsOnlyMyStores {
            let shops = (try? await model.placeSearch.shops(near: center, category: shopCategory)) ?? []
            guard !Task.isCancelled else { return }
            discovered = shops
            if shouldFrameDiscovery, !shops.isEmpty {
                shouldFrameDiscovery = false
                let furthest = shops.map { center.distance(to: $0.coordinate) }.max() ?? 0
                let span = min(max(furthest * 2.4, 1_500), 6_500)
                withAnimation(.smooth) {
                    position = .region(MKCoordinateRegion(center: center.clCoordinate, latitudinalMeters: span, longitudinalMeters: span))
                }
            }
        }
        var results: [PlaceResult] = []
        for store in model.storesForBranchSearch(onlyWithItems: false) {
            guard !Task.isCancelled else { return }
            let chain = store.catalogKey.flatMap { model.catalog?.entry(forKey: $0) }
            results += (try? await model.placeSearch.branches(of: store, chain: chain, near: center, radius: radius)) ?? []
        }
        guard !Task.isCancelled else { return }
        // Keep what was found nearby, so panning back does not empty the map – but not the
        // whole city: far away places only cost layout time.
        let keepRadius = max(radius * 4, 15_000)
        var seen = Set(results.map(\.id))
        found = results + found.filter { seen.insert($0.id).inserted && $0.coordinate.distance(to: center) < keepRadius }
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

    /// Stores with open list items, nearest branch first, with distance – tap to fly there.
    @ViewBuilder
    private func storeStrip(pins: [MapPin]) -> some View {
        // Only stores with something to buy: the strip is the shopping route, not a store list.
        let nearest = nearestPinPerStore(pins.filter { pin in pin.store.map { (openCounts[$0.id] ?? 0) > 0 } ?? false })
        if !nearest.isEmpty {
            let routeStops = model.shoppingRouteStops(from: pins)
            let routeURL = model.mapsRouteURL(for: routeStops)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    if let routeURL {
                        Button {
                            openURL(routeURL)
                        } label: {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 40, height: 40)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(routeStops.count == 1 ? "Route zu 1 Laden" : "Route zu \(routeStops.count) Läden")
                    }
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
            .padding(.bottom, 6)
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
    /// Not one of the user's saved branches: smaller and faded, so own stores stand out.
    let isMuted: Bool

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
                StoreBadge(store: store, size: isMuted ? 24 : 30)
                    .opacity(isMuted ? 0.55 : 1)
                    .overlay(alignment: .topTrailing) { if !isMuted { CountBadge(count: openCount) } }
                    .shadow(radius: isMuted ? 0 : 2, y: 1)
            }
        case .suggestion:
            if let chainStore {
                StoreBadge(store: chainStore, size: 24)
                    .opacity(0.45)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white, Color.primary)
                    }
            }
        case .place:
            Image(systemName: "mappin.circle.fill")
                .font(.title)
                .foregroundStyle(.white, .red)
        }
    }
}

/// Several shops close together: their badges stacked, and how many there are.
private struct ClusterView: View {
    let stores: [Store]
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: -12) {
                ForEach(stores) { store in
                    StoreBadge(store: store, size: 26)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                }
            }
            Text("\(count)")
                .font(.subheadline.bold())
                .monospacedDigit()
                .foregroundStyle(Color(uiColor: .label))
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(Color(uiColor: .systemBackground), in: .capsule)
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) Geschäfte")
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
/// Opaque and sized to its content, so nothing of the map shows through the text.
private struct PinSheet: View {
    let pin: MapPin
    /// Called when done; a page means "show this card".
    let onDone: (PageID?) -> Void
    @Environment(AppModel.self) private var model
    @State private var height: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            facts
            if let store = pin.store, !isOwnBranch { itemPreview(of: store) }
            VStack(spacing: 10) { actions }
                .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(height)])
        .presentationBackground(Color(.systemBackground))
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            badge
            VStack(alignment: .leading, spacing: 3) {
                Text(kindLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(accentText)
                Text(name)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Button { onDone(nil) } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Schließen")
        }
    }

    /// Address and distance on their own lines – the address may be long, the distance never is.
    private var facts: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let address {
                Label(address, systemImage: "mappin.and.ellipse")
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 8) {
                if let distance = model.distanceText(to: pin.coordinate) {
                    Chip(text: Text(distance), symbol: "location.fill")
                }
                if case .saved(let location) = pin.kind, location.isPreferred {
                    Chip(text: Text("Bevorzugt"), symbol: "star.fill")
                }
                if let store = pin.store {
                    let count = model.openItemCount(of: store.id)
                    Chip(text: count == 1 ? Text("1 offener Eintrag") : Text("\(count) offene Einträge"), symbol: "checklist")
                }
            }
        }
        .font(.subheadline)
        .labelStyle(FactLabelStyle())
    }

    /// The first open items, so the sheet answers "what do I need here?".
    @ViewBuilder
    private func itemPreview(of store: Store) -> some View {
        let open = model.items.filter { !$0.isCompleted && $0.storeID == store.id }
        if !open.isEmpty {
            let shown = open.prefix(4).map(\.title).joined(separator: ", ")
            let rest = open.count - min(open.count, 4)
            Text(rest > 0 ? "\(shown) und \(rest) weitere" : shown)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let store = shownStore {
            StoreBadge(store: store, size: 52)
        } else {
            Image(systemName: pin.place?.suggestedType.defaultSymbol ?? "mappin")
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .background(Color(.tertiarySystemFill), in: .circle)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        switch pin.kind {
        case .saved(let location):
            if let store = pin.store {
                primaryButton("Zur Card", symbol: "rectangle.stack") { onDone(.store(store.id)) }
            }
            HStack(spacing: 10) {
                routeButton
                if !location.isPreferred {
                    secondaryButton("Bevorzugen", symbol: "star") {
                        model.setPreferredLocation(location)
                        onDone(nil)
                    }
                }
            }
        case .branch(let place):
            if let store = pin.store {
                primaryButton("Als meine Filiale merken", symbol: "mappin.and.ellipse") {
                    model.addLocation(place, to: store.id)
                    onDone(nil)
                }
                HStack(spacing: 10) {
                    secondaryButton("Zur Card", symbol: "rectangle.stack") { onDone(.store(store.id)) }
                    routeButton
                }
            }
        case .suggestion(let place, _), .place(let place):
            primaryButton("Als Laden hinzufügen", symbol: "plus") {
                model.addStore(from: place)
                onDone(nil)
            }
            routeButton
        }
    }

    private func primaryButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(onAccent)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(accent)
    }

    private func secondaryButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
    }

    private var routeButton: some View {
        secondaryButton("Route", symbol: "arrow.triangle.turn.up.right.diamond") {
            PlaceResult(name: name, address: address, coordinate: pin.coordinate, mapItemIdentifier: nil, suggestedType: .other).openInMaps()
        }
    }

    // MARK: Data

    private var name: String {
        pin.store?.name ?? pin.place?.name ?? ""
    }

    private var address: String? {
        switch pin.kind {
        case .saved(let location): location.address
        case .branch(let place), .suggestion(let place, _), .place(let place): place.address
        }
    }

    private var kindLabel: LocalizedStringKey {
        switch pin.kind {
        case .saved: "Deine Filiale"
        case .branch: "Filiale in der Nähe"
        case .suggestion: "Noch nicht in deinen Läden"
        case .place: "Ort"
        }
    }

    private var isOwnBranch: Bool {
        if case .saved = pin.kind { true } else { false }
    }

    /// The own store, or the chain as a store for suggestions.
    private var shownStore: Store? {
        if let store = pin.store { return store }
        guard case .suggestion(_, let key) = pin.kind else { return nil }
        return model.catalog?.entry(forKey: key)?.makeStore(sortIndex: 0)
    }

    private var accent: Color { shownStore?.color ?? .accentColor }
    private var onAccent: Color { shownStore?.foregroundOnColor ?? .white }
    private var accentText: Color { shownStore?.readableColor ?? .secondary }
}

private struct Chip: View {
    let text: Text
    let symbol: String

    var body: some View {
        Label { text } icon: { Image(systemName: symbol) }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemFill), in: .capsule)
    }
}

/// Icon in secondary colour, text in full contrast.
private struct FactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
                .foregroundStyle(.secondary)
                .imageScale(.small)
            configuration.title
        }
    }
}

extension PlaceResult {
    func openInMaps() {
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
