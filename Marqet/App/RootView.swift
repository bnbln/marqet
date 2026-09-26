import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Group {
            if !model.hasCompletedOnboarding {
                OnboardingFlow()
            } else {
                switch model.phase {
            case .launching:
                ProgressView()
            case .needsPermission(let status):
                PermissionView(status: status)
            case .needsList:
                ListPickerView()
            case .ready:
                ShoppingScreen()
            }
            }
        }
        .alert(
            "Das hat nicht geklappt",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(model.errorMessage ?? "") }
        )
    }
}
