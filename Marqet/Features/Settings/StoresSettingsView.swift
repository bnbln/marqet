import MarqetCore
import SwiftUI

/// "Läden verwalten": order, edit, delete (KONZEPT §7.6, §4.4).
struct StoresSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showsAddStore = false
    @State private var pendingDelete: Store?

    var body: some View {
        List {
            Section {
                ForEach(model.sortedStores) { store in
                    NavigationLink {
                        StoreEditView(store: store)
                    } label: {
                        HStack(spacing: 12) {
                            StoreBadge(store: store, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.name)
                                Text(store.type.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onMove { model.moveStores(from: $0, to: $1) }
                .onDelete { offsets in
                    pendingDelete = offsets.first.map { model.sortedStores[$0] }
                }
            } footer: {
                Text("Die Reihenfolge hier ist die Reihenfolge der Cards.")
            }
            Section {
                Button("Laden hinzufügen", systemImage: "plus") { showsAddStore = true }
            }
        }
        .navigationTitle("Läden")
        .toolbar { EditButton() }
        .sheet(isPresented: $showsAddStore) {
            AddStoreSheet(opensComposer: false)
        }
        .confirmationDialog(
            "\(pendingDelete?.name ?? "") löschen?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { store in
            Button("Löschen", role: .destructive) {
                Task { await model.deleteStore(store.id) }
            }
        } message: { store in
            let count = model.openItemCount(of: store.id)
            Text(count == 0
                 ? "Gelernte Zuordnungen für diesen Laden gehen verloren."
                 : "\(count) offene Einträge landen in der Inbox. Gelernte Zuordnungen für diesen Laden gehen verloren.")
        }
    }
}

/// Name, kind, color, symbol and section order of one store.
struct StoreEditView: View {
    let store: Store

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = StoreType.supermarket
    @State private var colorHex = ""
    @State private var symbol: String?
    @State private var showsSectionOrder = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    StoreBadge(store: preview, size: 52)
                    TextField("Name", text: $name)
                        .font(.title3)
                }
                if model.isNameTaken(name, except: store.id) {
                    Label("Diesen Laden gibt es schon.", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Beim Umbenennen passt Marqet die Zeile „🛒 \(store.name)“ in allen offenen Einträgen an.")
            }

            Section("Art") {
                Picker("Art", selection: $type) {
                    ForEach(StoreType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }

            Section("Farbe") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(([store.colorHex] + StorePalette.colors).uniqued(), id: \.self) { hex in
                        Button { colorHex = hex } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if hex == colorHex { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if case .systemImage = store.symbol {
                Section("Symbol") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(StorePalette.symbols, id: \.self) { name in
                            Button { symbol = name } label: {
                                Image(systemName: name)
                                    .frame(width: 34, height: 34)
                                    .background(name == symbol ? Color(hex: colorHex) : Color(.tertiarySystemFill), in: .circle)
                                    .foregroundStyle(name == symbol ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if type.showsCategorySections {
                Section {
                    Button("Abschnitte sortieren", systemImage: "arrow.up.arrow.down") { showsSectionOrder = true }
                }
            }
        }
        .navigationTitle(store.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || model.isNameTaken(name, except: store.id))
            }
        }
        .sheet(isPresented: $showsSectionOrder) { SectionOrderSheet(store: store) }
        .onAppear {
            name = store.name
            type = store.type
            colorHex = store.colorHex
            if case .systemImage(let current) = store.symbol { symbol = current }
        }
    }

    private var preview: Store {
        var preview = store
        preview.colorHex = colorHex.isEmpty ? store.colorHex : colorHex
        if let symbol { preview.symbol = .systemImage(symbol) }
        return preview
    }

    private func save() {
        model.updateAppearance(of: store.id, colorHex: colorHex, systemImage: symbol, type: type)
        let newName = name
        Task { await model.rename(storeID: store.id, to: newName) }
        dismiss()
    }
}
