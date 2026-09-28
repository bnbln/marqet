import MapKit
import MarqetCore
import Testing
@testable import Marqet

/// Marienplatz, Munich.
private let center = GeoPoint(latitude: 48.1374, longitude: 11.5755)

private func shop(_ name: String, metersNorth: Double, metersEast: Double = 0) -> PlaceResult {
    PlaceResult(
        name: name,
        address: nil,
        coordinate: GeoPoint(
            latitude: center.latitude + metersNorth / 111_320,
            longitude: center.longitude + metersEast / (111_320 * cos(center.latitude * .pi / 180))
        ),
        mapItemIdentifier: "\(name)-\(metersNorth)-\(metersEast)",
        suggestedType: .supermarket
    )
}

private func suggestion(_ name: String, metersNorth: Double, metersEast: Double = 0) -> MapPin {
    MapPin(kind: .suggestion(shop(name, metersNorth: metersNorth, metersEast: metersEast), chainKey: name.lowercased()), store: nil)
}

/// A square around Marienplatz, `meters` wide.
private func visibleRect(meters: Double) -> MKMapRect {
    let middle = MKMapPoint(center.clCoordinate)
    let size = MKMapPointsPerMeterAtLatitude(center.latitude) * meters
    return MKMapRect(x: middle.x - size / 2, y: middle.y - size / 2, width: size, height: size)
}

@Suite("Karten-Cluster")
struct MapClusteringTests {
    @Test func nearbyShopsMergeWhenZoomedOut() {
        let pins = [suggestion("Aldi", metersNorth: 0), suggestion("Lidl", metersNorth: 30), suggestion("Penny", metersNorth: 60)]
        // 10 km on 400 pt: the three shops are less than 3 pt apart.
        let markers = MapClustering.markers(for: pins, in: visibleRect(meters: 10_000), viewWidth: 400)
        #expect(markers.count == 1)
        guard case .cluster(let cluster) = markers.first else {
            Issue.record("Expected one cluster")
            return
        }
        #expect(cluster.pins.count == 3)
        // Tapping zooms in to at least 400 m around the shops.
        #expect(cluster.zoomRect.size.width >= MKMapPointsPerMeterAtLatitude(center.latitude) * 399)
    }

    @Test func shopsSplitWhenZoomedIn() {
        let pins = [suggestion("Aldi", metersNorth: 0), suggestion("Lidl", metersNorth: 300), suggestion("Penny", metersNorth: -300)]
        // 1 km on 400 pt: 300 m are 120 pt – far enough apart for single pins.
        let markers = MapClustering.markers(for: pins, in: visibleRect(meters: 1_000), viewWidth: 400)
        #expect(markers.count == 3)
        #expect(markers.allSatisfy { if case .pin = $0 { true } else { false } })
    }

    @Test func searchResultsNeverMerge() {
        let pins = [
            MapPin(kind: .place(shop("Hofladen", metersNorth: 0)), store: nil),
            suggestion("Aldi", metersNorth: 10),
        ]
        let markers = MapClustering.markers(for: pins, in: visibleRect(meters: 10_000), viewWidth: 400)
        #expect(markers.count == 2)
    }

    @Test func pinsFarOutsideTheMapAreLeftOut() {
        let pins = [suggestion("Aldi", metersNorth: 0), suggestion("Lidl", metersNorth: 5_000)]
        let markers = MapClustering.markers(for: pins, in: visibleRect(meters: 1_000), viewWidth: 400)
        #expect(markers.map(\.id) == [pins[0].id])
    }
}
