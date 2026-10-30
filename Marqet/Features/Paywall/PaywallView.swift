import SwiftUI

/// Marqet Pro offer (KONZEPT §9.4). Opened from locked switches, settings and the triage summary –
/// never on launch.
struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(.tint)
                        Text("Marqet Pro")
                            .font(.largeTitle.bold())
                        Text("Weniger sortieren, schneller einkaufen.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 20) {
                        feature("wand.and.stars", "Automatisch zuordnen",
                                "Was du schon zweimal im selben Laden gekauft hast, landet von selbst dort.")
                        feature("sparkles", "Vorschläge mit Apple Intelligence",
                                "Auch für Neues schlägt Marqet den passenden Laden und die Kategorie vor, direkt auf deinem Gerät.")
                        feature("figure.walk", "Sortiert nach deinem Laufweg",
                                "Marqet lernt beim Abhaken, in welcher Reihenfolge du durch jeden Laden gehst.")
                        feature("person.2.fill", "Für die ganze Familie",
                                "Einmal kaufen, über die Familienfreigabe mit bis zu fünf Personen teilen.")
                    }
                    .frame(maxWidth: 520, alignment: .leading)

                    if model.hasProEntitlement {
                        Label(purchases.isFamilyShared ? "Aktiv über die Familienfreigabe" : "Marqet Pro ist aktiv",
                              systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.tint)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                if !model.hasProEntitlement { purchaseControls }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .task { await purchases.loadProduct() }
            .onChange(of: model.hasProEntitlement) { _, entitled in
                if entitled { dismiss() }
            }
        }
    }

    private var purchaseControls: some View {
        VStack(spacing: 12) {
            Button {
                Task { await purchases.purchase() }
            } label: {
                Group {
                    if purchases.state == .purchasing || purchases.state == .loading {
                        ProgressView()
                    } else if let product = purchases.product {
                        Text("Für \(product.displayPrice) freischalten")
                    } else if purchases.state == .unavailable {
                        Text("Bald verfügbar")
                    } else {
                        Text("Freischalten")
                    }
                }
                .frame(maxWidth: 420)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(purchases.product == nil || purchases.state == .purchasing)

            switch purchases.state {
            case .pending:
                Text("Der Kauf wartet auf Freigabe, zum Beispiel durch „Kaufanfrage“.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .unavailable:
                Text("Marqet Pro ist noch nicht verfügbar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            default:
                EmptyView()
            }

            HStack(spacing: 20) {
                Button("Käufe wiederherstellen") { Task { await purchases.restore() } }
                Link("Nutzungsbedingungen", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.footnote)

            Text("Einmalkauf, kein Abo. Deine Einkaufsliste funktioniert auch ohne Pro vollständig.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        }
    }
}
