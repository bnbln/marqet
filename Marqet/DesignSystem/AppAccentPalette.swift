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

    var color: Color {
        switch self {
        case .leaf: Color(hex: "#238A5D")
        case .ocean: Color(hex: "#286BC7")
        case .amber: Color(hex: "#B96620")
        case .violet: Color(hex: "#7651B8")
        case .coral: Color(hex: "#C94E55")
        }
    }
}
