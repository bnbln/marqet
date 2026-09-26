import MarqetCore
import SwiftUI

/// One store (or the unsorted bucket) as a tall card (KONZEPT §7.2).
struct StoreCard: View {
    let page: PageID
    /// `nil` for the unsorted card.
    let store: Store?
    let items: [ShoppingItem]
    let state: StoreCardState?
    var isFocused = false

    @Environment(AppModel.self) private var model
    @State private var showsCompleted = false
    @State private var renaming: ShoppingItem?
    @State private var renameText = ""
    @State private var showsSectionOrder = false

    private var tint: Color { store?.color ?? .gray }

    var body: some View {
        VStack(spacing: 0) {
            header
            if items.isEmpty && !showsCompleted {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                itemList
            }
        }
        .cardSurface(isFocused: isFocused, focusColor: tint)
        // Items dragged from another card move to this store (KONZEPT-DUO-IPAD §4.2).
        .dropDestination(for: String.self) { ids, _ in
            let moved = model.items.filter { ids.contains($0.id) && $0.storeID != store?.id }
            guard !moved.isEmpty else { return false }
            Task { for item in moved { await model.assign(item, to: store) } }
            return true
        }
        .sheet(isPresented: $showsSectionOrder) {
            if let store { SectionOrderSheet(store: store).leadingSheetPlacement() }
        }
        .alert("Umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Titel", text: $renameText)
            Button("Abbrechen", role: .cancel) {}
            Button("Sichern") {
                if let renaming { Task { await model.rename(renaming, to: renameText) } }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            if let store {
                StoreBadge(store: store, size: 44)
                    .overlay(Circle().strokeBorder(store.foregroundOnColor.opacity(0.35), lineWidth: 1.5))
            } else {
                Image(systemName: "tray.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.2), in: .circle)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(store?.name ?? String(localized: "Unsortiert"))
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .opacity(0.85)
            }
            Spacer(minLength: 0)
            if let store {
                cardMenu(for: store)
            }
        }
        .foregroundStyle(store?.foregroundOnColor ?? .white)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background {
            LinearGradient(colors: [tint, tint.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var subtitle: String {
        let open = items.filter { !$0.isCompleted }.count
        if store == nil { return String(localized: "\(open) ohne Laden") }
        switch state {
        case .shoppedEmpty: return String(localized: "Alles erledigt")
        case .planned where open == 0: return String(localized: "Geplant")
        default: return String(localized: "\(open) offen")
        }
    }

    private func cardMenu(for store: Store) -> some View {
        Menu {
            Button("Eintrag hinzufügen", systemImage: "plus") { model.startComposer(on: page) }
            if store.type.showsCategorySections {
                Button("Abschnitte sortieren", systemImage: "arrow.up.arrow.down") { showsSectionOrder = true }
            }
            if items.isEmpty {
                Button("Aus Übersicht entfernen", systemImage: "eye.slash") { model.hide(store.id) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.22), in: .circle)
        }
        .accessibilityLabel("Laden-Optionen")
    }

    // MARK: Items

    private var itemList: some View {
        ScrollViewReader { proxy in
            List {
                if store == nil, !items.isEmpty {
                    triageButton
                }
                // Category sections in walking order for grocery stores, one flat list otherwise (KONZEPT §6.3).
                ForEach(model.sections(for: page, items: items)) { section in
                    Section {
                        ForEach(section.items) { item in
                            ItemRow(item: item, tint: tint, onRename: {
                                renameText = item.title
                                renaming = item
                            })
                            .id(item.id)
                        }
                    } header: {
                        if let category = section.category {
                            Label(category.displayName, systemImage: category.symbol)
                                .font(.footnote.weight(.semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(tint)
                        }
                    }
                }
                completedSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // No keyboard dismissal on scroll here: the scroll to a new item would close the composer.
            .onChange(of: items.count) { old, new in
                // Newly added items appear at the bottom – keep them in view while typing.
                if new > old, model.composerTarget == page, let last = items.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    /// Entry into the triage flow from the unsorted card (KONZEPT §7.4).
    private var triageButton: some View {
        Button {
            model.startTriage()
        } label: {
            Label("Läden zuordnen", systemImage: "tray.and.arrow.down.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.gray)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var completedSection: some View {
        let completed = model.recentlyCompleted.filter { $0.storeID == store?.id && !items.contains($0) }
        Section {
            if showsCompleted {
                ForEach(completed) { item in
                    Button {
                        Task { await model.restore(item) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(tint.opacity(0.6))
                            Text(item.title)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "arrow.uturn.backward")
                                .foregroundStyle(.tertiary)
                                .accessibilityLabel("Nochmal kaufen")
                        }
                    }
                    .buttonStyle(.plain)
                }
                if completed.isEmpty {
                    Text("In den letzten 7 Tagen nichts erledigt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Button(showsCompleted ? "Erledigte ausblenden" : "Erledigte anzeigen") {
                showsCompleted.toggle()
                if showsCompleted { Task { await model.loadRecentlyCompleted() } }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
        }
        .listRowSeparator(.hidden)
    }

    // MARK: Empty states (KONZEPT §7.2 lifecycle)

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            switch state {
            case .shoppedEmpty:
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(tint)
                Text("Alles erledigt bei \(store?.name ?? "")")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                if let store {
                    Button("Ausblenden") { model.hide(store.id) }
                        .buttonStyle(.bordered)
                        .tint(tint)
                }
            case .planned:
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(tint)
                Text("Noch leer")
                    .font(.title3.bold())
                Text("Tippe auf +, um etwas für \(store?.name ?? "") hinzuzufügen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Eintrag hinzufügen", systemImage: "plus") { model.startComposer(on: page) }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            default:
                Image(systemName: store == nil ? "tray" : "cart")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text(store == nil ? "Alles zugeordnet" : "Leer")
                    .font(.title3.bold())
                if let store {
                    Button("Ausblenden") { model.hide(store.id) }
                        .buttonStyle(.bordered)
                }
            }
            Button("Erledigte anzeigen") {
                showsCompleted = true
                Task { await model.loadRecentlyCompleted() }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        }
        .padding(24)
    }
}

/// A shopping item row, Reminders-style: circle to check off, 1.5 s undo window.
struct ItemRow: View {
    let item: ShoppingItem
    let tint: Color
    var onRename: () -> Void = {}

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Task { await model.toggleCompletion(item) }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isCompleted ? tint : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.isCompleted ? "Erledigt, tippen zum Rückgängigmachen" : "Abhaken")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                if let notes = item.userNotes {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .animation(.snappy, value: item.isCompleted)
        .sensoryFeedback(.impact(weight: .light), trigger: item.isCompleted)
        .draggable(item.id)
        .contextMenu {
            Menu("Laden ändern", systemImage: "storefront") {
                Button("Unsortiert", systemImage: item.storeID == nil ? "checkmark" : "tray") {
                    Task { await model.assign(item, to: nil) }
                }
                ForEach(model.stores.sorted { $0.sortIndex < $1.sortIndex }) { store in
                    Button(store.name, systemImage: item.storeID == store.id ? "checkmark" : "circle.fill") {
                        Task { await model.assign(item, to: store) }
                    }
                    .tint(store.color)
                }
            }
            Menu("Kategorie ändern", systemImage: "square.grid.2x2") {
                let current = model.category(of: item)
                ForEach(ItemCategory.allCases, id: \.self) { category in
                    Button(category.displayName, systemImage: category == current ? "checkmark" : category.symbol) {
                        model.setCategory(category, for: item)
                    }
                }
            }
            Button("Umbenennen", systemImage: "pencil", action: onRename)
            Button("Löschen", systemImage: "trash", role: .destructive) {
                Task { await model.delete(item) }
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Löschen", systemImage: "trash", role: .destructive) {
                Task { await model.delete(item) }
            }
        }
    }
}
