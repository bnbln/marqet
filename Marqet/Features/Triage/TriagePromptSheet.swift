import MarqetCore
import SwiftUI

/// "3 neue Einträge zuordnen?" – a small sheet after new unsorted items arrive (KONZEPT §7.4).
struct TriagePromptSheet: View {
    let itemIDs: [ShoppingItem.ID]
    @Environment(AppModel.self) private var model

    private var titles: [String] {
        let ids = Set(itemIDs)
        return model.unsortedItems.filter { ids.contains($0.id) }.map(\.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titles.count == 1 ? "1 neuer Eintrag" : "\(titles.count) neue Einträge")
                        .font(.headline)
                    Text("Noch keinem Laden zugeordnet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(titles.prefix(12), id: \.self) { title in
                        Text(title)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill), in: .capsule)
                    }
                }
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 12) {
                Button("Später") { model.postponeTriage() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("Zuordnen") { model.startTriage() }
                    .buttonStyle(.glassProminent)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .padding(20)
        .presentationDetents([.height(250)])
        .presentationBackgroundInteraction(.enabled)
    }
}
