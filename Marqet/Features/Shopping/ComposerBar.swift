import MarqetCore
import SwiftUI

/// Serial entry above the keyboard (KONZEPT §7.3).
///
/// One text field for all stores: switching the target store via the chips never moves focus,
/// so the keyboard stays up while the pager follows to the target card. Return adds the item
/// and keeps the keyboard open (`ComposerTextField`).
struct ComposerBar: View {
    @Binding var isFocused: Bool
    @Binding var showsAddStore: Bool

    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 10) {
            chips
            HStack(spacing: 10) {
                ComposerTextField(
                    text: $model.composerText,
                    isFocused: $isFocused,
                    placeholder: placeholder,
                    onCommit: commit
                )
                Button("Fertig") { isFocused = false }
                    .font(.body.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22, style: .continuous))
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func commit(_ line: String) {
        guard let target = model.composerTarget else { return }
        Task { await model.addItem(title: line, to: target) }
    }

    private var placeholder: String {
        switch model.composerTarget {
        case .store(let id): String(localized: "Neuer Eintrag für \(model.store(id)?.name ?? "")")
        default: String(localized: "Neuer Eintrag (unsortiert)")
        }
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
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let target = model.composerTarget { proxy.scrollTo(target, anchor: .center) }
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
