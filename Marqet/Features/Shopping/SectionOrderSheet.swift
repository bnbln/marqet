import MarqetCore
import SwiftUI

/// "Abschnitte sortieren": the order of category sections in one store (KONZEPT §6.4, Free).
/// With Pro route learning, Marqet keeps refining this order from how the user shops.
struct SectionOrderSheet: View {
    let store: Store

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var order: [ItemCategory] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order, id: \.self) { category in
                        Label(category.displayName, systemImage: category.symbol)
                    }
                    .onMove { order.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text(model.isPro && model.routeLearningEnabled
                         ? "Ziehe die Abschnitte in die Reihenfolge deines Wegs durch \(store.name). Marqet lernt beim Abhaken weiter mit."
                         : "Ziehe die Abschnitte in die Reihenfolge deines Wegs durch \(store.name).")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Abschnitte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        model.setCategoryOrder(order, for: store.id)
                        dismiss()
                    }
                }
            }
            .onAppear { order = model.categoryOrder(for: store.id) }
        }
    }
}
