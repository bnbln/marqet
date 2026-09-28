import MapKit
import MarqetCore
import SwiftUI

/// Supporting information for a store, shown below its brand header in the zoom detail view.
struct StoreContextPane: View {
    let store: Store
    @Environment(AppModel.self) private var model
    @State private var showsMap = false

    private var location: StoreLocation? { model.relevantLocation(of: store.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OffersSection(store: store)
                LoyaltyCardsSection(store: store)
                branchSection
                if let detail = store.detail, !detail.isEmpty {
                    Label(detail, systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Color(.secondarySystemGroupedBackground)
                .contentShape(Rectangle())
                .onTapGesture {
                    if model.composerTarget != nil { model.endComposer() }
                }
        }
        .sheet(isPresented: $showsMap) { MapScreen(focusedStoreID: store.id).leadingSheetPlacement() }
    }

    @ViewBuilder
    private var branchSection: some View {
        if let location {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Filiale", systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(store.readableColor)
                    Spacer()
                    Button("Karte") { showsMap = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                BranchMapPreview(store: store, location: location)
                    .frame(height: 164)
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("Karte mit der gespeicherten Filiale von \(store.name)")

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(location.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let address = location.address, !address.isEmpty {
                            Text(address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let distance = model.distanceText(to: store.id) {
                            Text(distance)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        openRoute(to: location)
                    } label: {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .background(Color(.tertiarySystemFill), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Route zu \(store.name)")
                }
                .padding(.horizontal, 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Noch keine Filiale", systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(store.readableColor)
                Button { showsMap = true } label: {
                    Label("Filiale auf der Karte suchen", systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func openRoute(to location: StoreLocation) {
        let item = MKMapItem(
            location: CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            address: nil
        )
        item.name = store.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}

private struct BranchMapPreview: View {
    let store: Store
    let location: StoreLocation

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            latitudinalMeters: 1_200,
            longitudinalMeters: 1_200
        )
    }

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            Annotation(store.name, coordinate: region.center, anchor: .bottom) {
                StoreBadge(store: store, size: 32)
                    .padding(2)
                    .background(.white, in: .circle)
                    .shadow(radius: 3, y: 1)
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControlVisibility(.hidden)
    }
}
