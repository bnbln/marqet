import SwiftUI

enum AppAccentPalette: String, CaseIterable, Identifiable {
    static let storageKey = "appAccentPalette"

    case leaf
    case ocean
    case amber
    case violet
    case coral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leaf: String(localized: "Blattgrün")
        case .ocean: String(localized: "Ozeanblau")
        case .amber: String(localized: "Bernstein")
        case .violet: String(localized: "Violett")
        case .coral: String(localized: "Koralle")
        }
    }

    var color: Color { Color(hex: hex) }

    /// Also written for the widgets, which cannot read the app's settings.
    var hex: String {
        switch self {
        case .leaf: "#238A5D"
        case .ocean: "#286BC7"
        case .amber: "#B96620"
        case .violet: "#7651B8"
        case .coral: "#C94E55"
        }
    }
}
