import SwiftUI

/// The iPhone Duo hinge (KONZEPT-DUO-IPAD §2.5). `.none` on devices without one and before iOS 27.1.
enum HingeState: Equatable {
    case none, closed, partiallyOpen, fullyOpen

    var hasHinge: Bool { self != .none }
    /// The inner display is in use (flat or angled).
    var isUnfolded: Bool { self == .partiallyOpen || self == .fullyOpen }
}

extension View {
    func observeHinge(_ state: Binding<HingeState>) -> some View {
        modifier(HingeObserver(state: state))
    }
}

private struct HingeObserver: ViewModifier {
    @Binding var state: HingeState

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                state = HingeState(context.hinge)
            }
        } else {
            content
        }
    }
}

@available(iOS 27.1, *)
private extension HingeState {
    init(_ hinge: DeviceHinge?) {
        guard let hinge else {
            self = .none
            return
        }
        if hinge.status == .closed {
            self = .closed
        } else if hinge.status == .partiallyOpen {
            self = .partiallyOpen
        } else {
            self = .fullyOpen
        }
    }
}
