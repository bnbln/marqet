import SwiftUI

/// Marqet has no user account; this page explains what the profile icon represents on this device.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 72, height: 72)
                            .background(Color(.tertiarySystemFill), in: .circle)
                        Text("Dein Marqet-Profil")
                            .font(.title3.weight(.semibold))
                        Label("Ohne Benutzerkonto", systemImage: "lock.shield")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                }

                Section("Auf diesem Gerät") {
                    LabeledContent("Einkaufsliste", value: model.selectedList?.title ?? "Liste wählen")
                    LabeledContent("Läden", value: "\(model.stores.count)")
                    LabeledContent("Kundenkarten", value: "\(model.loyaltyCards.count)")
                }

                Section {
                    Text("Deine Listen bleiben in Apple Erinnerungen. Läden und Kundenkarten speichert Marqet auf diesem Gerät.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                }
            }
        }
    }
}
