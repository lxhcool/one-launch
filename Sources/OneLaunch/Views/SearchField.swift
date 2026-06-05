import AppKit
import SwiftUI

@MainActor
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var shouldFocus: Bool

    let placeholder: String
    let onCommit: () -> Void
    var onMoveUp: (() -> Void)? = nil
    var onMoveDown: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 18, weight: .regular)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.textColor = .white
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // 输入法组合期间不覆盖 NSTextField 内容，让 IME 完全控制显示
        let isComposing = (nsView.currentEditor() as? NSTextView)?.hasMarkedText() ?? false

        if !isComposing && nsView.stringValue != text {
            nsView.stringValue = text
        }

        nsView.backgroundColor = .clear
        nsView.textColor = .white
        nsView.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.38),
                .font: NSFont.systemFont(ofSize: 18, weight: .regular),
            ]
        )

        if shouldFocus {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                (nsView.currentEditor() as? NSTextView)?.insertionPointColor = NSColor.white
                self.shouldFocus = false
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let parent: SearchField
        private weak var textField: NSTextField?
        private var textUpdateTask: Task<Void, Never>?

        init(parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let tf = notification.object as? NSTextField else { return }
            self.textField = tf

            textUpdateTask?.cancel()
            textUpdateTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000)
                guard let self, !Task.isCancelled, let tf = self.textField else { return }
                let editor = tf.currentEditor() as? NSTextView
                self.parent.text = editor?.string ?? tf.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                guard !textView.hasMarkedText() else {
                    return false
                }
                parent.onCommit()
                return true
            }

            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onMoveUp?()
                return true
            }

            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onMoveDown?()
                return true
            }

            return false
        }
    }


}
