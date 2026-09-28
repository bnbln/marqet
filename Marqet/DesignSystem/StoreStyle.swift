import MarqetCore
import SwiftUI

extension Store {
    var color: Color { Color(hex: colorHex) }

    /// Store color for text and symbols on the card surface: darkened in light mode, lightened
    /// in dark mode until it reaches WCAG AA (4.5:1) against `secondarySystemGroupedBackground`.
    var readableColor: Color {
        let base = RGBColor(hex: colorHex) ?? RGBColor(red: 0.557, green: 0.557, blue: 0.576)
        return Color(UIColor { traits in
            let background = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            background.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            let adjusted = base.adjusted(forContrast: 4.5, on: RGBColor(red: red, green: green, blue: blue))
            return UIColor(red: adjusted.red, green: adjusted.green, blue: adjusted.blue, alpha: 1)
        })
    }

    /// Text and symbols on top of the store color (black on yellow chains, white otherwise).
    var foregroundOnColor: Color {
        prefersDarkForeground ? .black.opacity(0.85) : .white
    }

    /// Color scheme for system controls on top of the store color: the dark variant (white
    /// symbols) on dark brand colors, the light one on bright colors such as yellow.
    var colorSchemeOnColor: ColorScheme {
        prefersDarkForeground ? .light : .dark
    }

    private var prefersDarkForeground: Bool {
        RGBColor(hex: colorHex)?.prefersDarkForeground == true
    }
}

extension StoreType {
    var displayName: String {
        switch self {
        case .discounter: String(localized: "Discounter")
        case .supermarket: String(localized: "Supermarkt")
        case .drugstore: String(localized: "Drogerie")
        case .organic: String(localized: "Bioladen")
        case .hardware: String(localized: "Baumarkt")
        case .furniture: String(localized: "Möbel & Einrichtung")
        case .beverage: String(localized: "Getränke")
        case .bakery: String(localized: "Bäckerei")
        case .butcher: String(localized: "Metzgerei")
        case .pharmacy: String(localized: "Apotheke")
        case .market: String(localized: "Markt")
        case .online: String(localized: "Online")
        case .other: String(localized: "Sonstiges")
        }
    }

    var defaultSymbol: String {
        switch self {
        case .discounter, .supermarket: "cart.fill"
        case .drugstore: "drop.fill"
        case .organic: "leaf.fill"
        case .hardware: "hammer.fill"
        case .furniture: "sofa.fill"
        case .beverage: "wineglass.fill"
        case .bakery: "birthday.cake.fill"
        case .butcher: "fork.knife"
        case .pharmacy: "cross.case.fill"
        case .market: "carrot.fill"
        case .online: "shippingbox.fill"
        case .other: "bag.fill"
        }
    }
}

/// Curated colors and symbols for custom stores (KONZEPT §7.8). Each color carries white text.
enum StorePalette {
    static let colors = [
        "#C8323C", "#E0662B", "#D99A1E", "#5E9E3C", "#2E8B6E", "#23879B",
        "#2F6FB0", "#3F4FB5", "#7A4FBF", "#B0449A", "#8A6A4F", "#56657A",
    ]

    static let symbols = [
        "cart.fill", "basket.fill", "bag.fill", "carrot.fill", "leaf.fill", "fish.fill",
        "birthday.cake.fill", "cup.and.saucer.fill", "wineglass.fill", "drop.fill",
        "pills.fill", "hammer.fill", "pawprint.fill", "gift.fill", "tshirt.fill", "shippingbox.fill",
    ]
}

/// The rounded, opaque card surface (opaque for legibility in bright stores, KONZEPT §7.7).
struct CardSurface: ViewModifier {
    /// Soft glow in the store color below the card; it shows through the glass controls.
    var glowColor: Color?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .background(alignment: .bottom) {
                if let glowColor {
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .fill(glowColor)
                        .frame(height: 90)
                        .padding(.horizontal, 20)
                        .offset(y: 34)
                        .blur(radius: 56)
                        // Colored light reads much stronger on the pale light-mode background.
                        .opacity(colorScheme == .dark ? 0.2 : 0.08)
                        .accessibilityHidden(true)
                }
            }
    }
}

extension View {
    func cardSurface(glowColor: Color? = nil) -> some View {
        modifier(CardSurface(glowColor: glowColor))
    }

    /// iPhone Duo / iPad: sheets open on the leading half so the active card stays visible
    /// (KONZEPT-DUO-IPAD §4.2). No effect before iOS 27 or on compact width.
    @ViewBuilder
    func leadingSheetPlacement() -> some View {
        if #available(iOS 27.0, *) {
            presentationPlacement(.leading)
        } else {
            self
        }
    }
}
