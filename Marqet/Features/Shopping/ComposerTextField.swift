import SwiftUI
import UIKit

/// Single-line text field that keeps the keyboard up on Return (KONZEPT §7.3, serial entry).
///
/// SwiftUI's `TextField` ends editing on Return, which closes the keyboard after every item.
/// Here Return commits the line and the field stays first responder. Pasted text with line
/// breaks is split: every complete line is committed, the rest stays in the field.
struct ComposerTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    var onCommit: (String) -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.returnKeyType = .next
        field.autocapitalizationType = .sentences
        field.clearButtonMode = .whileEditing
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.placeholder = placeholder
        if isFocused, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isFocused, field.isFirstResponder {
            DispatchQueue.main.async { field.resignFirstResponder() }
        }
    }

    /// Full proposed width, natural single-line height (a UITextField would otherwise take all height).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView field: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? field.intrinsicContentSize.width, height: field.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ComposerTextField

        init(parent: ComposerTextField) { self.parent = parent }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            let line = field.text ?? ""
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                parent.onCommit(line)
                field.text = ""
                parent.text = ""
            }
            return false
        }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            guard string.contains(where: \.isNewline), let current = field.text, let swiftRange = Range(range, in: current) else {
                return true
            }
            var lines = current.replacingCharacters(in: swiftRange, with: string).components(separatedBy: .newlines)
            let rest = lines.removeLast()
            for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                parent.onCommit(line)
            }
            field.text = rest
            parent.text = rest
            return false
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            if parent.isFocused { parent.isFocused = false }
        }
    }
}
