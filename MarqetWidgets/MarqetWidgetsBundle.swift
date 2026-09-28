import SwiftUI
import WidgetKit

/// Widgets, Live Activity and controls of Marqet (KONZEPT-WIDGETS).
@main
struct MarqetWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ListWidget()
        OverviewWidget()
        LoyaltyCardWidget()
        OffersWidget()
        ShoppingTripLiveActivity()
        AddItemControl()
        LoyaltyCardControl()
        TripControl()
    }
}
