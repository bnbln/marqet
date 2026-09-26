import MarqetCore
import SwiftUI

/// A store as a round badge with its name below, in a rounded square. The one component wherever
/// a store is picked: "Weitere Läden" and Zuordnen (single and board).
struct StoreTile<Badge: View>: View {
    let name: String
    /// Small line below the name, e.g. "Wie zuletzt" on a suggestion.
    var caption: String?
    var captionSymbol: String?
    /// Suggestion: the square is tinted and outlined in this color.
    var highlight: Color?
    /// `nil` outside a multi-selection.
    var isSelected: Bool?
    var isDimmed = false
    var fill: Color = Color(.tertiarySystemFill)
    @ViewBuilder let badge: () -> Badge

    var body: some View {
        VStack(spacing: 6) {
            badge()
                .overlay(alignment: .topTrailing) {
                    if let isSelected {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .background(Circle().fill(Color(.systemBackground)))
                            .offset(x: 6, y: -6)
                    }
                }
            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            if let caption {
                Label {
                    Text(caption)
                } icon: {
                    if let captionSymbol { Image(systemName: captionSymbol) }
                }
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(highlight ?? .secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .top)
        .background(highlight.map { $0.opacity(0.14) } ?? fill, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(highlight ?? .clear, lineWidth: 2)
        }
        .opacity(isDimmed ? 0.5 : 1)
        .contentShape(.rect(cornerRadius: 20, style: .continuous))
    }
}

extension StoreTile where Badge == StoreBadge {
    init(store: Store, caption: String? = nil, captionSymbol: String? = nil, highlight: Color? = nil,
         isSelected: Bool? = nil, isDimmed: Bool = false, fill: Color = Color(.tertiarySystemFill)) {
        self.init(name: store.name, caption: caption, captionSymbol: captionSymbol, highlight: highlight,
                  isSelected: isSelected, isDimmed: isDimmed, fill: fill) {
            StoreBadge(store: store, size: 48)
        }
    }
}

/// "Laden hinzufügen" in the same shape as a store tile.
struct AddStoreTile: View {
    var fill: Color = Color(.tertiarySystemFill)

    var body: some View {
        StoreTile(name: String(localized: "Laden hinzufügen"), fill: fill) {
            Image(systemName: "plus")
                .font(.title2.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .background(Color(.systemFill), in: .circle)
        }
    }
}

/// "Läden zuordnen" – a glass button like the add button, in the accent color.
struct TriageButton: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppAccentPalette.storageKey) private var accentPaletteKey = AppAccentPalette.leaf.rawValue

    var body: some View {
        Button {
            model.startTriage()
        } label: {
            Label("Läden zuordnen", systemImage: "tray.and.arrow.down.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 52)
                .glassEffect(.regular.tint(AppAccentPalette(rawValue: accentPaletteKey)?.color ?? AppAccentPalette.leaf.color).interactive(), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}
