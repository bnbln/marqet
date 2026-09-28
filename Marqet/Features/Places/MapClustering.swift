import MapKit
import MarqetCore

/// What the map draws: one pin, or nearby pins merged into one bubble.
enum MapMarker: Identifiable, Equatable {
    case pin(MapPin)
    case cluster(MapCluster)

    var id: String {
        switch self {
        case .pin(let pin): pin.id
        case .cluster(let cluster): cluster.id
        }
    }

    var coordinate: GeoPoint {
        switch self {
        case .pin(let pin): pin.coordinate
        case .cluster(let cluster): cluster.coordinate
        }
    }
}

/// Pins that would overlap on screen at the current zoom.
struct MapCluster: Identifiable, Equatable {
    let id: String
    let pins: [MapPin]
    /// Center of the pins in map projection, so the bubble sits where they are.
    let coordinate: GeoPoint

    /// The area covering all pins, with some room around them – tapping the bubble zooms there.
    var zoomRect: MKMapRect {
        let points = pins.map { MKMapPoint($0.coordinate.clCoordinate) }
        let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 0
        // At least ~400 m across, so a tight cluster does not zoom to street level.
        let minimum = MKMapPointsPerMeterAtLatitude(coordinate.latitude) * 400
        let width = max((maxX - minX) * 1.6, minimum)
        let height = max((maxY - minY) * 1.6, minimum)
        return MKMapRect(x: (minX + maxX - width) / 2, y: (minY + maxY - height) / 2, width: width, height: height)
    }
}

/// Grid clustering in screen space (KONZEPT §14.1): with dozens of shops around, single pins
/// only show once they no longer overlap. Own saved branches and search results never merge –
/// they are what the user is looking for. Pins far outside the visible area are left out, so
/// MapKit only lays out what can be seen.
enum MapClustering {
    /// - Parameters:
    ///   - visibleRect: The map's visible area.
    ///   - viewWidth: The map's width in points, to turn `cellPoints` into map distance.
    ///   - cellPoints: Pins closer than this on screen merge.
    static func markers(for pins: [MapPin], in visibleRect: MKMapRect, viewWidth: CGFloat, cellPoints: CGFloat = 64) -> [MapMarker] {
        guard viewWidth > 0, visibleRect.size.width > 0 else { return pins.map(MapMarker.pin) }
        // Half a screen of margin: panning a little does not reveal an empty edge.
        let margin = visibleRect.insetBy(dx: -visibleRect.size.width / 2, dy: -visibleRect.size.height / 2)
        let cell = visibleRect.size.width / viewWidth * cellPoints

        var markers: [MapMarker] = []
        var cells: [Cell: [MapPin]] = [:]
        var order: [Cell] = []
        for pin in pins {
            let point = MKMapPoint(pin.coordinate.clCoordinate)
            guard margin.contains(point) else { continue }
            guard mergeable(pin) else {
                markers.append(.pin(pin))
                continue
            }
            let key = Cell(x: Int((point.x / cell).rounded(.down)), y: Int((point.y / cell).rounded(.down)))
            if cells[key] == nil { order.append(key) }
            cells[key, default: []].append(pin)
        }
        for key in order {
            guard let members = cells[key] else { continue }
            if members.count == 1 {
                markers.append(.pin(members[0]))
            } else {
                markers.append(.cluster(MapCluster(id: "cluster:\(key.x):\(key.y)", pins: members, coordinate: center(of: members))))
            }
        }
        return markers
    }

    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    private static func mergeable(_ pin: MapPin) -> Bool {
        switch pin.kind {
        case .branch, .suggestion: true
        case .saved, .place: false
        }
    }

    private static func center(of pins: [MapPin]) -> GeoPoint {
        let points = pins.map { MKMapPoint($0.coordinate.clCoordinate) }
        let x = points.map(\.x).reduce(0, +) / Double(points.count)
        let y = points.map(\.y).reduce(0, +) / Double(points.count)
        let coordinate = MKMapPoint(x: x, y: y).coordinate
        return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
