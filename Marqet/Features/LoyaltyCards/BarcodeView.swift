import CoreImage
import CoreImage.CIFilterBuiltins
import MarqetCore
import SwiftUI

/// A card's barcode, black on white, crisp at any size. EAN is drawn from its modules (Core Image
/// has no EAN generator); Code 128 and the 2D codes come from Core Image.
struct BarcodeView: View {
    let payload: String
    let symbology: BarcodeSymbology

    var body: some View {
        Group {
            if symbology == .ean13 || symbology == .ean8 {
                if let modules = EANBarcode.modules(for: payload) {
                    EANBars(modules: modules)
                } else {
                    unavailable
                }
            } else if let image = BarcodeImage.make(payload: payload, symbology: symbology) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                unavailable
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Barcode")
        .accessibilityValue(payload)
    }

    private var unavailable: some View {
        Label("Barcode nicht darstellbar", systemImage: "barcode")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Is this a 2D code (square) rather than a linear barcode?
    static func isSquare(_ symbology: BarcodeSymbology) -> Bool {
        symbology == .qr || symbology == .aztec
    }
}

private struct EANBars: View {
    let modules: [Bool]

    var body: some View {
        Canvas { context, size in
            // Scanners need a white quiet zone: 11 modules left, 7 right (GS1).
            let width = size.width / CGFloat(modules.count + 18)
            for (index, isBar) in modules.enumerated() where isBar {
                let rect = CGRect(x: CGFloat(index + 11) * width, y: 0, width: width, height: size.height)
                // No rounding per bar: uneven bar widths break the ratios the scanner reads.
                context.fill(Path(rect), with: .color(.black))
            }
        }
    }
}

enum BarcodeImage {
    private static let context = CIContext()

    static func make(payload: String, symbology: BarcodeSymbology) -> CGImage? {
        let output: CIImage?
        switch symbology {
        case .code128:
            let filter = CIFilter.code128BarcodeGenerator()
            guard let data = payload.data(using: .ascii) else { return nil }
            filter.message = data
            // Quiet zone around the bars; scanners fail without it on a card edge.
            filter.quietSpace = 10
            output = filter.outputImage
        case .qr:
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(payload.utf8)
            filter.correctionLevel = "M"
            output = filter.outputImage
        case .pdf417:
            let filter = CIFilter.pdf417BarcodeGenerator()
            filter.message = Data(payload.utf8)
            output = filter.outputImage
        case .aztec:
            let filter = CIFilter.aztecCodeGenerator()
            filter.message = Data(payload.utf8)
            output = filter.outputImage
        case .ean13, .ean8:
            return nil
        }
        guard let output else { return nil }
        return context.createCGImage(output, from: output.extent)
    }
}

#Preview {
    VStack(spacing: 24) {
        BarcodeView(payload: "4006381333931", symbology: .ean13).frame(height: 100)
        BarcodeView(payload: "PB 3083 1234", symbology: .code128).frame(height: 100)
        BarcodeView(payload: "https://marqet.app", symbology: .qr).frame(width: 160, height: 160)
    }
    .padding()
    .background(.white)
}
