import ActivityKit
import Foundation
import MarqetCore

/// The Live Activity "Einkauf" (KONZEPT-WIDGETS §5). The store lives in the dynamic state, so one
/// activity follows the whole shopping round from store to store.
struct ShoppingActivityAttributes: ActivityAttributes {
    typealias ContentState = TripStatus

    let tripID: UUID
    let listTitle: String
}
