#if DEBUG
import MarqetCore
import SwiftUI
import WidgetKit

/// Debug `-widget-showcase`: the widgets with the demo lists arranged like a Home Screen,
/// for App Store screenshots (docs/KONZEPT-SCREENSHOTS.md). Same views as the gallery.
struct WidgetShowcaseView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var snapshot = WidgetSnapshot.sampleWithoutTrip

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 28) {
                    VStack(spacing: 28) { smallRow; inbox; largeList }
                    VStack(spacing: 28) { largeOverview; mediumList }
                }
            } else {
                VStack(spacing: 24) { smallRow; inbox; largeOverview }
            }
        }
        // Tiles take their Home Screen size instead of stretching to the screen.
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(colors: [Color(hex: "#DCE5EE"), Color(hex: "#EFE6DD"), Color(hex: "#F4DCD2")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
        .task(id: model.items) {
            let own = model.makeWidgetSnapshot()
            if own.status == .ready, own.totalOpenCount > 0 { snapshot = own }
        }
    }

    private var smallRow: some View {
        HStack(spacing: 24) {
            tile(.systemSmall) { ListWidgetView(snapshot: snapshot, list: .automatic, family: .systemSmall) }
            WidgetPreviewTile(family: .systemSmall, background: OverviewWidgetView.background) {
                OverviewWidgetView(snapshot: snapshot, family: .systemSmall)
            }
        }
    }

    private var inbox: some View {
        tile(.systemMedium) { ListWidgetView(snapshot: snapshot, list: .inbox, family: .systemMedium) }
    }

    private var mediumList: some View {
        tile(.systemMedium) { ListWidgetView(snapshot: snapshot, list: .automatic, family: .systemMedium) }
    }

    private var largeList: some View {
        tile(.systemLarge) { ListWidgetView(snapshot: snapshot, list: .automatic, family: .systemLarge) }
    }

    private var largeOverview: some View {
        WidgetPreviewTile(family: .systemLarge, background: OverviewWidgetView.background) {
            OverviewWidgetView(snapshot: snapshot, family: .systemLarge)
        }
    }

    private func tile(_ family: WidgetFamily, @ViewBuilder content: () -> some View) -> some View {
        WidgetPreviewTile(family: family, background: ListWidgetView.background, content: content)
    }
}
#endif
