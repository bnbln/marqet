import MarqetCore
import SwiftUI

/// "Filialen" in a store's details: saved branches (one preferred) and a search nearby (KONZEPT §14.1).
struct BranchPickerSection: View {
    let store: Store
    @Environment(AppModel.self) private var model
    @State private var results: [PlaceResult] = []
    @State private var query = ""
    @State private var isSearching = false
    @State private var message: String?

    var body: some View {
        Section {
            ForEach(model.locations(of: store.id)) { location in
                Button {
                    model.setPreferredLocation(location)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name).foregroundStyle(.primary)
                            Text([location.address, model.distanceText(to: store.id).flatMap { location.isPreferred ? $0 : nil }]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if location.isPreferred {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .swipeActions {
                    Button("Entfernen", systemImage: "trash", role: .destructive) { model.removeLocation(location) }
                }
            }

            Button {
                Task { await searchNearby() }
            } label: {
                HStack {
                    Label("Filialen in der Nähe suchen", systemImage: "location.magnifyingglass")
                    if isSearching { Spacer(); ProgressView() }
                }
            }
            HStack {
                TextField("Oder Ort bzw. Adresse eingeben", text: $query)
                    .submitLabel(.search)
                    .onSubmit { Task { await searchText() } }
            }

            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(results) { place in
                Button {
                    model.addLocation(place, to: store.id)
                    results.removeAll { $0.id == place.id }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).foregroundStyle(.primary)
                            if let address = place.address {
                                Text(address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "plus.circle").foregroundStyle(.tint)
                    }
                }
            }
        } header: {
            Text("Filialen")
        } footer: {
            Text("Die bevorzugte Filiale bestimmt Entfernung, Kartenpunkt und die Adresse auf der Card.")
        }
    }

    private var chain: StoreCatalog.Entry? {
        store.catalogKey.flatMap { model.catalog?.entry(forKey: $0) }
    }

    private func searchNearby() async {
        isSearching = true
        defer { isSearching = false }
        guard let origin = await model.updateUserLocation() else {
            message = String(localized: "Ohne Standortfreigabe kannst du eine Filiale über Ort oder Adresse suchen.")
            return
        }
        do {
            results = try await model.placeSearch.branches(of: store, chain: chain, near: origin)
            message = results.isEmpty ? String(localized: "Keine Filiale in der Nähe gefunden.") : nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func searchText() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            // "Aldi Süd Schwabing" finds branches; a bare address finds the place itself.
            let all = try await model.placeSearch.search("\(chain?.name ?? store.name) \(text)", near: model.userLocation)
            results = chain.map { chain in all.filter { ChainRecognizer.entry(forPlaceNamed: $0.name, in: [chain]) != nil } } ?? all
            message = results.isEmpty ? String(localized: "Nichts gefunden.") : nil
        } catch {
            message = error.localizedDescription
        }
    }
}
