import MarqetCore
import MarqetReminders
import SwiftUI

/// First launch (KONZEPT §7.5): welcome → Reminders access → list → stores → Siri tip.
struct OnboardingFlow: View {
    private enum Step: Int, CaseIterable {
        case welcome, access, list, stores, siri
    }

    @Environment(AppModel.self) private var model
    @State private var step = Step.welcome

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .access: access
                case .list: ListPickerView(embedded: true) { advance(to: .stores) }
                case .stores: OnboardingStoresView { advance(to: .siri) }
                case .siri: siri
                }
            }
            .animation(.snappy, value: step)
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Zurück", systemImage: "chevron.left") { goBack() }
                            .tint(.primary)
                    }
                }
                if step != .welcome {
                    ToolbarItem(placement: .principal) {
                        ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                            .frame(width: 160)
                    }
                }
                if canSkip {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Überspringen") { skip() }
                            .tint(.primary)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: model.phase) { _, phase in
            // Access granted (here or in Settings): continue with the list.
            if step == .access, phase == .needsList || phase == .ready {
                advance(to: .list)
            }
        }
    }

    private func advance(to next: Step) {
        withAnimation(.snappy) { step = next }
    }

    private var canSkip: Bool {
        switch step {
        case .welcome, .stores, .siri: true
        case .access: model.phase == .needsList || model.phase == .ready
        case .list: true
        }
    }

    private func skip() {
        switch step {
        case .welcome: advance(to: model.phase == .needsList || model.phase == .ready ? .list : .access)
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
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        advance(to: previous)
    }

    // MARK: Steps

    private var welcome: some View {
        OnboardingPage(
            symbol: "cart.fill",
            title: "Deine Einkaufsliste, nach Läden sortiert",
            points: [
                ("mic.fill", "Trag Einkäufe wie gewohnt ein – mit Siri, in Erinnerungen oder in Marqet."),
                ("storefront.fill", "Marqet sortiert sie in Cards für Aldi, dm, den Markt und alle deine Läden."),
                ("figure.walk", "Im Laden in der Reihenfolge deines Wegs – mit jedem Einkauf besser."),
            ],
            footnote: "Deine Einträge bleiben in Apple Erinnerungen. Kein Konto, keine Werbung."
        ) {
            Button("Los geht’s") {
                let hasAccess = model.phase == .needsList || model.phase == .ready
                advance(to: hasAccess ? .list : .access)
            }
        }
    }

    @ViewBuilder
    private var access: some View {
        if case .needsPermission(let status) = model.phase, status != .notDetermined {
            PermissionView(status: status)
        } else {
            OnboardingPage(
                symbol: "checklist",
                title: "Zugriff auf Erinnerungen",
                points: [
                    ("list.bullet", "Marqet liest die Liste, die du gleich auswählst."),
                    ("note.text", "Den Laden eines Eintrags speichert Marqet als Zeile „🛒 Laden“ in dessen Notizen – sichtbar auch in Erinnerungen und für alle, mit denen du die Liste teilst."),
                ],
                footnote: "Alles bleibt auf deinem Gerät und in deinem iCloud."
            ) {
                Button("Zugriff erlauben") {
                    Task { await model.requestAccess() }
                }
            }
        }
    }

    private var siri: some View {
        OnboardingPage(
            symbol: "waveform",
            title: "Eintragen mit Siri",
            points: [
                ("quote.bubble.fill", "Sag: „Hey Siri, setz Milch auf die Liste \(model.selectedList?.title ?? "Einkaufen")“."),
                ("tray.and.arrow.down.fill", "Neue Einträge landen in „Unsortiert“ – Marqet fragt dich beim nächsten Öffnen, in welchen Laden sie gehören."),
                ("hand.draw.fill", "Wische zwischen den Läden, tippe + für neue Einträge."),
            ],
            footnote: nil
        ) {
            Button("Fertig") { model.completeOnboarding() }
        }
    }
}

/// Step 4: pick the stores you shop at; the tap order becomes the card order (KONZEPT §7.5).
private struct OnboardingStoresView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var model
    @State private var selection: [String] = []
    @State private var showsCustomStore = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wo kaufst du ein?")
                        .font(.largeTitle.bold())
                    Text("Wähle deine Läden in der Reihenfolge, in der du sie am häufigsten besuchst. Du kannst später jederzeit weitere hinzufügen.")
                        .foregroundStyle(.secondary)
                }
                Picker("Region", selection: $model.region) {
                    Text("Deutschland").tag(StoreCatalog.Region.germany)
                    Text("Österreich").tag(StoreCatalog.Region.austria)
                    Text("Schweiz").tag(StoreCatalog.Region.switzerland)
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 16) {
                    ForEach(model.catalog?.entries(for: model.region) ?? []) { entry in
                        let index = selection.firstIndex(of: entry.key)
                        Button {
                            if let index { selection.remove(at: index) } else { selection.append(entry.key) }
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
                                                .offset(x: 6, y: -6)
                                        }
                                    }
                                    .opacity(index == nil && !selection.isEmpty ? 0.55 : 1)
                                Text(entry.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 100, alignment: .top)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(index != nil ? .isSelected : [])
                    }
                }
                Button("Eigenen Laden anlegen", systemImage: "plus") { showsCustomStore = true }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                for key in selection {
                    if let entry = model.catalog?.entry(forKey: key) { model.addStore(from: entry, planned: false) }
                }
                onContinue()
            } label: {
                Text("Weiter")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(20)
        }
        .sheet(isPresented: $showsCustomStore) {
            AddStoreSheet(opensComposer: false)
        }
    }
}

private struct OnboardingPage<Action: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let points: [(String, LocalizedStringKey)]
    let footnote: LocalizedStringKey?
    @ViewBuilder var action: Action

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: symbol)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.tint)
                    .padding(.top, 32)
                Text(title)
                    .font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(points.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: points[index].0)
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 30)
                            Text(points[index].1)
                        }
                    }
                }
                if let footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            action
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(20)
        }
    }
}
