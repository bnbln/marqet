import MarqetCore
import SwiftUI

struct StoreOrderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

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
                } footer: {
                    Text("Die Reihenfolge hier ist auch die Reihenfolge deiner Ladenkarten.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Läden sortieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
