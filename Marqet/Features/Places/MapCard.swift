import MapKit
import MarqetCore
import SwiftUI

/// First page of the deck: a still map with the saved branches of stores that have open items.
/// Tapping it zooms into the full map (`MapScreen`), like a store card into its full screen.
struct MapCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.cardZoomNamespace) private var zoomNamespace

    var body: some View {
        let pins = model.mapPins(found: []).filter { pin in
            pin.store.map { model.openItemCount(of: $0.id) > 0 } ?? false
        }
        Button { model.focus(.map) } label: {
            ZStack(alignment: .bottom) {
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

                footer(pins: pins)
            }
            .clipShape(.rect(cornerRadius: 30, style: .continuous))
            .contentShape(.rect(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(.plain)
        // Leave room below the card for Home's floating microphone and add button.
        .padding(.bottom, 48)
        .modifier(CardZoomSource(page: .map, namespace: zoomNamespace))
        .accessibilityLabel("Karte öffnen")
    }

    /// Opaque panel, so the text never sits on map colours.
    private func footer(pins: [MapPin]) -> some View {
        let storeCount = Set(pins.compactMap(\.store?.id)).count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Karte")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text(subtitle(storeCount: storeCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func subtitle(storeCount: Int) -> LocalizedStringKey {
        switch storeCount {
        case 0: "Filialen deiner Läden in der Nähe"
        case 1: "1 Laden mit offenen Einträgen"
        default: "\(storeCount) Läden mit offenen Einträgen"
        }
    }
}
