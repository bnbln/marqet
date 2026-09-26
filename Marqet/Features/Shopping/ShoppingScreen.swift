import MarqetCore
import SwiftUI

/// Main screen: the store card pager (KONZEPT §7.2) with the add button and the composer.
struct ShoppingScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showsAddStore = false
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
            Menu("Optionen", systemImage: "gearshape") {
                Button("Laden hinzufügen", systemImage: "storefront") { showsAddStore = true }
                Button("Liste wechseln", systemImage: "list.bullet") { model.showListPicker() }
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
