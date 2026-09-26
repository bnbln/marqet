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
                        }
                    }
                    .onMove { model.moveStores(from: $0, to: $1) }
                    .onDelete { offsets in
                        pendingDelete = offsets.first.map { model.sortedStores[$0] }
                    }
                    Button("Laden hinzufügen", systemImage: "plus") { showsAddStore = true }
                } footer: {
                    Text("Die Reihenfolge hier ist auch die Reihenfolge deiner Ladenkarten.")
                }
            }
            .navigationTitle("Läden sortieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
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
}
