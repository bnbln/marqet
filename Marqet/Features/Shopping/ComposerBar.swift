import MarqetCore
import SwiftUI

/// Serial entry above the keyboard (KONZEPT §7.3).
///
/// One text field for all stores: switching the target store via the chips never moves focus,
/// so the keyboard stays up while the pager follows to the target card. Return or the send
/// button adds the item and keeps the keyboard open (`ComposerTextField`). The bar stays open
/// for further entries until it is swiped down.
struct ComposerBar: View {
    @Binding var isFocused: Bool
    @Binding var showsAddStore: Bool

    @Environment(AppModel.self) private var model
    @AppStorage(AppAccentPalette.storageKey) private var accentPaletteKey = AppAccentPalette.leaf.rawValue
    @State private var dragOffset: CGFloat = 0

    private var accentColor: Color {
        AppAccentPalette(rawValue: accentPaletteKey)?.color ?? AppAccentPalette.leaf.color
    }

    private var canSend: Bool {
        !model.composerText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 10) {
            Capsule()
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.bottom, -2)
                .accessibilityHidden(true)
            chips
            HStack(spacing: 10) {
                ComposerTextField(
                    text: $model.composerText,
                    isFocused: $isFocused,
                    placeholder: placeholder,
                    onCommit: commit
                )
                Button("Senden", systemImage: "arrow.up.circle.fill", action: send)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        canSend ? Color.white : Color(.tertiaryLabel),
                        canSend ? accentColor : Color(.tertiarySystemFill)
                    )
                    .disabled(!canSend)
                    .animation(.snappy, value: canSend)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .clipShape(.rect(cornerRadius: 30, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .offset(y: dragOffset)
        .simultaneousGesture(dismissGesture)
        .accessibilityAction(.escape, close)
    }

    /// Swiping the bar down closes the composer; horizontal drags stay with the chip row.
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard value.translation.height > abs(value.translation.width) else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let isVertical = value.translation.height > abs(value.translation.width)
                if isVertical, value.translation.height > 60 || value.predictedEndTranslation.height > 160 {
                    close()
                }
                withAnimation(.snappy) { dragOffset = 0 }
            }
    }

    private func send() {
        guard canSend else { return }
        commit(model.composerText)
        model.composerText = ""
    }

    private func close() {
        isFocused = false
        model.endComposer()
    }

    private func commit(_ line: String) {
        guard let target = model.composerTarget else { return }
        Task { await model.addItem(title: line, to: target) }
    }

    private var placeholder: String {
        String(localized: "Neuer Eintrag")
    }

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(page: .unsorted, title: String(localized: "Unsortiert"), color: .gray, badge: nil)
                    ForEach(model.stores.sorted { $0.sortIndex < $1.sortIndex }) { store in
                        chip(page: .store(store.id), title: store.name, color: store.color, badge: store)
                    }
                    Button {
                        showsAddStore = true
                    } label: {
                        Label("Laden", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemFill), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -12)
            .onAppear {
                if let target = model.composerTarget { proxy.scrollTo(target) }
            }
            .onChange(of: model.composerTarget) { _, target in
                if let target { withAnimation(.smooth) { proxy.scrollTo(target) } }
            }
        }
    }

    private func chip(page: PageID, title: String, color: Color, badge: Store?) -> some View {
        let isSelected = model.composerTarget == page
        return Button {
            model.startComposer(on: page)
        } label: {
            HStack(spacing: 6) {
                if let badge {
                    StoreBadge(store: badge, size: 20)
                } else {
                    Image(systemName: "tray")
                        .font(.caption.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? (badge?.foregroundOnColor ?? .white) : .primary)
            .background(isSelected ? color : Color(.tertiarySystemFill), in: .capsule)
        }
        .buttonStyle(.plain)
        .id(page)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
