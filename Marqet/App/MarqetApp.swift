import MarqetPersistence
import SwiftData
import SwiftUI
import UserNotifications

@main
struct MarqetApp: App {
    @State private var model: AppModel
    @State private var purchases: PurchaseManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // `-demo`: in-memory data for screenshots and simulator checks without Reminders access.
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            let model = AppModel.demo(isPro: ProcessInfo.processInfo.arguments.contains("-pro"))
            model.sharesWithWidgets = true
            // `-demo-arrival`: arrival alerts on, for geofence checks with `simctl location`.
            if ProcessInfo.processInfo.arguments.contains("-demo-arrival") { model.arrivalAlertsEnabled = true }
            Self.prepareBackgroundWork(for: model)
            _model = State(initialValue: model)
            _purchases = State(initialValue: PurchaseManager { [weak model] in model?.hasProEntitlement = $0 })
            return
        }
        #endif
        let container: ModelContainer
        do {
            container = try PersistenceContainer.make()
        } catch {
            // A broken on-disk store must not brick the app; stores are re-detected from markers.
            container = try! PersistenceContainer.make(inMemory: true)
        }
        let model = AppModel(container: container)
        model.sharesWithWidgets = true
        Self.prepareBackgroundWork(for: model)
        _model = State(initialValue: model)
        _purchases = State(initialValue: PurchaseManager { [weak model] in model?.hasProEntitlement = $0 })
    }

    /// Everything that must be ready before a background launch delivers its event: widget and
    /// Live Activity buttons act through this model, arrival notifications need their handler,
    /// and after an arrival relaunch the geofence event waits for the monitor (KONZEPT-WIDGETS §13).
    private static func prepareBackgroundWork(for model: AppModel) {
        AppModel.active = model
        UNUserNotificationCenter.current().delegate = NotificationResponder.shared
        ArrivalNotifier.registerCategory()
        if model.arrivalAlertsEnabled {
            Task { await model.startPresenceMonitor() }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(purchases)
                .task { await purchases.start() }
                .task {
                    model.isInForeground = true
                    await model.start()
                    await model.updatePresence()
                    #if DEBUG
                    // `-triage`: open the triage screen right away (screenshots).
                    if ProcessInfo.processInfo.arguments.contains("-paywall") {
                        model.showsPaywall = true
                    }
                    if ProcessInfo.processInfo.arguments.contains("-triage") {
                        try? await Task.sleep(for: .seconds(1))
                        model.startTriage()
                    }
                    #endif
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // No background push from EventKit – refresh whenever the app comes to the foreground.
            model.isInForeground = phase == .active
            if phase == .active {
                Task {
                    await model.refreshPhase()
                    // At a store? Then its list comes first (KONZEPT-WIDGETS §13).
                    await model.updatePresence()
                }
            }
            // Leaving the app: widgets get the latest state right away, not after the debounce.
            if phase == .background {
                Task { await model.syncWidgetsNow() }
            }
        }
    }
}
