import MarqetCore
import MarqetReminders
import SwiftUI

/// First launch (KONZEPT §7.5): welcome → Reminders access → list → stores → Siri tip.
/// Every step uses `OnboardingLayout`, so illustration, headline and text never jump.
struct OnboardingFlow: View {
    private enum Step: Int, CaseIterable {
        case welcome, access, list, stores, siri
    }

    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var step = Step.welcome
    /// Tap order of the chosen catalog stores – kept when going back and forth.
    @State private var storeSelection: [String] = []

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .access: access
                case .list: OnboardingListStep { advance(to: .stores) }
                case .stores: OnboardingStoresStep(selection: $storeSelection) {
                    model.addOnboardingStores(storeSelection)
                    advance(to: .siri)
                }
                case .siri: siri
                }
            }
            .id(step)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(x: 24)),
                removal: .opacity
            ))
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Zurück", systemImage: "chevron.left") { goBack() }
                            .tint(.primary)
                    }
                    ToolbarItem(placement: .principal) {
                        ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                            .frame(width: 140)
                            .accessibilityLabel("Schritt \(step.rawValue + 1) von \(Step.allCases.count)")
                    }
                }
                if canSkip {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Compact: an icon button; the open Duo and the iPad have room for the word.
                        Button("Überspringen", systemImage: "chevron.right") { skip() }
                            .labelStyle(AdaptiveSkipLabelStyle(showsTitle: sizeClass == .regular))
                            .tint(.primary)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        // Prices arrive in the background while the user reads the first screens. Unstructured,
        // so finishing the onboarding quickly does not cancel the download.
        .task { Task(priority: .utility) { await model.prefetchStaplePrices() } }
        .onChange(of: model.phase) { _, phase in
            // Access granted (here or in Settings): continue with the list.
            if step == .access, hasAccess(phase) {
                advance(to: .list)
            }
        }
    }

    private func hasAccess(_ phase: AppModel.Phase) -> Bool {
        phase == .needsList || phase == .ready
    }

    private func advance(to next: Step) {
        withAnimation(.snappy) { step = next }
    }

    /// The last step has its own "Fertig"; access can only be skipped once granted.
    private var canSkip: Bool {
        switch step {
        case .welcome, .list, .stores: true
        case .access: hasAccess(model.phase)
        case .siri: false
        }
    }

    private func skip() {
        switch step {
        case .welcome: advance(to: hasAccess(model.phase) ? .list : .access)
        case .access: advance(to: .list)
        case .list:
            if model.selectedListID != nil {
                advance(to: .stores)
            } else {
                Task {
                    await model.createShoppingList()
                    if model.selectedListID != nil { advance(to: .stores) }
                }
            }
        case .stores: advance(to: .siri)
        case .siri: model.completeOnboarding()
        }
    }

    private func goBack() {
        guard var previous = Step(rawValue: step.rawValue - 1) else { return }
        // Access already granted: going back skips the permission step.
        if previous == .access, hasAccess(model.phase) { previous = .welcome }
        advance(to: previous)
    }

    // MARK: Steps

    private var welcome: some View {
        OnboardingLayout(title: "Deine Einkaufsliste, nach Läden sortiert", brandName: "Marqet") {
            SortingIllustration()
        } content: {
            OnboardingPoints(points: [
                ("mic.fill", "Trag Einkäufe mit Siri, in Erinnerungen oder in Marqet ein."),
                ("square.stack.fill", "Marqet sortiert sie nach Läden."),
                ("mappin", "Finde Läden in deiner Nähe und hake Einkäufe ab."),
            ])
        } action: {
            OnboardingPrimaryButton(title: "Los geht’s") {
                advance(to: hasAccess(model.phase) ? .list : .access)
            }
        }
    }

    @ViewBuilder
    private var access: some View {
        if case .needsPermission(let status) = model.phase, status != .notDetermined {
            // Declined: same page, the way back leads through Settings.
            OnboardingLayout(title: "Zugriff in den Einstellungen erlauben") {
                MarkerIllustration()
            } content: {
                OnboardingPoints(points: [
                    ("gearshape.fill", "Öffne Einstellungen › Apps › Marqet › Erinnerungen und wähle „Voller Zugriff“."),
                    ("arrow.uturn.backward", "Danach geht es hier automatisch weiter."),
                ])
            } action: {
                SettingsButton()
            }
        } else {
            OnboardingLayout(title: "Zugriff auf Erinnerungen") {
                MarkerIllustration()
            } content: {
                OnboardingPoints(points: [
                    ("list.bullet", "Wähle gleich die Einkaufsliste aus, die Marqet sortieren soll."),
                    ("note.text", "Der Laden steht sichtbar in den Notizen des Eintrags – auch für alle, mit denen du die Liste teilst."),
                ])
            } action: {
                OnboardingPrimaryButton(title: "Zugriff erlauben") {
                    Task { await model.requestAccess() }
                }
            }
        }
    }

    private var siri: some View {
        OnboardingLayout(title: "Eintragen mit Siri") {
            SiriIllustration()
        } content: {
            OnboardingPoints(points: [
                ("quote.bubble.fill", "Sag: „Hey Siri, setz Milch auf die Liste \(model.selectedList?.title ?? "Einkaufen")“."),
                ("tray.fill", "Neue Einträge findest du in der Inbox."),
                ("square.stack.3d.up.fill", "Live Activity und Widgets zeigen dir, was noch offen ist."),
            ])
        } action: {
            OnboardingPrimaryButton(title: "Fertig") { model.completeOnboarding() }
        }
    }
}

private struct AdaptiveSkipLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsTitle {
            configuration.title
        } else {
            configuration.icon
        }
    }
}

private struct SettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        OnboardingPrimaryButton(title: "Einstellungen öffnen") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
    }
}

/// Step 3: the Reminders list Marqet works with.
private struct OnboardingListStep: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        OnboardingLayout(title: "Welche Liste ist deine Einkaufsliste?") {
            ListIllustration()
        } content: {
            VStack(spacing: 0) {
                ForEach(sortedLists) { list in
                    Button {
                        Task { await model.selectList(list.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: list.colorHex ?? "#8E8E93"))
                                .frame(width: 14, height: 14)
                            Text(list.title).foregroundStyle(.primary)
                            Spacer()
                            if list.id == model.selectedListID {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!list.allowsModifications)
                    .accessibilityAddTraits(list.id == model.selectedListID ? .isSelected : [])
                    Divider().padding(.leading, 42)
                }
                Button {
                    Task { await model.createShoppingList() }
                } label: {
                    Label("Neue Liste „Einkaufen“ anlegen", systemImage: "plus")
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            // The page is white: a gray block, like a grouped list, keeps the rows together.
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20, style: .continuous))
        } action: {
            OnboardingPrimaryButton(title: "Weiter", isEnabled: model.selectedListID != nil, action: onContinue)
        }
        .task(id: model.lists.map(\.id)) {
            // An obvious shopping list ("Einkaufen", "Einkaufsliste" …) is preselected.
            guard model.selectedListID == nil,
                  let likely = sortedLists.first(where: { $0.allowsModifications && ShoppingListHeuristics.isLikelyShoppingList($0.title) })
            else { return }
            await model.selectList(likely.id)
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

/// Step 4: the stores you shop at; the tap order becomes the card order (KONZEPT §7.5).
private struct OnboardingStoresStep: View {
    @Binding var selection: [String]
    let onContinue: () -> Void
    @Environment(AppModel.self) private var model
    @State private var showsCustomStore = false

    var body: some View {
        OnboardingLayout(title: "Wo kaufst du ein?") {
            StoresIllustration()
        } content: {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 16) {
                ForEach(catalogEntries) { entry in
                    tile(entry)
                }
            }
            Button("Eigenen Laden anlegen", systemImage: "plus") { showsCustomStore = true }
                .foregroundStyle(.tint)
        } action: {
            OnboardingPrimaryButton(title: continueTitle, action: onContinue)
        }
        .sheet(isPresented: $showsCustomStore) {
            AddStoreSheet(opensComposer: false)
        }
    }

    private var continueTitle: LocalizedStringKey {
        switch selection.count {
        case 0: "Später"
        case 1: "Weiter mit 1 Laden"
        default: "Weiter mit \(selection.count) Läden"
        }
    }

    private var catalogEntries: [StoreCatalog.Entry] {
        let entries = model.catalog?.entries(for: model.region) ?? []
        let priorities = [
            "amazon", "aldi-sued", "aldi-nord", "lidl", "rewe", "edeka", "kaufland",
            "netto", "penny", "picnic", "otto", "dm", "rossmann", "sephora",
        ]
        let rank = Dictionary(uniqueKeysWithValues: priorities.enumerated().map { ($0.element, $0.offset) })
        return entries.enumerated().sorted { lhs, rhs in
            (rank[lhs.element.key] ?? priorities.count + lhs.offset) <
            (rank[rhs.element.key] ?? priorities.count + rhs.offset)
        }.map(\.element)
    }

    private func tile(_ entry: StoreCatalog.Entry) -> some View {
        let index = selection.firstIndex(of: entry.key)
        return Button {
            withAnimation(.snappy) {
                if let index { selection.remove(at: index) } else { selection.append(entry.key) }
            }
        } label: {
            VStack(spacing: 8) {
                StoreBadge(store: entry.makeStore(sortIndex: 0), size: 52)
                    .overlay(alignment: .topTrailing) {
                        if let index {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.accentColor, in: .circle)
                                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                                .offset(x: 6, y: -6)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                Text(entry.name)
                    .font(.caption.weight(index == nil ? .medium : .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.name)
        .accessibilityValue(index.map { String(localized: "Platz \($0 + 1)") } ?? "")
        .accessibilityAddTraits(index != nil ? .isSelected : [])
    }
}
