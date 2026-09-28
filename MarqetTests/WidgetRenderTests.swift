import MarqetCore
import SwiftUI
import Testing
import WidgetKit
@testable import Marqet

/// Renders every widget, the Live Activity and the Dynamic Island as PNGs for design review
/// (KONZEPT-WIDGETS §12). Runs only with an output folder:
/// `TEST_RUNNER_MARQET_WIDGET_RENDER_DIR=/path xcodebuild test … -only-testing:MarqetTests/WidgetRenderTests`
@MainActor
@Suite("Widgets als Bilder")
struct WidgetRenderTests {
    struct Shot {
        let name: String
        let size: CGSize
        let cornerRadius: CGFloat
        let background: AnyView
        let content: AnyView
    }

    static let small = CGSize(width: 170, height: 170)
    static let medium = CGSize(width: 364, height: 170)
    static let large = CGSize(width: 364, height: 382)
    static let extraLarge = CGSize(width: 364, height: 594)

    var shots: [Shot] {
        let snapshot = WidgetSnapshot.sample
        let status = snapshot.sampleTripStatus!
        var doneStatus = status
        doneStatus.openCount = 0
        doneStatus.doneCount = 9
        doneStatus.next = []
        let card = snapshot.automaticLoyaltyCard
        func shot(_ name: String, _ size: CGSize, radius: CGFloat = 24, background: some View, _ content: some View) -> Shot {
            Shot(name: name, size: size, cornerRadius: radius, background: AnyView(background), content: AnyView(content))
        }
        let list = ListWidgetView.background
        let gray = OverviewWidgetView.background
        var shots = [
            shot("liste-klein", Self.small, background: list, ListWidgetView(snapshot: snapshot, list: .automatic, family: .systemSmall)),
            shot("liste-mittel", Self.medium, background: list, ListWidgetView(snapshot: snapshot, list: .automatic, family: .systemMedium)),
            shot("liste-gross", Self.large, background: list, ListWidgetView(snapshot: snapshot, list: .automatic, family: .systemLarge)),
            shot("inbox-mittel", Self.medium, background: list, ListWidgetView(snapshot: snapshot, list: .inbox, family: .systemMedium)),
            shot("inbox-gross", Self.large, background: list, ListWidgetView(snapshot: snapshot, list: .inbox, family: .systemLarge)),
            shot("drogerie-mittel", Self.medium, background: list,
                 ListWidgetView(snapshot: snapshot, list: .store(snapshot.stores[1].id), family: .systemMedium)),
            shot("erledigt-klein", Self.small, background: list, ListWidgetView(snapshot: snapshot, list: .completed, family: .systemSmall)),
            shot("leer-mittel", Self.medium, background: list,
                 ListWidgetView(snapshot: snapshot, list: .store(snapshot.stores[3].id), family: .systemMedium)),
            shot("ueberblick-klein", Self.small, background: gray, OverviewWidgetView(snapshot: snapshot, family: .systemSmall)),
            shot("ueberblick-mittel", Self.medium, background: gray, OverviewWidgetView(snapshot: snapshot, family: .systemMedium)),
            shot("ueberblick-gross", Self.large, background: gray, OverviewWidgetView(snapshot: WidgetSnapshot.sampleWithoutTrip, family: .systemLarge)),
            shot("ueberblick-gross-einkauf", Self.large, background: gray, OverviewWidgetView(snapshot: snapshot, family: .systemLarge)),
            shot("kundenkarte-klein", Self.small, background: LoyaltyCardWidgetView.background(for: card),
                 LoyaltyCardWidgetView(snapshot: snapshot, card: card, family: .systemSmall)),
            shot("kundenkarte-mittel", Self.medium, background: LoyaltyCardWidgetView.background(for: card),
                 LoyaltyCardWidgetView(snapshot: snapshot, card: card, family: .systemMedium)),
            shot("angebote-klein", Self.small, background: gray, OffersWidgetView(snapshot: snapshot, family: .systemSmall)),
            shot("angebote-mittel", Self.medium, background: gray, OffersWidgetView(snapshot: snapshot, family: .systemMedium)),
            shot("angebote-gross", Self.large, background: gray, OffersWidgetView(snapshot: snapshot, family: .systemLarge)),
            shot("ipad-xl-ueberblick", CGSize(width: 715, height: 330), background: gray,
                 OverviewWidgetView(snapshot: snapshot, family: .systemExtraLarge)),
            shot("sperr-liste", CGSize(width: 172, height: 76), radius: 14, background: Color.black.opacity(0.8),
                 ListWidgetView(snapshot: snapshot, list: .automatic, family: .accessoryRectangular).foregroundStyle(.white)),
            shot("sperr-ueberblick", CGSize(width: 172, height: 76), radius: 14, background: Color.black.opacity(0.8),
                 OverviewWidgetView(snapshot: snapshot, family: .accessoryRectangular).foregroundStyle(.white)),
            shot("sperr-rund", CGSize(width: 76, height: 76), radius: 38, background: Color.black.opacity(0.8),
                 ListWidgetView(snapshot: snapshot, list: .automatic, family: .accessoryCircular).foregroundStyle(.white)),
            shot("live-sperrbildschirm", CGSize(width: 364, height: 160), background: status.store.color, TripLockScreenView(status: status)),
            shot("live-laden-fertig", CGSize(width: 364, height: 120), background: doneStatus.store.color, TripLockScreenView(status: doneStatus)),
            shot("live-insel-gross", CGSize(width: 371, height: 170), radius: 44, background: Color.black, IslandExpandedMock(status: status)),
            shot("live-insel-kompakt", CGSize(width: 250, height: 37), radius: 19, background: Color.black, IslandCompactMock(status: status)),
            shot("live-watch", CGSize(width: 180, height: 90), radius: 20, background: Color(white: 0.15), TripSmallView(status: status)),
        ]
        if #available(iOS 27.0, *) {
            shots.append(shot("liste-xl-hoch", Self.extraLarge, background: list,
                              ListWidgetView(snapshot: snapshot, list: .automatic, family: .systemExtraLargePortrait)))
            shots.append(shot("ueberblick-xl-hoch", Self.extraLarge, background: gray,
                              OverviewWidgetView(snapshot: snapshot, family: .systemExtraLargePortrait)))
        }
        return shots
    }

    @Test func rendersEveryWidgetInLightAndDark() throws {
        guard let path = ProcessInfo.processInfo.environment["MARQET_WIDGET_RENDER_DIR"] else { return }
        let directory = URL(filePath: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            for shot in shots {
                let view = shot.content
                    .frame(width: shot.size.width, height: shot.size.height)
                    .background(shot.background)
                    .clipShape(.rect(cornerRadius: shot.cornerRadius, style: .continuous))
                    .environment(\.colorScheme, scheme)
                    .environment(\.locale, Locale(identifier: "de_DE"))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                let data = try #require(renderer.uiImage?.pngData())
                try data.write(to: directory.appending(path: "\(shot.name)-\(scheme == .dark ? "dunkel" : "hell").png"))
            }
        }
    }
}

/// The expanded Dynamic Island's regions, arranged as the system does, for the render only.
private struct IslandExpandedMock: View {
    let status: TripStatus

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                WidgetBadge(store: status.store, size: 40)
                Spacer()
                VStack(spacing: 1) {
                    Text(status.store.name).font(.system(size: 16, weight: .bold))
                    Text("\(status.doneCount) von \(status.totalCount) erledigt")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(status.openCount, format: .number)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(status.store.colorOnDark)
                    Text("offen").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            TripExpandedBottom(status: status)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .environment(\.colorScheme, .dark)
    }
}

private struct IslandCompactMock: View {
    let status: TripStatus

    var body: some View {
        HStack {
            WidgetBadge(store: status.store, size: 22)
            Spacer()
            TripCompactTrailing(status: status)
        }
        .padding(.horizontal, 8)
        .environment(\.colorScheme, .dark)
    }
}
