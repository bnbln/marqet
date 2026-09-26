import MarqetPersistence
import SwiftData
import SwiftUI

@main
struct MarqetApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // `-demo`: in-memory data for screenshots and simulator checks without Reminders access.
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            _model = State(initialValue: .demo(isPro: ProcessInfo.processInfo.arguments.contains("-pro")))
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
        _model = State(initialValue: AppModel(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            // No background push from EventKit – refresh whenever the app comes to the foreground.
            if phase == .active {
                Task { await model.refreshPhase() }
            }
        }
    }
}
