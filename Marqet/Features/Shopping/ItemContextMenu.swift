import MarqetCore
import SwiftUI
import UIKit

/// Long-press menu of a shopping item.
///
/// Moving an item to another store is a drag, not a menu tap (the item row is `.draggable`
/// and store cards are drop targets) – the old "Verschieben nach" row of tiny store logos
/// scrolled sideways and its touch targets were too small. Deleting is a swipe action on the
/// row instead of living here, so this menu only holds actions, like Reminders' does.
struct ItemContextMenu: View {
    let item: ShoppingItem
    let onEdit: () -> Void
    let onEditNote: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        ControlGroup {
            Button(item.isCompleted ? "Offen" : "Erledigt",
                   systemImage: item.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle") {
                Task { await model.toggleCompletion(item) }
            }
            Button("Bearbeiten", systemImage: "pencil", action: onEdit)
        }

        Section {
            categoryMenu
            Button(item.userNotes == nil ? "Notiz hinzufügen" : "Notiz bearbeiten",
                   systemImage: "note.text", action: onEditNote)
        }

        Section {
            Button("Kopieren", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = item.title
            }
            ShareLink(item: shareText) {
                Label("Teilen", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: Parts

    private var categoryMenu: some View {
        let current = model.category(of: item)
        return Menu {
            Picker("Kategorie", selection: Binding(
                get: { current },
                set: { model.setCategory($0, for: item) }
            )) {
                ForEach(ItemCategory.allCases, id: \.self) { category in
                    Label(category.displayName, systemImage: category.symbol).tag(category)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Kategorie", systemImage: current.symbol)
            Text(current.displayName)
        }
    }

    private var shareText: String {
        [item.title, item.userNotes].compactMap(\.self).joined(separator: "\n")
    }
}

/// Free-text note of an item; stored above the 🛒 marker line in the reminder's notes.
struct ItemNoteSheet: View {
    let item: ShoppingItem

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("z. B. laktosefrei, 1,5 %", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($isFocused)
                } footer: {
                    Text("Die Notiz steht auch in der Erinnerungen-App.")
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Task { await model.setNotes(text, for: item) }
                        dismiss()
                    }
                }
            }
            .onAppear {
                text = item.userNotes ?? ""
                isFocused = true
            }
        }
        .presentationDetents([.medium])
    }
}
