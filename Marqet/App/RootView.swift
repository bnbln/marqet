import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppAccentPalette.storageKey) private var accentPaletteKey = AppAccentPalette.leaf.rawValue

    private var accentColor: Color {
        AppAccentPalette(rawValue: accentPaletteKey)?.color ?? AppAccentPalette.leaf.color
    }

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
        .tint(accentColor)
        .sheet(isPresented: $model.showsPaywall) {
            PaywallView()
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
