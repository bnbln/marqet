import MarqetCore
import SwiftUI
import Vision
import VisionKit

/// Camera scan of a card's barcode (VisionKit). Reports the first recognized code once.
struct BarcodeScanner: UIViewControllerRepresentable {
    var onScan: (String, MarqetCore.BarcodeSymbology) -> Void

    /// Scanning needs a camera and the Neural Engine – never true in the simulator.
    @MainActor static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.symbologies)],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private static let symbologies: [VNBarcodeSymbology] = [.ean13, .ean8, .code128, .qr, .pdf417, .aztec]

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: BarcodeScanner
        private var hasReported = false

        init(parent: BarcodeScanner) { self.parent = parent }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasReported else { return }
            for item in items {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue, !payload.isEmpty,
                      let symbology = Self.symbology(for: barcode.observation.symbology) else { continue }
                hasReported = true
                scanner.stopScanning()
                parent.onScan(payload, symbology)
                return
            }
        }

        static func symbology(for vision: VNBarcodeSymbology) -> MarqetCore.BarcodeSymbology? {
            switch vision {
            case .ean13: .ean13
            case .ean8: .ean8
            case .code128: .code128
            case .qr: .qr
            case .pdf417: .pdf417
            case .aztec: .aztec
            default: nil
            }
        }
    }
}
