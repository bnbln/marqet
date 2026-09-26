import MarqetCore
import SwiftUI

extension StoreSortMode {
    var title: LocalizedStringResource {
        switch self {
        case .manual: "Manuell"
        case .distance: "Entfernung"
        case .smart: "Smart"
        }
    }
}

extension TravelMode {
    var title: LocalizedStringResource {
        switch self {
        case .walking: "Zu Fuß"
        case .driving: "Mit dem Auto"
        }
    }

    var systemImage: String {
        switch self {
        case .walking: "figure.walk"
        case .driving: "car"
        }
    }
}
