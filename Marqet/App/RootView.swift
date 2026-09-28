import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppAccentPalette.storageKey) private var accentPaletteKey = AppAccentPalette.leaf.rawValue
    /// Debug: `-widget-gallery` opens Einstellungen › Widgets for screenshots.
    @State private var showsWidgetGallery = false
    /// Debug: `-widget-showcase` shows the widgets like a Home Screen (App Store screenshots).
    @State private var showsWidgetShowcase = false

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
        // Widgets, the Live Activity and controls (KONZEPT-WIDGETS §8).
        .onOpenURL { model.open($0) }
        .sheet(isPresented: $model.showsPaywall) {
            PaywallView()
        }
        .fullScreenCover(item: $model.presentedLoyaltyCards) { presentation in
            LoyaltyCardScreen(cards: presentation.cards, initialCardID: presentation.initialCardID)
        }
        .sheet(item: $model.presentedLeaflet) { leaflet in
            SafariView(url: leaflet.url).ignoresSafeArea()
        }
        .onChange(of: accentPaletteKey) {
            Task { await model.syncWidgetsNow() }
        }
        #if DEBUG
        .sheet(isPresented: $showsWidgetGallery) {
            NavigationStack { WidgetSettingsView() }
        }
        .task(id: model.hasLoadedItems) {
            if model.hasLoadedItems, ProcessInfo.processInfo.arguments.contains("-widget-gallery") {
                showsWidgetGallery = true
            }
            if model.hasLoadedItems, ProcessInfo.processInfo.arguments.contains("-widget-showcase") {
                showsWidgetShowcase = true
            }
        }
        .fullScreenCover(isPresented: $showsWidgetShowcase) {
            WidgetShowcaseView()
        }
        #endif
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
