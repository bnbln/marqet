import SwiftUI

/// Two panes side by side. From iOS 27.1 an `ArrangementView`, which puts the split exactly on
/// the iPhone Duo fold – beside each other at a vertical fold (book), above each other at a
/// horizontal one (half folded, flip); before that a plain `HStack` (KONZEPT-DUO-IPAD §4.4).
struct AdaptiveSplit<Primary: View, Secondary: View>: View {
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary

    var body: some View {
        if #available(iOS 27.1, *) {
            ArrangementView { primary } secondary: { secondary }
                .arrangementViewStyle(.split.axes([.horizontal, .vertical]))
        } else {
            HStack(spacing: 0) {
                primary.frame(maxWidth: .infinity)
                Divider()
                secondary.frame(maxWidth: .infinity)
            }
        }
    }
}
