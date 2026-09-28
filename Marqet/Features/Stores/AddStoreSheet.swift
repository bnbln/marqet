import MarqetCore
import SwiftUI

/// "Laden hinzufügen": pick a chain from the catalog or create an own store (KONZEPT §7.8).
struct AddStoreSheet: View {
    private enum Mode: Hashable { case catalog, custom }

    /// Jump to the new store and open the composer (main screen); off inside the triage flow.
    var opensComposer = true

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode = Mode.catalog
    @State private var search = ""
    @State private var lastAdded: Store?
    /// Stores created in this sheet; tapping them again removes them.
    @State private var addedHere: Set<Store.ID> = []

    // Custom store form
    @State private var name = ""
    @State private var type = StoreType.supermarket
    @State private var colorHex = StorePalette.colors[3]
    @State private var symbol = StorePalette.symbols[0]

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                switch mode {
                case .catalog: catalogList
                case .custom: customForm
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Art", selection: $mode) {
                    Text("Katalog").tag(Mode.catalog)
                    Text("Eigener Laden").tag(Mode.custom)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("Laden hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { finish() }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Catalog

    private var catalogList: some View {
        @Bindable var model = model
        return List {
            Section {
                Picker("Region", selection: $model.region) {
                    Text("Deutschland").tag(StoreCatalog.Region.germany)
                    Text("Österreich").tag(StoreCatalog.Region.austria)
                    Text("Schweiz").tag(StoreCatalog.Region.switzerland)
                }
            }
            Section("Online-Shops") {
                ForEach(filteredEntries.filter { $0.type == .online }) { entry in
                    catalogRow(entry)
                }
            }
            Section {
                ForEach(filteredEntries.filter { $0.type != .online }) { entry in
                    catalogRow(entry)
                }
                if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   filteredEntries.isEmpty {
                    Button {
                        name = search.trimmingCharacters(in: .whitespacesAndNewlines)
                        mode = .custom
                    } label: {
                        Label("Eigenen Laden anlegen", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("Läden")
            } footer: {
                Text("Jeder Laden kann als eigener Laden angelegt werden. Marqet steht in keiner Verbindung zu den genannten Handelsketten. Alle Marken gehören ihren jeweiligen Inhabern.")
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Kette suchen")
    }

    private func catalogRow(_ entry: StoreCatalog.Entry) -> some View {
        let added = model.stores.contains { $0.catalogKey == entry.key }
        return Button {
            toggle(entry)
        } label: {
            HStack(spacing: 14) {
                StoreBadge(store: entry.makeStore(sortIndex: 0), size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).foregroundStyle(Color.primary)
                    Text(entry.type.displayName)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(added ? Color.accentColor : Color.secondary)
            }
        }
        .accessibilityValue(added ? "Hinzugefügt" : "")
    }

    private func toggle(_ entry: StoreCatalog.Entry) {
        guard let existing = model.stores.first(where: { $0.catalogKey == entry.key }) else {
            let store = model.addStore(from: entry, planned: opensComposer)
            addedHere.insert(store.id)
            lastAdded = store
            return
        }
        if lastAdded?.id == existing.id { lastAdded = nil }
        if addedHere.remove(existing.id) != nil {
            Task { await model.deleteStore(existing.id) }
        } else {
            model.hide(existing.id)
        }
    }

    private var filteredEntries: [StoreCatalog.Entry] {
        let entries = model.catalog?.entries(for: model.region) ?? []
        let query = ItemKeyNormalizer.storeNameKey(search)
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            ([entry.name] + entry.aliases).contains { ItemKeyNormalizer.storeNameKey($0).contains(query) }
        }
    }

    // MARK: Custom store

    private var customForm: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    StoreBadge(store: previewStore, size: 52)
                    TextField("Name, z. B. Hofladen Maier", text: $name)
                        .font(.title3)
                        .submitLabel(.done)
                }
                if model.isNameTaken(name) {
                    Label("Diesen Laden gibt es schon.", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("Art") {
                Picker("Art", selection: $type) {
                    ForEach(StoreType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: type) { _, new in symbol = new.defaultSymbol }
            }

            Section("Farbe") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(StorePalette.colors, id: \.self) { hex in
                        Button {
                            colorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if hex == colorHex {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Symbol") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                    ForEach(StorePalette.symbols, id: \.self) { name in
                        Button {
                            symbol = name
                        } label: {
                            Image(systemName: name)
                                .font(.body)
                                .frame(width: 34, height: 34)
                                .background(name == symbol ? Color(hex: colorHex) : Color(.tertiarySystemFill), in: .circle)
                                .foregroundStyle(name == symbol ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button("Laden anlegen") {
                    lastAdded = model.addCustomStore(name: name, type: type, colorHex: colorHex, systemImage: symbol)
                    finish()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || model.isNameTaken(name))
            }
        }
    }

    private var previewStore: Store {
        Store(name: name, colorHex: colorHex, symbol: .systemImage(symbol), sortIndex: 0, origin: .custom, type: type)
    }

    /// Jump to the last added store and open the composer there.
    private func finish() {
        dismiss()
        if opensComposer, let lastAdded {
            model.startComposer(on: .store(lastAdded.id))
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        AddStoreSheet()
            .environment(AppModel.preview(stores: ["lidl"]))
    }
}
