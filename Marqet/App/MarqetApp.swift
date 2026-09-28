import MarqetPersistence
import SwiftData
import SwiftUI

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
            AppModel.active = model
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
        // Widget and Live Activity buttons run in this process and act through this model.
        model.sharesWithWidgets = true
        AppModel.active = model
        _model = State(initialValue: model)
        _purchases = State(initialValue: PurchaseManager { [weak model] in model?.hasProEntitlement = $0 })
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(purchases)
                .task { await purchases.start() }
                .task {
                    await model.start()
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
            if phase == .active {
                Task { await model.refreshPhase() }
            }
            // Leaving the app: widgets get the latest state right away, not after the debounce.
            if phase == .background {
                Task { await model.syncWidgetsNow() }
            }
        }
    }
}
