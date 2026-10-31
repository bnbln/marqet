import MarqetCore
import SwiftUI

/// "Was jetzt wichtig ist" above the inbox (KONZEPT #40): the stores with a list, the inbox, and
/// up to two actions. Swiping to the next card – or "Einkauf starten" – moves it away.
struct BriefingCard: View {
    let briefing: Briefing
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label(briefing.greeting, systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(briefing.headline)
                    .font(.title3.bold())
                Text(briefing.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(briefing.stores) { line in
                        Button {
                            model.pageRequest = .store(line.store.id)
                        } label: {
                            HStack(spacing: 6) {
                                StoreBadge(store: line.store, size: 24)
                                Text(line.openCount > 0 ? "\(line.openCount)" : String(localized: "angeheftet"))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 10)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemFill), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(line.store.name), \(line.openCount) offen")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

            HStack(spacing: 10) {
                if let first = briefing.firstStore {
                    Button {
                        model.pageRequest = .store(first.id)
                    } label: {
                        Label("Einkauf starten", systemImage: "cart.fill")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
                if briefing.inboxCount > 0 {
                    Button {
                        model.startTriage()
                    } label: {
                        Label("Zuordnen", systemImage: "tray.and.arrow.down")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
            .controlSize(.large)
            .minimumScaleFactor(0.85)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
