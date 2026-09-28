import MarqetCore
import SwiftUI

struct StoreOrderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showsAddStore = false
    @State private var pendingDelete: Store?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.sortedStores) { store in
                        HStack(spacing: 12) {
                            StoreBadge(store: store, size: 32)
                            Text(store.name)
                            Spacer(minLength: 0)
                            // Always visible: the rows can be dragged right away, without an edit mode.
                            Image(systemName: "line.3.horizontal")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    // Applies at once: Home reorders behind the sheet while the user drags.
                    .onMove { model.moveStores(from: $0, to: $1) }
                    .onDelete { offsets in
                        pendingDelete = offsets.first.map { model.sortedStores[$0] }
                    }
                    Button("Laden hinzufügen", systemImage: "plus") { showsAddStore = true }
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle("Läden sortieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                }
            }
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var footer: LocalizedStringKey {
        switch model.storeSortMode {
        case .manual:
            "Halten und ziehen ändert die Reihenfolge deiner Ladenkarten, nach links wischen löscht."
        case .distance, .smart:
            "Deine Ladenkarten sind gerade nach \(model.storeSortMode.title) sortiert. Sobald du hier ziehst, gilt deine eigene Reihenfolge."
        }
    }
}
