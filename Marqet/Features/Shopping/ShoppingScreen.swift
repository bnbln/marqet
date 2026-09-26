import MarqetCore
import SwiftUI

/// Main screen: the store card pager (KONZEPT §7.2) with the add button and the composer.
struct ShoppingScreen: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppAccentPalette.storageKey) private var accentPaletteKey = AppAccentPalette.leaf.rawValue
    @State private var showsAddStore = false
    @State private var showsSettings = false
    @State private var showsNewListPrompt = false
    @State private var newListName = ""
    @State private var isComposerFocused = false

    private var accentColor: Color {
        AppAccentPalette(rawValue: accentPaletteKey)?.color ?? AppAccentPalette.leaf.color
    }

    var body: some View {
        NavigationStack {
            StorePager()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .overlay(alignment: .bottom) {
                    if model.composerTarget == nil {
                        bottomControls
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if model.composerTarget != nil {
                        ComposerBar(isFocused: $isComposerFocused, showsAddStore: $showsAddStore)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: model.composerTarget == nil)
                .navigationTitle("Marqet")
                .navigationSubtitle(model.selectedList?.title ?? "Liste wählen")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbar }
                .toolbarVerticalCompressionPreferringItems()
                .tint(accentColor)
                .sheet(isPresented: $showsAddStore) {
                    AddStoreSheet()
                        .leadingSheetPlacement()
                }
                .sheet(isPresented: $showsSettings) {
                    SettingsView()
                }
                .alert("Neue Liste anlegen", isPresented: $showsNewListPrompt) {
                    TextField("Listenname", text: $newListName)
                    Button("Abbrechen", role: .cancel) {}
                    Button("Erstellen") {
                        Task { await model.createShoppingList(named: newListName) }
                    }
                    .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .sheet(isPresented: triagePromptBinding) {
                    if let ids = model.triagePrompt { TriagePromptSheet(itemIDs: ids) }
                }
                .fullScreenCover(isPresented: triageBinding) {
                    TriageScreen()
                }
                .overlay(alignment: .top) {
                    if model.autoAssignReport != nil { AutoAssignToast() }
                }
                .animation(.snappy, value: model.autoAssignReport)
                .onChange(of: model.composerTarget) { _, target in
                    if target != nil { isComposerFocused = true }
                }
                .onChange(of: isComposerFocused) { _, focused in
                    if !focused, model.composerTarget != nil { model.endComposer() }
                }
        }
    }

    private var bottomControls: some View {
        HStack(spacing: 14) {
            PageIndicator()
                .glassEffect(.regular, in: .capsule)
            Spacer(minLength: 0)
            Menu {
                Section("Hinzufügen zu …") {
                    Button("Unsortiert", systemImage: "tray") { model.startComposer(on: .unsorted) }
                    ForEach(model.sortedStores) { store in
                        Button(store.name) { model.startComposer(on: .store(store.id)) }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.bold))
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            } primaryAction: {
                model.startComposer(on: model.deck.pages.contains(model.activePage) ? model.activePage : .unsorted)
            }
            .menuStyle(.button)
            .buttonStyle(.glassProminent)
            .accessibilityLabel("Eintrag hinzufügen")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    // System navigation and settings items remain available in the iPhone Duo vertical bar.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Einstellungen", systemImage: "gearshape") { showsSettings = true }
        }

        ToolbarTitleMenu {
            Section("Listen") {
                ForEach(model.lists.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { list in
                    Button {
                        Task { await model.selectList(list.id) }
                    } label: {
                        if list.id == model.selectedListID {
                            Label(list.title, systemImage: "checkmark")
                        } else {
                            Text(list.title)
                        }
                    }
                    .disabled(!list.allowsModifications)
                }
            }
            Button("Neue Liste anlegen", systemImage: "plus") {
                newListName = ""
                showsNewListPrompt = true
            }
        }
    }
}

extension ShoppingScreen {
    private var triagePromptBinding: Binding<Bool> {
        Binding(get: { model.triagePrompt != nil && model.triage == nil }, set: { if !$0 { model.postponeTriage() } })
    }

    private var triageBinding: Binding<Bool> {
        Binding(get: { model.triage != nil }, set: { if !$0 { model.endTriage() } })
    }
}

/// "5 automatisch zugeordnet · Rückgängig" (Pro, KONZEPT §7.4). Disappears after a few seconds.
private struct AutoAssignToast: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let count = model.autoAssignReport?.assignments.count ?? 0
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
            Text(count == 1 ? "1 Eintrag automatisch zugeordnet" : "\(count) Einträge automatisch zugeordnet")
                .font(.subheadline.weight(.medium))
            Button("Rückgängig") { Task { await model.undoAutoAssign() } }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .task(id: count) {
            try? await Task.sleep(for: .seconds(6))
            model.autoAssignReport = nil
        }
    }
}

private extension View {
    /// Marqet has no tabs: when space runs out on iPhone Duo, keep the toolbar items.
    @ViewBuilder
    func toolbarVerticalCompressionPreferringItems() -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalCompressionBehavior(.prefersToolbarItems)
        } else {
            self
        }
    }
}

#Preview {
    ShoppingScreen()
        .environment(AppModel.preview(
            items: [
                ("Milch", "laktosefrei\n🛒 Aldi Süd"), ("Bananen", "🛒 Aldi Süd"), ("Brot", "🛒 Aldi Süd"),
                ("Zahnpasta", "🛒 dm"), ("Batterien", nil),
            ],
            stores: ["aldi-sued", "dm"]
        ))
}
