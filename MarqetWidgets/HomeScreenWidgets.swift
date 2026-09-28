import AppIntents
import MarqetCore
import SwiftUI
import WidgetKit

// Home Screen, Lock Screen and StandBy widgets (KONZEPT-WIDGETS §4).

/// One timeline entry: the snapshot plus the widget's configuration.
struct MarqetEntry<Intent: WidgetConfigurationIntent>: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let configuration: Intent
    /// Higher while a trip runs, so the Smart Stack shows the list in the store.
    var relevance: TimelineEntryRelevance?
}

/// Shared provider: gallery and placeholders use sample data, timelines read Reminders live.
struct MarqetProvider<Intent: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    typealias Entry = MarqetEntry<Intent>

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snapshot: .sample, configuration: Intent())
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let snapshot = context.isPreview ? previewSnapshot() : await WidgetDataSource.load()
        return Entry(date: .now, snapshot: snapshot, configuration: configuration)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date.now
        let snapshot = await WidgetDataSource.load(now: now)
        let entry = Entry(date: now, snapshot: snapshot, configuration: configuration,
                          relevance: TimelineEntryRelevance(score: snapshot.trip == nil ? 0 : 1))
        return Timeline(entries: [entry], policy: .after(WidgetDataSource.nextReload(for: snapshot, now: now)))
    }

    /// The widget gallery shows the user's own lists once the app wrote them, else the demo shop.
    private func previewSnapshot() -> WidgetSnapshot {
        let stored = SharedStore.snapshot
        return stored.status == .ready && stored.totalOpenCount > 0 ? stored : .sample
    }
}

/// Gets the family from the environment, so the shared views can stay plain parameters.
private struct FamilyReader<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @ViewBuilder var content: (WidgetFamily) -> Content

    var body: some View { content(family) }
}

// MARK: - Liste

struct ListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.list, intent: ListWidgetIntent.self, provider: MarqetProvider<ListWidgetIntent>()) { entry in
            FamilyReader { family in
                ListWidgetView(
                    snapshot: entry.snapshot,
                    list: entry.configuration.list?.kind ?? .automatic,
                    showsSections: entry.configuration.showsSections,
                    family: family
                )
            }
            .containerBackground(for: .widget) { ListWidgetView.background }
        }
        .configurationDisplayName("Liste")
        .description("Ein Laden, die Inbox oder der nächste Laden – abhaken direkt im Widget.")
        .supportedFamilies(WidgetFamily.systemFamilies + [.accessoryRectangular, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

// MARK: - Überblick

struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.overview, intent: OverviewWidgetIntent.self, provider: MarqetProvider<OverviewWidgetIntent>()) { entry in
            FamilyReader { family in
                OverviewWidgetView(
                    snapshot: entry.snapshot,
                    order: entry.configuration.order,
                    showsInbox: entry.configuration.showsInbox,
                    family: family
                )
            }
            .containerBackground(for: .widget) { OverviewWidgetView.background }
        }
        .configurationDisplayName("Überblick")
        .description("Alle Läden mit offenen Einträgen – und der Einkauf mit einem Tipp.")
        .supportedFamilies(WidgetFamily.systemFamilies + [.accessoryRectangular, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

// MARK: - Kundenkarte

struct LoyaltyCardWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.loyaltyCard, intent: LoyaltyCardWidgetIntent.self, provider: MarqetProvider<LoyaltyCardWidgetIntent>()) { entry in
            let card = (entry.configuration.card ?? .automatic).resolve(in: entry.snapshot)
            FamilyReader { family in
                LoyaltyCardWidgetView(snapshot: entry.snapshot, card: card, family: family)
            }
            .containerBackground(for: .widget) { LoyaltyCardWidgetView.background(for: card) }
        }
        .configurationDisplayName("Kundenkarte")
        .description("Ein Tipp bis zum Barcode an der Kasse.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

// MARK: - Angebote

struct OffersWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.offers, intent: OffersWidgetIntent.self, provider: MarqetProvider<OffersWidgetIntent>()) { entry in
            FamilyReader { family in
                OffersWidgetView(snapshot: entry.snapshot, storeID: entry.configuration.store?.id, family: family)
            }
            .containerBackground(for: .widget) { OffersWidgetView.background }
        }
        .configurationDisplayName("Angebote")
        .description("Die aktuellen Prospekte deiner Läden.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Previews

#Preview("Liste", as: .systemMedium) {
    ListWidget()
} timeline: {
    MarqetEntry(date: .now, snapshot: .sample, configuration: ListWidgetIntent())
}

#Preview("Überblick", as: .systemLarge) {
    OverviewWidget()
} timeline: {
    MarqetEntry(date: .now, snapshot: .sample, configuration: OverviewWidgetIntent())
}
