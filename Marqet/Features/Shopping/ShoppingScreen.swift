import MarqetCore
import SwiftUI

/// Main screen: the store card pager (KONZEPT §7.2) with the add button and the composer.
struct ShoppingScreen: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppAccentPalette.storageKey) private var accentPaletteKey = AppAccentPalette.leaf.rawValue
    @State private var showsAddStore = false
    @State private var showsSettings = false
    @State private var showsStoreOrder = false
    @State private var isComposerFocused = false
    /// Bumped by the add button and undo; each drives a light haptic tap.
    @State private var addFeedback = 0
    @State private var undoFeedback = 0

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
                .sensoryFeedback(.impact(weight: .light), trigger: addFeedback)
                .sensoryFeedback(.impact(weight: .light), trigger: undoFeedback)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .toolbarVerticalCompressionPreferringItems()
                .tint(.primary)
                .sheet(isPresented: $showsAddStore) {
                    AddStoreSheet()
                        .leadingSheetPlacement()
                }
                .sheet(isPresented: $showsSettings) {
                    SettingsView()
                }
                .sheet(isPresented: $showsStoreOrder) {
                    StoreOrderSheet().leadingSheetPlacement()
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
                .onChange(of: model.triagePrompt) { _, prompt in
                    #if DEBUG
                    if prompt != nil, ProcessInfo.processInfo.arguments.contains("-demo-no-prompt") {
                        model.postponeTriage()
                    }
                    #endif
                }
                .onChange(of: model.hasLoadedItems) { _, loaded in
                    #if DEBUG
                    if loaded, ProcessInfo.processInfo.arguments.contains("-demo-compose") {
                        model.startComposer(on: model.deck.pages.first(where: { $0.storeID != nil }) ?? .unsorted)
                    }
                    #endif
                }
        }
    }

    private var bottomControls: some View {
        // The dots sit bottom-aligned with the add button, on the background below the cards.
        ZStack(alignment: .bottom) {
            PageIndicator()
            HStack {
                Spacer()
                Menu {
                    Section("Hinzufügen zu …") {
                        Button("Unsortiert", systemImage: "tray") { model.startComposer(on: .unsorted) }
                        ForEach(model.sortedStores) { store in
                            Button(store.name) { model.startComposer(on: .store(store.id)) }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .glassEffect(.regular.tint(accentColor).interactive(), in: .circle)
                        .contentShape(.circle)
                } primaryAction: {
                    addFeedback += 1
                    model.startComposer(on: model.deck.pages.contains(model.activePage) ? model.activePage : .unsorted)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("Eintrag hinzufügen")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    // System navigation and settings items remain available in the iPhone Duo vertical bar.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Marqet")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(model.selectedList?.title ?? "Liste wählen")
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .sharedBackgroundVisibility(.hidden)
        if model.lastUndoAction != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rückgängig", systemImage: "arrow.uturn.backward") {
                    undoFeedback += 1
                    Task { await model.undoLastAction() }
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(model.showsCompleted ? "Erledigte ausblenden" : "Erledigte anzeigen",
                       systemImage: model.showsCompleted ? "checkmark.circle.fill" : "clock.arrow.circlepath") {
                    withAnimation(.snappy) { model.showsCompleted.toggle() }
                    if model.showsCompleted { Task { await model.loadRecentlyCompleted() } }
                }
                Button("Läden sortieren", systemImage: "arrow.up.arrow.down") {
                    showsStoreOrder = true
                }
            } label: {
                Label("Anzeigeoptionen", systemImage: "line.3.horizontal.decrease")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Einstellungen", systemImage: "gearshape") { showsSettings = true }
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
    @State private var undoFeedback = 0

    var body: some View {
        let count = model.autoAssignReport?.assignments.count ?? 0
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
            Text(count == 1 ? "1 Eintrag automatisch zugeordnet" : "\(count) Einträge automatisch zugeordnet")
                .font(.subheadline.weight(.medium))
            Button("Rückgängig") {
                undoFeedback += 1
                Task { await model.undoAutoAssign() }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .sensoryFeedback(.impact(weight: .light), trigger: undoFeedback)
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
