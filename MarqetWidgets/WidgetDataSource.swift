import Foundation
import MarqetCore
import MarqetReminders

/// Fresh data for a timeline (KONZEPT-WIDGETS §9.2, step 2): the widget reads Reminders itself,
/// so items added by Siri or family appear without opening Marqet. Stores, walking order and what
/// Marqet learned come from the registry the app wrote; without access the app's last snapshot.
enum WidgetDataSource {
    private static let dictionary = try? CategoryDictionary.bundled()

    static func load(now: Date = .now) async -> WidgetSnapshot {
        let stored = SharedStore.snapshot
        guard let registry = SharedStore.registry, registry.status == .ready, let listID = registry.listID else {
            return stored
        }
        let gateway = EventKitGateway()
        guard gateway.authorizationStatus() == .fullAccess else { return stored }
        do {
            let matcher = StoreMatcher(stores: registry.stores)
            let open = try await gateway.openReminders(in: listID)
                .map { ShoppingItemMapper.item(from: $0, matcher: matcher) }
            let since = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            let completed = ((try? await gateway.completedReminders(in: listID, since: since)) ?? [])
                .map { ShoppingItemMapper.item(from: $0, matcher: matcher) }
            var classifier = CategoryClassifier(dictionary: dictionary ?? CategoryDictionary(categories: [:]))
            classifier.learned = registry.learnedCategories.mapValues { (category: $0, isCorrection: true) }
            return WidgetSnapshotBuilder.snapshot(
                registry: registry,
                items: open,
                recentlyCompleted: completed,
                classifier: classifier,
                trip: SharedStore.trip,
                now: now
            )
        } catch {
            return stored
        }
    }

    /// Every 30 minutes; every 10 while a trip runs (the app reloads right after each change anyway).
    static func nextReload(for snapshot: WidgetSnapshot, now: Date = .now) -> Date {
        now.addingTimeInterval(snapshot.trip == nil ? 30 * 60 : 10 * 60)
    }
}
