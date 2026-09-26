import MarqetPersistence
import MarqetReminders
import SwiftUI

struct PermissionView: View {
    let status: RemindersAuthorization

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("Zugriff auf Erinnerungen", systemImage: "checklist")
        } description: {
            if status == .notDetermined {
                Text("Marqet liest deine Einkaufsliste aus der Erinnerungen-App und sortiert sie nach Läden. Deine Einträge bleiben in Erinnerungen – auf deinem Gerät und in deinem iCloud.")
            } else {
                Text("Marqet braucht vollen Zugriff auf deine Erinnerungen. Du kannst ihn in den Einstellungen unter „Marqet“ erteilen.")
            }
        } actions: {
            if status == .notDetermined {
                Button("Zugriff erlauben") {
                    Task { await model.requestAccess() }
                }
                .buttonStyle(.glassProminent)
            } else {
                Button("Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.glassProminent)
            }
        }
    }
}

#Preview("Nicht gefragt") {
    PermissionView(status: .notDetermined)
        .environment(AppModel(gateway: InMemoryReminderGateway(status: .notDetermined), container: try! PersistenceContainer.make(inMemory: true), intelligence: UnavailableIntelligence()))
}

#Preview("Abgelehnt") {
    PermissionView(status: .denied)
        .environment(AppModel(gateway: InMemoryReminderGateway(status: .denied), container: try! PersistenceContainer.make(inMemory: true), intelligence: UnavailableIntelligence()))
}
