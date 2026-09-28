import MarqetCore
import SwiftUI

/// Settings (KONZEPT §7.6).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppAccentPalette.storageKey) private var accentPaletteKey = AppAccentPalette.leaf.rawValue
    @State private var confirmsReset = false
    @State private var showsPaywall = false
    @State private var showsNewListPrompt = false
    @State private var newListName = ""
    @AppStorage(AppModel.openPricesKey) private var openPricesEnabled = true

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section("Listen") {
                    Menu {
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
                    } label: {
                        LabeledContent("Aktuelle Liste", value: model.selectedList?.title ?? "Liste wählen")
                    }
                    .tint(.primary)
                    Button("Neue Liste anlegen", systemImage: "plus") {
                        newListName = ""
                        showsNewListPrompt = true
                    }
                }
                Section("Erscheinungsbild") {
                    ForEach(AppAccentPalette.allCases) { palette in
                        Button {
                            accentPaletteKey = palette.rawValue
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(palette.color)
                                    .frame(width: 22, height: 22)
                                Text(palette.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if accentPaletteKey == palette.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(palette.color)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    NavigationLink {
                        WidgetSettingsView()
                    } label: {
                        Label("Widgets & Live-Aktivität", systemImage: "square.grid.2x2")
                    }
                }

                Section {
                    NavigationLink {
                        StoresSettingsView()
                    } label: {
                        LabeledContent("Läden verwalten", value: "\(model.stores.count)")
                    }
                    NavigationLink {
                        LoyaltyCardsSettingsView()
                    } label: {
                        LabeledContent("Kundenkarten", value: "\(model.loyaltyCards.count)")
                    }
                    Picker("Zuordnen als", selection: $model.preferredTriageMode) {
                        Text("Karten").tag(TriageSession.Mode.single)
                        Text("Tabelle").tag(TriageSession.Mode.board)
                    }
                    Toggle("Preise beim Zuordnen", isOn: $openPricesEnabled)
                    Button {
                        Task { await model.refreshPrices(for: model.items, force: true, includeOffers: true) }
                    } label: {
                        HStack {
                            Label("Preise jetzt aktualisieren", systemImage: "arrow.clockwise")
                            Spacer()
                            if model.isRefreshingPrices { ProgressView() }
                        }
                    }
                    .disabled(!openPricesEnabled || model.isRefreshingPrices)
                    if let lastCheck = model.lastPriceCheck {
                        LabeledContent("Letzte Preisabfrage", value: lastCheck.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let error = model.priceRefreshError {
                        Text(error).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Läden")
                } footer: {
                    Text("Marqet lädt Preise erst, wenn du Angebote oder Preisvergleiche öffnest. Danach nutzt es die lokal gespeicherten Werte bis zur nächsten benötigten Aktualisierung.")
                }

                Section {
                    Picker("Reihenfolge", selection: Binding(
                        get: { model.storeSortMode },
                        set: { mode in Task { await model.setStoreSortMode(mode) } }
                    )) {
                        ForEach(StoreSortMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if model.storeSortMode != .manual {
                        Picker("Unterwegs", selection: Binding(
                            get: { model.travelMode },
                            set: { mode in
                                model.travelMode = mode
                                Task {
                                    await model.refreshStoreOrder()
                                    model.pageRequest = model.activePage
                                }
                            }
                        )) {
                            ForEach(TravelMode.allCases, id: \.self) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                        }
                    }
                } header: {
                    Text("Reihenfolge der Cards")
                } footer: {
                    Text(sortFooter)
                }

                Section {
                    proRow
                    proToggle("Automatisch zuordnen", isOn: $model.autoAssignEnabled)
                    proToggle("Vorschläge mit Apple Intelligence", isOn: $model.intelligenceEnabled)
                    proToggle("Laufweg lernen", isOn: $model.routeLearningEnabled)
                    Button("Gelerntes zurücksetzen", role: .destructive) { confirmsReset = true }
                } header: {
                    Text("Intelligenz")
                } footer: {
                    Text(intelligenceFooter)
                }

                Section("Über Marqet") {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    NavigationLink("Datenschutz") { PrivacyView() }
                    NavigationLink("Datenquellen") { DataSourcesView() }
                    Text("Marqet steht in keiner Verbindung zu den genannten Handelsketten. Alle Marken gehören ihren jeweiligen Inhabern.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                Section("Entwicklung") {
                    Toggle("Marqet Pro (Entwickler-Override)", isOn: $model.developerProOverride)
                    Button("Onboarding erneut zeigen") {
                        model.hasCompletedOnboarding = false
                        dismiss()
                    }
                }
                #endif
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .tint(AppAccentPalette(rawValue: accentPaletteKey)?.color ?? AppAccentPalette.leaf.color)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                        .tint(.primary)
                }
            }
            .alert("Neue Liste anlegen", isPresented: $showsNewListPrompt) {
                TextField("Listenname", text: $newListName)
                Button("Abbrechen", role: .cancel) {}
                Button("Erstellen") {
                    Task { await model.createShoppingList(named: newListName) }
                }
                .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .sheet(isPresented: $showsPaywall) {
                PaywallView()
            }
            .confirmationDialog("Gelerntes zurücksetzen?", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("Zurücksetzen", role: .destructive) { model.resetLearning() }
            } message: {
                Text("Marqet vergisst gelernte Zuordnungen und Laufwege. Deine Kategorie-Korrekturen und selbst sortierten Abschnitte bleiben.")
            }
        }
    }

    @ViewBuilder
    private var proRow: some View {
        if model.isPro {
            Label("Marqet Pro ist aktiv", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.tint)
        } else {
            Button {
                showsPaywall = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Marqet Pro freischalten", systemImage: "sparkles")
                        .font(.headline)
                    Text("Automatisch zuordnen, Vorschläge mit Apple Intelligence und Sortierung nach deinem Laufweg. Einmalkauf, mit der Familie teilbar.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Pro switches: usable with Pro, otherwise a lock that opens the paywall.
    @ViewBuilder
    private func proToggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        if model.isPro {
            Toggle(title, isOn: isOn)
        } else {
            Button {
                showsPaywall = true
            } label: {
                LabeledContent(title) {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private var sortFooter: String {
        switch model.storeSortMode {
        case .manual: String(localized: "Du bestimmst die Reihenfolge selbst. Entfernung und Smart nutzen deinen Standort nur, während Marqet offen ist.")
        case .distance: String(localized: "Der nächste Laden steht vorn. Läden ohne Filiale folgen in deiner Reihenfolge.")
        case .smart: String(localized: "Viele offene Einträge und kurze Wege stehen vorn. Die Reihenfolge ändert sich nur beim Öffnen, nicht beim Wischen.")
        }
    }

    private var intelligenceFooter: String {
        guard model.isPro else {
            return String(localized: "Vorschläge aus deinen bisherigen Zuordnungen gibt es auch ohne Pro.")
        }
        return model.isIntelligenceAvailable
            ? String(localized: "Apple Intelligence läuft auf deinem Gerät. Nichts verlässt dein iPhone.")
            : String(localized: "Apple Intelligence ist auf diesem Gerät nicht verfügbar. Marqet schlägt Läden dann anhand der Ladenart vor.")
    }
}

private struct PrivacyView: View {
    var body: some View {
        List {
            Text("Marqet hat kein Konto, keinen Server und keine Werbung. Deine Einträge liegen in Apple Erinnerungen, deine Läden und alles Gelernte auf deinem Gerät.")
            Text("Den Laden eines Eintrags speichert Marqet als Zeile „🛒 Laden“ in den Notizen der Erinnerung. Mit wem du die Liste teilst, sieht diese Zeile auch.")
            Text("Apple Intelligence läuft auf deinem Gerät. Marqet erfasst keine Nutzungsdaten.")
            Text("Deinen Standort nutzt Marqet nur mit deiner Erlaubnis. Für lokale Preissuchen sendet es eine auf etwa 10 km gerundete Position und einen Umkreis von 30 km an Open Prices. Ohne Standort nutzt es regionale Preise.")
            Text("Kundenkarten bleiben auf deinem Gerät. Beim Scannen liest Marqet nur den Barcode aus, Kamerabilder werden weder gespeichert noch übertragen.")
            Text("Preise werden bei Bedarf von Open Prices geladen und auf dem Gerät gespeichert. Die Anfrage enthält Produktkategorien, aber keine Eintragstexte oder angelegten Läden.")
            Text("Käufe wickelt der App Store von Apple ab. Marqet erhält keine Zahlungsdaten.")
        }
        .navigationTitle("Datenschutz")
    }
}

/// Attribution for the open data in the app (docs/OFFENE-DATEN.md §2).
private struct DataSourcesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Prices").font(.headline)
                    Text("Preise aus Kassenbons und Preisschildern, gesammelt von der Community von Open Food Facts. Marqet zeigt Kategoriepreise und besonders günstige Beobachtungen mit Datum.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let lastCheck = model.lastPriceCheck {
                        Text("Letzte Preisabfrage: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Link("prices.openfoodfacts.org", destination: URL(string: "https://prices.openfoodfacts.org")!)
            } footer: {
                Text("Datenbank unter der Open Database License (ODbL 1.0), Inhalte unter der Database Contents License (DbCL 1.0).")
            }
            Section {
                Link("Open Database License", destination: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!)
            }
        }
        .navigationTitle("Datenquellen")
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
