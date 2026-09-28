import MarqetCore
import SwiftUI

/// A customer card's barcode for widgets and the Live Activity. Widgets cannot draw with `Canvas`,
/// so EAN bars are a `Shape`; Code 128 and 2D codes come from Core Image like in the app.
struct WidgetBarcode: View {
    let payload: String
    let symbology: BarcodeSymbology

    var body: some View {
        Group {
            if symbology == .ean13 || symbology == .ean8, let modules = EANBarcode.modules(for: payload) {
                EANBarsShape(modules: modules).fill(.black)
            } else if let image = BarcodeImage.make(payload: payload, symbology: symbology) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "barcode")
                    .font(.title2)
                    .foregroundStyle(.black.opacity(0.4))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Barcode")
        .accessibilityValue(payload)
    }
}

/// EAN-13/EAN-8 bars with the GS1 quiet zones (11 modules left, 7 right).
struct EANBarsShape: Shape {
    let modules: [Bool]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width / CGFloat(modules.count + 18)
        for (index, isBar) in modules.enumerated() where isBar {
            path.addRect(CGRect(x: rect.minX + CGFloat(index + 11) * width, y: rect.minY, width: width, height: rect.height))
        }
        return path
    }
}
