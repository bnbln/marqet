import MarqetCore
import SwiftUI

/// Round store mark: bundled retailer favicon/logo, monogram, or SF Symbol fallback.
struct StoreBadge: View {
    let store: Store
    var size: CGFloat = 28

    var body: some View {
        Group {
            if store.catalogKey == "billa-plus", size > 28 {
                Image("billa-plus-wordmark")
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, size * 0.08)
                    .frame(width: size * 1.7, height: size * 0.7)
                    .background(.white, in: .rect(cornerRadius: size * 0.14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                            .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
                    }
            } else {
                ZStack {
                    if let logoAsset {
                        Circle().fill(.white)
                        Image(logoAsset)
                            .resizable()
                            .scaledToFit()
                            .padding(size * 0.12)
                    } else {
                        Circle().fill(Color(hex: store.colorHex))
                        symbol.foregroundStyle(foreground)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
            }
        }
        .accessibilityHidden(true)
    }

    private var logoAsset: String? {
        guard let key = store.catalogKey, StoreBrandLogos.keys.contains(key) else { return nil }
        return key
    }

    @ViewBuilder
    private var symbol: some View {
        switch store.symbol {
        case .monogram(let text):
            Text(text)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(size * 0.12)
        case .systemImage(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.46, weight: .semibold))
        }
    }

    private var foreground: Color {
        RGBColor(hex: store.colorHex)?.prefersDarkForeground == true ? .black.opacity(0.85) : .white
    }
}

private enum StoreBrandLogos {
    static let keys: Set<String> = [
        "aldi-sued", "aldi-nord", "lidl", "rewe", "edeka", "kaufland", "netto", "penny", "norma",
        "globus", "marktkauf", "tegut", "dm", "rossmann", "mueller", "alnatura", "denns", "bio-company",
        "hornbach", "obi", "bauhaus", "ikea", "getraenke-hoffmann", "billa", "billa-plus", "spar", "hofer",
        "bipa", "mpreis", "migros", "coop", "denner", "aldi-suisse", "volg", "manor",
    ]
}

#Preview {
    let catalog = try? StoreCatalog.bundled()
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: 16) {
            ForEach(catalog?.stores ?? []) { entry in
                VStack {
                    StoreBadge(store: entry.makeStore(sortIndex: 0), size: 44)
                    Text(entry.name).font(.caption).lineLimit(1)
                }
            }
        }
        .padding()
    }
}
