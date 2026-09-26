import MarqetCore
import MarqetPersistence
import MarqetReminders
import SwiftUI

/// Picks the Reminders list Marqet works with (KONZEPT §7.5, step 3).
struct ListPickerView: View {
    /// Inside onboarding or settings: no own navigation stack, and `onSelected` continues the flow.
    var embedded = false
    var onSelected: (() -> Void)?

    @Environment(AppModel.self) private var model

    var body: some View {
        if embedded {
            list
        } else {
            NavigationStack { list }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(sortedLists) { list in
                    Button {
                        Task { await model.selectList(list.id) }
                    } label: {
                        ListRow(list: list, isSelected: list.id == model.selectedListID)
                    }
                    .disabled(!list.allowsModifications)
                }
                Button {
                    Task { await model.createShoppingList() }
                } label: {
                    Label("Neue Liste anlegen", systemImage: "plus")
                        .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Einkaufsliste")
        .safeAreaInset(edge: .bottom) {
            if embedded {
                Button("Weiter") { onSelected?() }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(model.selectedListID == nil)
                    .padding(20)
            }
        }
    }

    private var sortedLists: [ReminderList] {
        model.lists.sorted { lhs, rhs in
            let lhsLikely = ShoppingListHeuristics.isLikelyShoppingList(lhs.title)
            let rhsLikely = ShoppingListHeuristics.isLikelyShoppingList(rhs.title)
            if lhsLikely != rhsLikely { return lhsLikely }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}

private struct ListRow: View {
    let list: ReminderList
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: list.colorHex ?? "#8E8E93"))
                .frame(width: 14, height: 14)
            Text(list.title)
                .foregroundStyle(Color.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Ausgewählt")
            }
        }
    }
}

#Preview {
    let gateway = InMemoryReminderGateway()
    let model = AppModel(gateway: gateway, container: try! PersistenceContainer.make(inMemory: true), intelligence: UnavailableIntelligence())
    ListPickerView()
        .environment(model)
        .task {
            await gateway.seed(listTitle: "Einkaufsliste", reminders: [])
            await gateway.seed(listTitle: "Arbeit", reminders: [])
            await model.refreshPhase()
        }
}
