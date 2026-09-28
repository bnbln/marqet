import MarqetCore
import SwiftUI

/// Round store mark: bundled retailer favicon/logo, monogram, or SF Symbol fallback.
struct StoreBadge: View {
    let store: Store
    var size: CGFloat = 28

    /// Fallback switch for trademark issues (PLAN E1): build setting `MARQET_BRAND_LOGOS = NO`
    /// turns every brand mark – logo assets and the drawn Edeka/Netto marks – into monograms,
    /// so a rejected build can be resubmitted within a day.
    static let usesBrandLogos: Bool = {
        // The build setting arrives as the string "YES"/"NO", a hand-edited plist may hold a Bool.
        switch Bundle.main.object(forInfoDictionaryKey: "MarqetUsesBrandLogos") {
        case let flag as Bool: flag
        case let text as String: !["NO", "FALSE", "0"].contains(text.uppercased())
        default: true
        }
    }()

    var body: some View {
        Group {
            if Self.usesBrandLogos, store.catalogKey == "edeka" {
                Image("edeka")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.82, height: size)
                    .clipShape(.rect(cornerRadius: size * 0.1, style: .continuous))
                    .frame(width: size, height: size)
            } else {
                ZStack {
                    if Self.usesBrandLogos, store.catalogKey == "netto" {
                        Circle().fill(Color(red: 0.88, green: 0.02, blue: 0.08))
                        Text("N")
                            .font(.system(size: size * 0.67, weight: .black, design: .rounded).italic())
                            .foregroundStyle(.yellow)
                    } else if let logoAsset {
                        Circle().fill(.white)
                        Image(logoAsset)
                            .resizable()
                            .scaledToFit()
                            .padding(size * (Self.fullBleedLogos.contains(logoAsset) ? 0 : 0.06))
                    } else {
                        Circle().fill(Color(hex: store.colorHex))
                        symbol.foregroundStyle(foreground)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.black.opacity(0.1), lineWidth: 0.5))
            }
        }
        .accessibilityHidden(true)
    }

    private static let fullBleedLogos: Set<String> = [
        "rewe", "lidl", "ikea", "penny", "billa", "bipa", "norma", "aldi-suisse",
        "bio-company", "tegut", "volg", "obi", "hornbach",
        // Already laid out for the circle (ASSET_SOURCES.md).
        "nahkauf", "hit", "famila", "combi", "budni", "sephora", "douglas", "flaconi", "kadewe",
        "breuninger", "galeria", "peek-cloppenburg", "hm", "zara", "uniqlo", "c-and-a", "tk-maxx",
        "primark", "deichmann", "snipes", "mediamarkt", "saturn", "cyberport", "decathlon",
        "intersport", "thalia", "hugendubel", "fressnapf", "zoo-and-co", "moemax", "xxxlutz",
    ]

    private var logoAsset: String? {
        guard Self.usesBrandLogos, let key = store.catalogKey, StoreBrandLogos.keys.contains(key) else { return nil }
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
        "nahkauf", "hit", "famila", "combi", "budni", "sephora", "douglas", "flaconi", "kadewe",
        "breuninger", "galeria", "peek-cloppenburg", "hm", "zara", "uniqlo", "c-and-a", "tk-maxx",
        "primark", "deichmann", "snipes", "mediamarkt", "saturn", "cyberport", "decathlon",
        "intersport", "thalia", "hugendubel", "fressnapf", "zoo-and-co", "moemax", "xxxlutz",
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
