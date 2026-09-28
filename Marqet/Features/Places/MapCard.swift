import MapKit
import MarqetCore
import SwiftUI

/// First page of the deck: a still map with the saved branches of stores that have open items.
/// Tapping it zooms into the full map (`MapScreen`), like a store card into its full screen.
/// The header sits on top like the inbox's, so the map fills the rest of the card.
struct MapCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.cardZoomNamespace) private var zoomNamespace

    var body: some View {
        let pins = model.mapPins(found: []).filter { pin in
            pin.store.map { model.openItemCount(of: $0.id) > 0 } ?? false
        }
        Button { model.focus(.map) } label: {
            VStack(spacing: 0) {
                header(pins: pins)
                Map(initialPosition: pins.isEmpty ? .userLocation(fallback: .automatic) : .automatic, interactionModes: []) {
                    UserAnnotation()
                    ForEach(pins) { pin in
                        if let store = pin.store {
                            Annotation(store.name, coordinate: pin.coordinate.clCoordinate) {
                                StoreBadge(store: store, size: 30)
                                    .padding(2)
                                    .background(.white, in: .circle)
                                    .shadow(radius: 2, y: 1)
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cardSurface()
            .contentShape(.rect(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(.plain)
        .modifier(CardZoomSource(page: .map, namespace: zoomNamespace))
        .accessibilityLabel("Karte öffnen")
    }

    /// Gray like the inbox header; the open button looks like the lists' "…" button.
    private func header(pins: [MapPin]) -> some View {
        let storeCount = Set(pins.compactMap(\.store?.id)).count
        return HStack(spacing: 14) {
            Image(systemName: "map.fill")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.2), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Karte")
                    .font(.title2.bold())
                    .lineLimit(1)
                Text(subtitle(storeCount: storeCount))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.22), in: .circle)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.gray, .gray.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func subtitle(storeCount: Int) -> LocalizedStringKey {
        switch storeCount {
        case 0: "Filialen deiner Läden in der Nähe"
        case 1: "1 Laden mit offenen Einträgen"
        default: "\(storeCount) Läden mit offenen Einträgen"
        }
    }
}
