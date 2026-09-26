import MarqetCore
import SwiftUI

/// Settings (KONZEPT §7.6).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppAccentPalette.storageKey) private var accentPaletteKey = AppAccentPalette.leaf.rawValue
    @State private var confirmsReset = false
    @State private var showsNewListPrompt = false
    @State private var newListName = ""

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
                        StoresSettingsView()
                    } label: {
                        LabeledContent("Läden verwalten", value: "\(model.stores.count)")
                    }
                    Picker("Zuordnen startet mit", selection: $model.preferredTriageMode) {
                        Text("Einzeln").tag(TriageSession.Mode.single)
                        Text("Board").tag(TriageSession.Mode.board)
                    }
                } header: {
                    Text("Läden")
                }

                Section {
                    proRow
                    Toggle("Automatisch zuordnen", isOn: $model.autoAssignEnabled)
                        .disabled(!model.isPro)
                    Toggle("Vorschläge mit Apple Intelligence", isOn: $model.intelligenceEnabled)
                        .disabled(!model.isPro)
                    Toggle("Laufweg lernen", isOn: $model.routeLearningEnabled)
                        .disabled(!model.isPro)
                    Button("Gelerntes zurücksetzen", role: .destructive) { confirmsReset = true }
                } header: {
                    Text("Intelligenz")
                } footer: {
                    Text(intelligenceFooter)
                }

                Section("Über Marqet") {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    NavigationLink("Datenschutz") { PrivacyView() }
                    Text("Marqet steht in keiner Verbindung zu den genannten Handelsketten. Alle Marken gehören ihren jeweiligen Inhabern.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                Section("Entwicklung") {
                    Toggle("Marqet Pro (Test)", isOn: $model.isPro)
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
            VStack(alignment: .leading, spacing: 4) {
                Label("Marqet Pro", systemImage: "sparkles")
                    .font(.headline)
                Text("Automatisch zuordnen, Vorschläge mit Apple Intelligence und Sortierung nach deinem Laufweg. Einmalkauf, mit der Familie teilbar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
        }
        .navigationTitle("Datenschutz")
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
