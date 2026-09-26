import MarqetCore
import SwiftUI

/// Round store mark: monogram for chains, SF Symbol for generic stores (no logos, KONZEPT §8).
struct StoreBadge: View {
    let store: Store
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: store.colorHex))
            symbol.foregroundStyle(foreground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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
