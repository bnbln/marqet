import MarqetCore
import SwiftUI
import UIKit

/// Long-press menu of a shopping item.
///
/// iOS shows at most three labelled actions in the top row of a context menu (four without
/// labels), too few for the stores. So the top row holds the main actions, like Reminders,
/// and the stores follow directly below as a scrollable row of logos – one tap to move.
struct ItemContextMenu: View {
    let item: ShoppingItem
    let onEdit: () -> Void
    let onEditNote: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ControlGroup {
            Button(item.isCompleted ? "Offen" : "Erledigt",
                   systemImage: item.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle") {
                Task { await model.toggleCompletion(item) }
            }
            Button("Bearbeiten", systemImage: "pencil", action: onEdit)
            Button(role: .destructive) {
                Task { await model.delete(item) }
            } label: {
                // The top row draws symbols as templates; only an original-mode image stays red.
                Label { Text("Löschen") } icon: { Self.redTrash }
            }
        }

        if !deckTargets.isEmpty || item.storeID != nil {
            Section {
                ControlGroup {
                    ForEach(deckTargets) { store in
                        Button { move(to: store) } label: {
                            Label { Text(store.name) } icon: { badge(store) }
                        }
                    }
                    if item.storeID != nil {
                        Button("Inbox", systemImage: "tray") { move(to: nil) }
                    }
                } label: {
                    Text("Verschieben nach")
                }
                .controlGroupStyle(.palette)
            }
        }

        Section {
            if !hiddenTargets.isEmpty {
                Menu("Weitere Läden", systemImage: "storefront") {
                    ForEach(hiddenTargets) { store in
                        Button { move(to: store) } label: {
                            Label { Text(store.name) } icon: { badge(store) }
                        }
                    }
                }
            }
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

    private static let redTrash: Image = {
        let symbol = UIImage(systemName: "trash")?.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
        return symbol.map(Image.init(uiImage:)) ?? Image(systemName: "trash")
    }()

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

    /// Menus only take images, so the badge is rendered to a bitmap that keeps its colours.
    private func badge(_ store: Store) -> Image {
        let renderer = ImageRenderer(content: StoreBadge(store: store, size: 30))
        renderer.scale = displayScale
        guard let image = renderer.uiImage else { return Image(systemName: "storefront") }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
    }

    // MARK: Targets

    /// Stores with a card in the pager, in card order; the suggested store comes first.
    private var deckTargets: [Store] {
        let targets = model.deck.pages.compactMap { page -> Store? in
            guard case .store(let id) = page, id != item.storeID else { return nil }
            return model.store(id)
        }
        guard let suggested = model.suggestion(for: item)?.storeID,
              let index = targets.firstIndex(where: { $0.id == suggested }) else { return targets }
        var ordered = targets
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }

    private var hiddenTargets: [Store] {
        model.hiddenStores.filter { $0.id != item.storeID }
    }

    private var shareText: String {
        [item.title, item.userNotes].compactMap(\.self).joined(separator: "\n")
    }

    private func move(to store: Store?) {
        Task { await model.assign(item, to: store) }
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
