import MarqetCore
import SwiftUI

/// Main screen: the store card pager (KONZEPT §7.2) with the add button and the composer.
struct ShoppingScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showsAddStore = false
    @State private var showsSettings = false
    @State private var isComposerFocused = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StorePager()
                if model.composerTarget == nil {
                    PageIndicator()
                        .padding(.vertical, 10)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if model.composerTarget != nil {
                    ComposerBar(isFocused: $isComposerFocused, showsAddStore: $showsAddStore)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.composerTarget == nil)
            .navigationTitle(model.selectedList?.title ?? "Marqet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .toolbarVerticalCompressionPreferringItems()
            .sheet(isPresented: $showsAddStore) {
                AddStoreSheet()
                    .leadingSheetPlacement()
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView()
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

    // Only system toolbar items: on iPhone Duo they move into the vertical bar (KONZEPT-DUO-IPAD §3).
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Einstellungen", systemImage: "gearshape") { showsSettings = true }
        }

        if !model.unsortedItems.isEmpty {
            ToolbarItem(placement: .bottomBar) {
                Button("Zuordnen (\(model.unsortedItems.count))", systemImage: "tray.and.arrow.down") {
                    model.startTriage()
                }
            }
        }

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
            Menu {
                Section("Hinzufügen zu …") {
                    Button("Unsortiert", systemImage: "tray") { model.startComposer(on: .unsorted) }
                    ForEach(model.stores.sorted { $0.sortIndex < $1.sortIndex }) { store in
                        Button(store.name) { model.startComposer(on: .store(store.id)) }
                    }
                }
            } label: {
                Label("Hinzufügen", systemImage: "plus")
            } primaryAction: {
                model.startComposer(on: model.deck.pages.contains(model.activePage) ? model.activePage : .unsorted)
            }
            .menuStyle(.button)
            .buttonStyle(.glassProminent)
            .tint(.accentColor)
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
