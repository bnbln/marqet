import MarqetCore
import SwiftUI

/// Dictation: speak what you need and where, watch the lists build up, then confirm (KONZEPT §3).
///
/// Top: the live transcript, recognized stores in their color. Middle: one card per store in
/// the order they were mentioned, rows flying in as they are heard (and across cards when a
/// store is corrected). Bottom: the microphone. After "Fertig" the same screen asks
/// "Hinzufügen?" – rows can be deselected, moved or removed before adding.
struct VoiceCaptureScreen: View {
    let request: VoiceRequest

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openURL) private var openURL
    @AppStorage(AppAccentPalette.storageKey) private var accentPaletteKey = AppAccentPalette.leaf.rawValue
    @State private var session: VoiceSession?
    @State private var confirmsDiscard = false
    @State private var commitFeedback = 0
    @State private var isCommitting = false

    private var accentColor: Color {
        AppAccentPalette(rawValue: accentPaletteKey)?.color ?? AppAccentPalette.leaf.color
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    VoiceCaptureContent(session: session, accentColor: accentColor, isWide: sizeClass == .regular)
                } else {
                    Color.clear
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let session {
                    VoiceControls(
                        session: session,
                        accentColor: accentColor,
                        isCommitting: isCommitting,
                        onCommit: commit,
                        onOpenSettings: openSettings
                    )
                }
            }
            .navigationTitle(session.map(title(for:)) ?? "")
            .navigationSubtitle(session.map(subtitle(for:)) ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .tint(.primary)
        .sensoryFeedback(.success, trigger: commitFeedback)
        .sensoryFeedback(.impact(weight: .light), trigger: session?.groups.count ?? 0)
        .interactiveDismissDisabled()
        .task {
            let session = VoiceSession(model: model, request: request)
            self.session = session
            await session.start()
        }
        .confirmationDialog("Diktat verwerfen?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) { close() }
            Button("Weiter bearbeiten", role: .cancel) {}
        } message: {
            Text("Die erkannten Einträge werden nicht hinzugefügt.")
        }
    }

    private func title(for session: VoiceSession) -> String {
        switch session.phase {
        case .preparing, .listening, .failed: String(localized: "Einsprechen")
        case .finishing: String(localized: "Wird sortiert …")
        case .review: String(localized: "Hinzufügen?")
        }
    }

    /// Review: what "Hinzufügen" will do, right under the question.
    private func subtitle(for session: VoiceSession) -> String {
        guard session.phase == .review, !session.groups.isEmpty else { return "" }
        let items = session.selectedCount
        guard items > 0 else { return String(localized: "Nichts ausgewählt") }
        let stores = session.targetCount
        let itemText = items == 1 ? String(localized: "1 Eintrag") : String(localized: "\(items) Einträge")
        let storeText = stores == 1 ? String(localized: "1 Liste") : String(localized: "\(stores) Listen")
        return String(localized: "\(itemText) für \(storeText)")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Abbrechen", systemImage: "xmark", role: .close) {
                if (session?.draft.entries.isEmpty ?? true) { close() } else { confirmsDiscard = true }
            }
        }
        if let session, session.usesIntelligence {
            ToolbarItem(placement: .topBarTrailing) {
                IntelligenceBadge(isActive: session.isInterpreting || session.phase == .finishing)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private func close() {
        Task {
            await session?.cancel()
            model.voiceRequest = nil
        }
    }

    private func commit() {
        guard let session, !isCommitting else { return }
        isCommitting = true
        Task {
            _ = await session.commit()
            commitFeedback += 1
            model.voiceRequest = nil
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

// MARK: - Content

private struct VoiceCaptureContent: View {
    let session: VoiceSession
    let accentColor: Color
    let isWide: Bool

    @Namespace private var rows
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeColor: Color {
        session.activeChoice.flatMap { session.option(for: $0) }?.store.color ?? accentColor
    }

    var body: some View {
        Group {
            if isWide {
                // iPad and the open Duo: what was said on the left, the lists on the right.
                AdaptiveSplit {
                    VStack(alignment: .leading, spacing: 20) {
                        TranscriptView(session: session, isExpanded: true)
                        Spacer(minLength: 0)
                    }
                    .padding(28)
                } secondary: {
                    lists
                }
            } else {
                VStack(spacing: 0) {
                    TranscriptView(session: session, isExpanded: session.phase != .review)
                        .padding(.horizontal, 20)
                    .padding(.top, 4)
                    lists
                }
            }
        }
        .background(alignment: .bottom) {
            AmbientGlow(color: activeColor, level: session.phase == .listening ? session.level : 0)
                .animation(.easeInOut(duration: 0.6), value: session.activeChoice)
        }
    }

    private var lists: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    if session.groups.isEmpty {
                        EmptyDictationHint(session: session)
                            .transition(.opacity)
                    }
                    ForEach(session.groups) { group in
                        VoiceListCard(
                            session: session,
                            group: group,
                            isActive: session.phase == .listening && session.activeChoice == group.choice,
                            rowNamespace: rows
                        )
                        .id(group.id)
                        .transition(cardTransition)
                    }
                    if session.phase == .review, !session.groups.isEmpty {
                        Text("Tippen zum Abwählen, gedrückt halten zum Verschieben.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.28), value: session.groups)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: session.activeChoice) { _, choice in
                guard let choice else { return }
                withAnimation(.smooth) { proxy.scrollTo(choice, anchor: .center) }
            }
            .onChange(of: session.draft.entries.last?.id) { _, _ in
                guard session.phase == .listening,
                      let last = session.groups.first(where: { $0.rows.contains { $0.id == session.draft.entries.last?.id } })
                else { return }
                withAnimation(.smooth) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var cardTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .scale(scale: 0.9, anchor: .top).combined(with: .opacity).combined(with: .offset(y: 24)),
                removal: .scale(scale: 0.95).combined(with: .opacity)
            )
    }
}

// MARK: - Transcript

/// The words so far. Stores light up in their color, recognized items in full strength,
/// the rest stays secondary; the still changing tail is lighter.
private struct TranscriptView: View {
    let session: VoiceSession
    let isExpanded: Bool

    var body: some View {
        let text = session.transcript.full
        Group {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
            } else {
                Text(highlighted)
                    .contentTransition(.interpolate)
            }
        }
        .font(isExpanded ? .title3.weight(.medium) : .footnote)
        .lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Listening: the newest words matter, older ones scroll out at the top.
        // Review: a short quote of the beginning.
        .lineLimit(isExpanded ? 6 : 2)
        .truncationMode(isExpanded ? .head : .tail)
        .animation(.smooth(duration: 0.25), value: text)
        .animation(.snappy, value: isExpanded)
        .accessibilityLabel(text.isEmpty ? placeholder : text)
    }

    private var placeholder: String {
        switch session.phase {
        case .preparing(let progress?): String(localized: "Sprachmodell wird geladen … \(Int(progress * 100)) %")
        case .preparing: String(localized: "Einen Moment …")
        default: String(localized: "Sag, was du brauchst – und wo du es kaufst.")
        }
    }

    private var highlighted: AttributedString {
        let full = session.transcript.full
        let finalizedCount = session.transcript.finalized.count
        var result = AttributedString(String(full.prefix(finalizedCount)))
        result.foregroundColor = .secondary
        var tail = AttributedString(String(full.dropFirst(finalizedCount)))
        tail.foregroundColor = Color(.tertiaryLabel)
        result.append(tail)

        let plain = String(result.characters)
        for entry in session.draft.entries {
            for word in entry.spoken.name.split(whereSeparator: { !$0.isLetter }) where word.count >= 3 {
                mark(String(word), in: &result, plain: plain) { $0.foregroundColor = .primary }
            }
            if let quantity = entry.spoken.quantity {
                mark(quantity, in: &result, plain: plain) { $0.foregroundColor = .primary }
            }
        }
        for option in session.options {
            for spelling in [option.name] + option.spellings {
                mark(spelling, in: &result, plain: plain) {
                    $0.foregroundColor = option.store.readableColor
                    $0.inlinePresentationIntent = .stronglyEmphasized
                }
            }
        }
        return result
    }

    /// Whole-word, case and diacritic insensitive.
    private func mark(_ needle: String, in text: inout AttributedString, plain: String, style: (inout AttributeContainer) -> Void) {
        var container = AttributeContainer()
        style(&container)
        var searchStart = plain.startIndex
        while let range = plain.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<plain.endIndex) {
            searchStart = range.upperBound
            let before = range.lowerBound == plain.startIndex ? nil : plain[plain.index(before: range.lowerBound)]
            let after = range.upperBound == plain.endIndex ? nil : plain[range.upperBound]
            guard before?.isLetter != true, after?.isLetter != true else { continue }
            let lower = plain.distance(from: plain.startIndex, to: range.lowerBound)
            let length = plain.distance(from: range.lowerBound, to: range.upperBound)
            let start = text.characters.index(text.startIndex, offsetBy: lower)
            let end = text.characters.index(start, offsetBy: length)
            text[start..<end].mergeAttributes(container)
        }
    }
}

// MARK: - List card

/// A store's list as it builds up: brand header like the pager cards, rows below.
private struct VoiceListCard: View {
    let session: VoiceSession
    let group: VoiceSession.Group
    let isActive: Bool
    let rowNamespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: Store? { group.option?.store }
    private var tint: Color { store?.color ?? Color(.systemGray) }
    private var readableTint: Color { store?.readableColor ?? .secondary }
    private var isReview: Bool { session.phase == .review }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 0) {
                ForEach(group.rows) { row in
                    VoiceRow(session: session, row: row, tint: readableTint, isReview: isReview)
                        .matchedGeometryEffect(id: row.id, in: rowNamespace)
                        .transition(rowTransition)
                    if row.id != group.rows.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 26, style: .continuous))
        .shadow(color: isActive ? tint.opacity(0.45) : .black.opacity(0.06), radius: isActive ? 22 : 10, y: isActive ? 8 : 3)
        .scaleEffect(isActive && !reduceMotion ? 1.015 : 1)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: isActive)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(store?.name ?? String(localized: "Inbox"))
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let store {
                StoreBadge(store: store, size: 30)
            } else {
                Image(systemName: "tray.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.22), in: .circle)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(store?.name ?? String(localized: "Inbox"))
                    .font(.headline)
                if group.option?.isNew == true {
                    Text("Neuer Laden – wird angelegt")
                        .font(.caption)
                        .opacity(0.85)
                } else if store == nil {
                    Text("Ohne Laden – später zuordnen")
                        .font(.caption)
                        .opacity(0.85)
                }
            }
            Spacer(minLength: 8)
            Text(group.rows.filter(\.entry.isSelected).count, format: .number)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.white.opacity(0.22), in: .capsule)
                .accessibilityLabel("\(group.rows.count) Einträge")
        }
        .foregroundStyle(store?.foregroundOnColor ?? .white)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [tint, tint.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var rowTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .push(from: .bottom).combined(with: .scale(scale: 0.85, anchor: .leading)),
                removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .leading))
            )
    }
}

private struct VoiceRow: View {
    let session: VoiceSession
    let row: VoiceSession.Row
    let tint: Color
    let isReview: Bool

    private var entry: VoiceDraft.Entry { row.entry }
    /// Heard by the rules, the language model has not confirmed it yet.
    private var isTentative: Bool { session.usesIntelligence && entry.origin == .rules && !isReview }

    var body: some View {
        Button {
            // While listening the rows only show what was heard; choosing starts in review.
            guard isReview else { return }
            withAnimation(.snappy) { session.toggle(row) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(entry.isSelected ? tint : Color(.tertiaryLabel))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28)
                Text(entry.spoken.name)
                    .font(.body)
                    .foregroundStyle(entry.isSelected ? .primary : .secondary)
                    .strikethrough(!entry.isSelected, color: .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let quantity = entry.spoken.quantity {
                    Text(quantity)
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                }
                reasonMark
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(.rect)
            .opacity(isTentative ? 0.55 : 1)
            .animation(.smooth, value: isTentative)
        }
        .buttonStyle(.plain)
        .contextMenu { menu }
        .accessibilityLabel(entry.spoken.title)
        .accessibilityValue(entry.isSelected ? String(localized: "ausgewählt") : String(localized: "nicht ausgewählt"))
        .accessibilityAddTraits(entry.isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var reasonMark: some View {
        switch row.placement.reason {
        case .memory:
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Wie beim letzten Mal")
        case .context:
            Image(systemName: "scope")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Aktuelle Liste")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var menu: some View {
        Menu("Laden ändern", systemImage: "arrow.right.arrow.left") {
            ForEach(session.options.filter { !$0.isNew }) { option in
                Button(option.name) { withAnimation(.spring(duration: 0.5, bounce: 0.2)) { session.move(row, to: option.choice) } }
            }
            Button("Inbox", systemImage: "tray") { withAnimation(.spring(duration: 0.5, bounce: 0.2)) { session.move(row, to: .inbox) } }
        }
        Button("Entfernen", systemImage: "trash", role: .destructive) {
            withAnimation(.snappy) { session.remove(row) }
        }
    }
}

// MARK: - Empty state

private struct EmptyDictationHint: View {
    let session: VoiceSession

    var body: some View {
        VStack(spacing: 18) {
            if session.phase == .review {
                Image(systemName: "text.badge.xmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Keine Einträge erkannt")
                    .font(.headline)
                Text("Tippe auf „Weitersprechen“ und versuch es noch einmal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("„10 Eier vom Markt und bei Rewe 500 g Hackfleisch“")
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                let known = session.options.filter { !$0.isNew }.prefix(5)
                if !known.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(Array(known)) { option in
                            StoreBadge(store: option.store, size: 30)
                                .overlay(Circle().strokeBorder(Color(.systemGroupedBackground), lineWidth: 2))
                        }
                    }
                    .accessibilityHidden(true)
                    Text("Nenn einen Laden, und seine Liste erscheint.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
    }
}

// MARK: - Controls

private struct VoiceControls: View {
    let session: VoiceSession
    let accentColor: Color
    let isCommitting: Bool
    let onCommit: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Group {
            switch session.phase {
            case .preparing(let progress):
                VStack(spacing: 10) {
                    if let progress {
                        ProgressView(value: progress).frame(width: 180)
                    } else {
                        ProgressView()
                    }
                    Text(progress == nil ? "Mikrofon wird vorbereitet" : "Sprachmodell wird geladen")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 112)
            case .listening:
                VStack(spacing: 10) {
                    MicrophoneButton(level: session.level, accentColor: accentColor) {
                        Task { await session.stop() }
                    }
                    Text("Tippen, wenn du fertig bist")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .finishing:
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.large)
                        .frame(width: 76, height: 76)
                    Text(session.usesIntelligence ? "Apple Intelligence sortiert …" : "Wird sortiert …")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .review:
                reviewBar
            case .failed(let message, let canOpenSettings):
                VStack(spacing: 12) {
                    Label(message, systemImage: "mic.slash")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if canOpenSettings {
                        Button("Einstellungen öffnen", action: onOpenSettings)
                            .buttonStyle(.glass)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .animation(.snappy, value: session.phase)
    }

    private var reviewBar: some View {
        VStack(spacing: 6) {
            Button {
                Task { await session.resume() }
            } label: {
                Label("Weitersprechen", systemImage: "mic.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            Button(action: onCommit) {
                HStack(spacing: 8) {
                    if isCommitting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "plus")
                    }
                    Text(commitTitle)
                        .contentTransition(.numericText())
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .glassEffect(.regular.tint(accentColor).interactive(), in: .capsule)
            .disabled(session.selectedCount == 0 || isCommitting)
            .opacity(session.selectedCount == 0 ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var commitTitle: String {
        let count = session.selectedCount
        return count == 1 ? String(localized: "1 Eintrag hinzufügen") : String(localized: "\(count) Einträge hinzufügen")
    }
}

/// Stop button with a halo that breathes with the voice.
private struct MicrophoneButton: View {
    let level: Float
    let accentColor: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // The halo lives outside the button: its constant resizing must not cancel a tap.
            if !reduceMotion {
                ForEach(0..<3) { ring in
                    Circle()
                        .fill(accentColor.opacity(0.16 - Double(ring) * 0.04))
                        .frame(width: 76, height: 76)
                        .scaleEffect(1 + CGFloat(level) * (0.35 + CGFloat(ring) * 0.3))
                }
                .animation(.smooth(duration: 0.12), value: level)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            Button(action: action) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white)
                    .frame(width: 24, height: 24)
                    .frame(width: 76, height: 76)
                    .background(accentColor, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(accentColor).interactive(), in: .circle)
            .accessibilityLabel("Aufnahme beenden")
        }
        .frame(width: 120, height: 120)
    }
}

/// Soft light rising from the bottom in the color of the store just mentioned.
private struct AmbientGlow: View {
    let color: Color
    let level: Float
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Ellipse()
            .fill(color)
            .frame(height: 260)
            .scaleEffect(x: 1.3, y: 0.8 + CGFloat(level) * 0.4)
            .offset(y: 170)
            .blur(radius: 80)
            .opacity((colorScheme == .dark ? 0.35 : 0.2) + Double(level) * 0.25)
            .animation(.smooth(duration: 0.2), value: level)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// "Apple Intelligence" in the bar, shimmering while the model reads.
private struct IntelligenceBadge: View {
    let isActive: Bool

    var body: some View {
        Label("Apple Intelligence", systemImage: "sparkles")
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(
                LinearGradient(colors: [.orange, .pink, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .symbolEffect(.pulse, isActive: isActive)
            .frame(width: 36, height: 36)
            .accessibilityLabel(isActive ? "Apple Intelligence liest mit" : "Apple Intelligence")
    }
}

// MARK: - Presentation

extension View {
    /// Presents the dictation screen for `AppModel.voiceRequest`. Home presents it while no
    /// store is open full screen, `StoreFocusScreen` while one is.
    func voiceCaptureCover(isPresenter: Bool) -> some View {
        modifier(VoiceCaptureCover(isPresenter: isPresenter))
    }
}

private struct VoiceCaptureCover: ViewModifier {
    let isPresenter: Bool
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.fullScreenCover(item: Binding(
            get: { isPresenter ? model.voiceRequest : nil },
            set: { if $0 == nil { model.voiceRequest = nil } }
        )) { request in
            VoiceCaptureScreen(request: request)
        }
    }
}

#Preview {
    let model = AppModel.demo(isPro: true)
    VoiceCaptureScreen(request: VoiceRequest())
        .environment(model)
}
