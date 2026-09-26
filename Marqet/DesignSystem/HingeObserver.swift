import SwiftUI

/// The iPhone Duo hinge (KONZEPT-DUO-IPAD §2.5). `.none` on devices without one and before iOS 27.1.
enum HingeState: Equatable {
    /// A hinge exists, but no pose was reported yet; the vertical system bar gave the Duo away.
    case present
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
            content.modifier(DuoObserver(state: $state))
        } else {
            content
        }
    }
}

/// Combines the reported pose with the vertical system bar, which only the Duo has and which is
/// known from the first layout on. The hinge pose may be missing: `onHingeChange` can report no
/// hinge until the first pose change (so in the simulator until one in the Device Hub).
@available(iOS 27.1, *)
private struct DuoObserver: ViewModifier {
    @Binding var state: HingeState
    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    @State private var reported: HingeState = .none

    private var combined: HingeState {
        reported != .none ? reported : (verticalEdge != nil ? .present : .none)
    }

    func body(content: Content) -> some View {
        content
            .onHingeChange { _, context in
                reported = HingeState(context.hinge)
            }
            .onChange(of: combined, initial: true) { _, new in
                state = new
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
