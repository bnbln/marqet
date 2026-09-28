import MarqetCore
import SwiftUI

/// Main screen: the store card pager (KONZEPT §7.2) with the add button and the composer.
struct ShoppingScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showsAddStore = false
    @State private var showsSettings = false
    @State private var showsProfile = false
    @State private var showsLoyaltyCards = false
    @State private var showsStoreOrder = false
    @State private var isComposerFocused = false
    /// Bumped by the add button and undo; each drives a light haptic tap.
    @State private var addFeedback = 0
    @State private var undoFeedback = 0
    @Namespace private var cardZoom
    @State private var hinge: HingeState = .none

    /// Height of large title + briefing card; the pager moves down by it.
    @State private var briefingHeight: CGFloat = 0

    /// 1 while the briefing sits above the inbox, 0 once the user swiped on – follows the finger.
    /// iPhone only: side by side cards (iPad, Duo open) keep the plain pager.
    private var briefingAmount: CGFloat {
        guard model.briefing != nil, sizeClass == .compact else { return 0 }
        return 1 - model.briefingProgress
    }

    var body: some View {
        GeometryReader { _ in
            NavigationStack {
                StorePager(isComposerFocused: $isComposerFocused, showsAddStore: $showsAddStore)
                    .environment(\.cardZoomNamespace, cardZoom)
                    // The inbox slides down under the briefing and comes back up as the user swipes on.
                    .offset(y: briefingAmount * briefingHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())
                    .overlay(alignment: .bottom) {
                        if model.editingItemID != nil {
                            editingCloseButton
                        } else if model.composerTarget == nil {
                            bottomControls
                        }
                    }
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
                    .sheet(isPresented: $showsProfile) {
                        ProfileView()
                    }
                    .sheet(isPresented: $showsLoyaltyCards) {
                        NavigationStack { LoyaltyCardsSettingsView() }
                            .tint(Color(uiColor: .label))
                    }
                    .sheet(isPresented: $showsStoreOrder) {
                        StoreOrderSheet().leadingSheetPlacement()
                    }
                    .observeHinge($hinge)
                    .voiceCaptureCover(isPresenter: model.focusedPage == nil)
                    .fullScreenCover(isPresented: triageBinding) {
                        TriageScreen()
                    }
                    .fullScreenCover(item: focusBinding) { focused in
                        Group {
                            if focused.page == .map {
                                MapScreen()
                            } else {
                                StoreFocusScreen(page: focused.page, hinge: hinge)
                            }
                        }
                        .navigationTransition(.zoom(sourceID: focused.page.rawValue, in: cardZoom))
                    }
                    .overlay(alignment: .top) { briefingBlock }
                    .overlay(alignment: .top) {
                        VStack(spacing: 8) {
                            if model.autoAssignReport != nil { AutoAssignToast() }
                            if let deleted = model.recentDeletion { DeletionUndoToast(item: deleted) }
                        }
                    }
                    .animation(.snappy, value: model.autoAssignReport)
                    .animation(.snappy, value: model.recentDeletion)
                    .onChange(of: model.activePage) { _, page in
                        // The open composer follows the page reached by swiping the cards behind it.
                        if model.composerTarget != nil,
                           model.composerTarget != page,
                           page == .unsorted || page.storeID != nil,
                           model.deck.pages.contains(page) {
                            withAnimation(.smooth) { model.startComposer(on: page) }
                        }
                        if page != .unsorted, model.briefing != nil {
                            withAnimation(.snappy) { model.dismissBriefing() }
                        }
                    }
                    .onChange(of: model.briefing != nil, initial: true) { _, shown in
                        if shown, sizeClass == .regular { model.dismissBriefing() }
                    }
                    .onChange(of: model.composerTarget) { _, target in
                        if target != nil, model.focusedPage == nil { isComposerFocused = true }
                        if target == nil { isComposerFocused = false }
                    }
                    .onChange(of: model.hasLoadedItems, initial: true) { _, loaded in
                        #if DEBUG
                        if loaded, ProcessInfo.processInfo.arguments.contains("-demo-compose") {
                            model.startComposer(on: model.deck.pages.first(where: { $0.storeID != nil }) ?? .unsorted)
                        }
                        if loaded, ProcessInfo.processInfo.arguments.contains("-demo-focus"),
                           let store = model.deck.pages.first(where: { $0.storeID != nil }) {
                            model.focus(store)
                        }
                        if loaded, ProcessInfo.processInfo.arguments.contains("-demo-focus-inbox") {
                            model.focus(.unsorted)
                        }
                        if loaded, ProcessInfo.processInfo.arguments.contains("-demo-triage") {
                            model.startTriage()
                        }
                        if loaded, ProcessInfo.processInfo.arguments.contains("-demo-voice") {
                            model.startVoice()
                        }
                        if loaded, ProcessInfo.processInfo.arguments.contains("-demo-map") {
                            model.focus(.map)
                        }
                        #endif
                    }
            }
        }
    }

    /// Large title and "Was jetzt wichtig ist" above the inbox (KONZEPT #40).
    @ViewBuilder
    private var briefingBlock: some View {
        if let briefing = model.briefing, sizeClass == .compact {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Marqet")
                        .font(.largeTitle.bold())
                    Text(model.selectedList?.title ?? "")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                BriefingCard(briefing: briefing)
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { briefingHeight = $0 + 8 }
            .offset(x: -model.briefingProgress * 160)
            .opacity(briefingAmount)
            // Swiping on the card itself also moves on to the first store.
            .gesture(DragGesture(minimumDistance: 24).onEnded { value in
                if value.translation.width < -60, let first = briefing.firstStore {
                    model.pageRequest = .store(first.id)
                }
            })
            .transition(.opacity)
        }
    }

    private var bottomControls: some View {
        // The dots sit bottom-aligned with the add button, on the background below the cards.
        ZStack(alignment: .bottom) {
            PageIndicator()
                .offset(y: 12 + briefingAmount * 60)
                .opacity(1 - briefingAmount)
            if !hinge.hasHinge {
                if sizeClass == .compact {
                    // iPhone: microphone at the left thumb, add at the right – the dots sit between.
                    HStack {
                        voiceButton
                        Spacer()
                        addMenu
                    }
                } else {
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            Spacer()
                            voiceButton
                            addMenu
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var editingCloseButton: some View {
        HStack {
            Spacer()
            Button {
                model.editingItemID = nil
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bearbeiten schließen")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    /// Dictation next to the add button (KONZEPT §3.1): speak items and stores in one go.
    private var voiceButton: some View {
        Button {
            addFeedback += 1
            model.startVoice()
        } label: {
            Image(systemName: "mic.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Einsprechen")
        .accessibilityHint("Sag, was du brauchst und wo du es kaufst.")
    }

    /// Add button: tap adds to the active card, long press picks the target (KONZEPT §7.3).
    private var addMenu: some View {
                Menu {
                    Section("Hinzufügen zu …") {
                        Button("Inbox", systemImage: "tray") { model.startComposer(on: .unsorted) }
                        ForEach(model.sortedStores) { store in
                            Button(store.name) { model.startComposer(on: .store(store.id)) }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 52, height: 52)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .contentShape(.circle)
                } primaryAction: {
                    addFeedback += 1
                    model.startComposer(on: model.deck.pages.contains(model.activePage) ? model.activePage : .unsorted)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .tint(.primary)
                .accessibilityLabel("Eintrag hinzufügen")
    }

    /// Duo: the add action as the favored item in the system bar (bottom, next to where tabs sit);
    /// the system places it in every pose – vertically at the thumb outside, in the bar inside.
    private var addToolbarMenu: some View {
        Menu {
            Section("Hinzufügen zu …") {
                Button("Inbox", systemImage: "tray") { model.startComposer(on: .unsorted) }
                ForEach(model.sortedStores) { store in
                    Button(store.name) { model.startComposer(on: .store(store.id)) }
                }
            }
        } label: {
            Label("Hinzufügen", systemImage: "plus")
        } primaryAction: {
            addFeedback += 1
            model.startComposer(on: model.deck.pages.contains(model.activePage) ? model.activePage : .unsorted)
        }
        .tint(.primary)
    }

    // System navigation remains available in the iPhone Duo vertical bar.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if hinge.hasHinge, model.composerTarget == nil, model.editingItemID == nil {
            ToolbarItem(placement: .bottomBar) {
                Button("Einsprechen", systemImage: "mic.fill") { model.startVoice() }
                    .tint(.primary)
            }
            ToolbarItem(placement: .bottomBar) { addToolbarMenu }
        }
        ToolbarItem(placement: .topBarLeading) {
            profileMenu
                .opacity(1 - briefingAmount)
        }
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
            // With the briefing, the title is shown large below the bar instead.
            .opacity(1 - briefingAmount)
        }
        .sharedBackgroundVisibility(.hidden)
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
            .tint(.primary)
        }
    }

    private var profileMenu: some View {
        Menu {
            Button("Profil", systemImage: "person.crop.circle") { showsProfile = true }
            Button("Kundenkarten", systemImage: "wallet.pass") { showsLoyaltyCards = true }
            Button("Einstellungen", systemImage: "gearshape") { showsSettings = true }
            if model.lastUndoAction != nil {
                Section("Letzte Aktion") {
                    Button("Rückgängig", systemImage: "arrow.uturn.backward") {
                        undoFeedback += 1
                        Task { await model.undoLastAction() }
                    }
                }
            }
        } label: {
            Label("Profil und mehr", systemImage: "person.fill")
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
        }
        .accessibilityLabel("Profil und mehr")
        .tint(.primary)
    }
}

extension ShoppingScreen {
    private struct FocusedPage: Identifiable {
        let page: PageID
        /// Constant: switching the composer to another store swaps the full-screen card in
        /// place instead of dismissing and presenting the cover again.
        var id: String { "focus" }
    }

    private var focusBinding: Binding<FocusedPage?> {
        Binding(get: { model.focusedPage.map(FocusedPage.init) }, set: { model.focusedPage = $0?.page })
    }

    private var triageBinding: Binding<Bool> {
        Binding(get: { model.triage != nil && model.focusedPage == nil }, set: { if !$0 { model.endTriage() } })
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

/// "„Milch“ gelöscht · Rückgängig", right after swipe-to-delete. Disappears after a few seconds
/// (bekannte Lücke: vorher gab es keine sichtbare Rückgängig-Option direkt nach dem Löschen).
private struct DeletionUndoToast: View {
    let item: ShoppingItem
    @Environment(AppModel.self) private var model
    @State private var undoFeedback = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
            Text("„\(item.title)“ gelöscht")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Button("Rückgängig") {
                undoFeedback += 1
                Task { await model.undoDeletion(item) }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .sensoryFeedback(.impact(weight: .light), trigger: undoFeedback)
        .task(id: item.id) {
            try? await Task.sleep(for: .seconds(5))
            if model.recentDeletion?.id == item.id { model.recentDeletion = nil }
        }
    }
}

extension View {
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
