import AppKit
import SwiftUI

@MainActor
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var shouldFocus: Bool

    let placeholder: String
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CenteringView {
        let container = CenteringView()

        let field = NSTextField()
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 22, weight: .medium)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.textColor = .white
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail

        container.addSubview(field)
        container.textField = field
        return container
    }

    func updateNSView(_ nsView: CenteringView, context: Context) {
        guard let field = nsView.textField else { return }

        if field.stringValue != text {
            field.stringValue = text
        }

        field.backgroundColor = .clear
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.38),
                .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            ]
        )

        if shouldFocus {
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                (field.currentEditor() as? NSTextView)?.insertionPointColor = NSColor.white
                shouldFocus = false
            }
        }
    }

    final class CenteringView: NSView {
        var textField: NSTextField?

        override func layout() {
            super.layout()
            guard let textField else { return }
            let fieldHeight = textField.intrinsicContentSize.height
            textField.frame = NSRect(
                x: 0,
                y: (bounds.height - fieldHeight) / 2,
                width: bounds.width,
                height: fieldHeight
            )
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let parent: SearchField

        init(parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                guard !textView.hasMarkedText() else {
                    return false
                }

                parent.onCommit()
                return true
            }

            return false
        }
    }
}
