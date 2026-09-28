import SwiftUI

/// The fixed grid every onboarding step uses: illustration stage, headline, text – each in a
/// slot of constant height, the block centered on screen. The top offset depends only on the
/// screen height, never on the content, so image, headline and the first line of text sit at the
/// same height on every step, however long the headline or text is.
struct OnboardingLayout<Illustration: View, Content: View, Action: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var illustration: Illustration
    @ViewBuilder var content: Content
    @ViewBuilder var action: Action

    var body: some View {
        GeometryReader { proxy in
            if let fold = FoldGeometry.verticalFold(in: proxy) {
                book(fold: fold.frame, size: proxy.size)
            } else {
                single(height: proxy.size.height)
            }
        }
    }

    /// One column: the anchored block, the action below in a bar.
    private func single(height: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                illustration
                    .frame(width: OnboardingMetrics.stageWidth, height: OnboardingMetrics.stageHeight)
                    .accessibilityHidden(true)
                headline
                    .multilineTextAlignment(.center)
                    .padding(.top, OnboardingMetrics.titleSpacing)
                text(alignment: .center)
                    .padding(.top, OnboardingMetrics.textSpacing)
            }
            .frame(maxWidth: OnboardingMetrics.maxWidth)
            .padding(.horizontal, 24)
            .padding(.top, OnboardingMetrics.topInset(for: height))
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            action
                .frame(maxWidth: OnboardingMetrics.maxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
    }

    /// iPhone Duo, open like a book: the picture on the left page, words and action on the
    /// right – nothing runs across the crease. The headline sits at the same height on every step.
    private func book(fold: CGRect, size: CGSize) -> some View {
        HStack(spacing: 0) {
            illustration
                .frame(width: OnboardingMetrics.stageWidth, height: OnboardingMetrics.stageHeight)
                .accessibilityHidden(true)
                .frame(width: fold.minX, height: size.height)
            Color.clear.frame(width: fold.width)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headline
                    text(alignment: .leading)
                        .padding(.top, OnboardingMetrics.textSpacing)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaBar(edge: .bottom) {
                action
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
            }
            .frame(width: max(size.width - fold.maxX, 0))
        }
    }

    private var headline: some View {
        Text(title)
            .font(.title.bold())
            // Always two lines: a one-line headline must not pull the text up.
            .lineLimit(2, reservesSpace: true)
            .minimumScaleFactor(0.8)
            .accessibilityAddTraits(.isHeader)
    }

    private func text(alignment: TextAlignment) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(alignment)
                    .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
            }
            content
        }
    }
}

enum OnboardingMetrics {
    static let stageWidth: CGFloat = 300
    static let stageHeight: CGFloat = 184
    static let titleSpacing: CGFloat = 28
    static let textSpacing: CGFloat = 14
    static let maxWidth: CGFloat = 480

    /// Height of image + two-line headline + the first lines of text, the block that is centered.
    private static let anchorBlockHeight: CGFloat = 440

    /// Same value on every step of one screen: it only depends on the available height.
    static func topInset(for height: CGFloat) -> CGFloat {
        max(12, (height - anchorBlockHeight) * 0.3)
    }
}

/// Symbol + text rows below the headline.
struct OnboardingPoints: View {
    let points: [(symbol: String, text: LocalizedStringKey)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(points.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Image(systemName: points[index].symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 26)
                    Text(points[index].text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Identical full-width primary action for every onboarding step.
struct OnboardingPrimaryButton: View {
    let title: LocalizedStringKey
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!isEnabled)
        .frame(maxWidth: .infinity)
    }
}
