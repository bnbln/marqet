import MarqetCore
import SwiftUI

extension Color {
    /// Store and list colors are stored as `#RRGGBB`. Invalid values fall back to system gray.
    init(hex: String) {
        let rgb = RGBColor(hex: hex) ?? RGBColor(red: 0.557, green: 0.557, blue: 0.576)
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
