import SwiftUI

/// A plain-text editor for macro code: monospaced, coloured as VBA, and with
/// every typing aid that would corrupt code switched off — curly quotes
/// above all, which VBA does not accept as string delimiters.
struct CodeEditor {
    @Binding var text: String

    fileprivate static let fontSize: CGFloat = 14

    fileprivate static func color(for kind: VBASyntaxHighlighter.Kind) -> PlatformColor {
        switch kind {
        case .keyword: return .systemBlue
        case .comment: return .systemGreen
        case .string: return .systemRed
        case .number: return .systemPurple
        }
    }

    fileprivate static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: PlatformFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), .foregroundColor: PlatformColor.label]
    }

    /// Recolours the whole text. Modules are small enough that this keeps
    /// up with typing, and it is never wrong about a span the edit changed.
    fileprivate static func highlight(_ storage: NSTextStorage) {
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: whole)
        for span in VBASyntaxHighlighter.spans(in: storage.string) where NSMaxRange(span.range) <= storage.length {
            storage.addAttribute(.foregroundColor, value: color(for: span.kind), range: span.range)
        }
        storage.endEditing()
    }
}

#if os(iOS)
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont

extension CodeEditor: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.inlinePredictionType = .no
        view.keyboardType = .asciiCapable
        view.alwaysBounceVertical = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        view.typingAttributes = Self.baseAttributes
        view.accessibilityIdentifier = "codeEditor"
        view.text = text
        Self.highlight(view.textStorage)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        guard view.text != text else { return }
        let selection = view.selectedRange
        view.text = text
        Self.highlight(view.textStorage)
        view.selectedRange = NSRange(location: min(selection.location, view.textStorage.length), length: 0)
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ view: UITextView) {
            let selection = view.selectedRange
            CodeEditor.highlight(view.textStorage)
            view.selectedRange = selection
            view.typingAttributes = CodeEditor.baseAttributes
            text.wrappedValue = view.text
        }

        /// New lines keep the indentation of the line they break, as every
        /// code editor does.
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard replacement == "\n" else { return true }
            let source = view.text as NSString
            let lineStart = source.lineRange(for: NSRange(location: range.location, length: 0)).location
            let line = source.substring(with: NSRange(location: lineStart, length: range.location - lineStart))
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            guard !indent.isEmpty else { return true }
            view.textStorage.replaceCharacters(in: range, with: NSAttributedString(string: "\n" + indent,
                                                                                   attributes: CodeEditor.baseAttributes))
            view.selectedRange = NSRange(location: range.location + 1 + indent.utf16.count, length: 0)
            textViewDidChange(view)
            return false
        }
    }
}
#else
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont

private extension NSColor {
    static var label: NSColor { .labelColor }
}

extension CodeEditor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let view = scrollView.documentView as? NSTextView else { return scrollView }
        view.delegate = context.coordinator
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 8, height: 12)
        view.typingAttributes = Self.baseAttributes
        view.setAccessibilityIdentifier("codeEditor")
        view.string = text
        if let storage = view.textStorage { Self.highlight(storage) }
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let view = scrollView.documentView as? NSTextView, view.string != text else { return }
        view.string = text
        if let storage = view.textStorage { Self.highlight(storage) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            let selection = view.selectedRanges
            if let storage = view.textStorage { CodeEditor.highlight(storage) }
            view.selectedRanges = selection
            view.typingAttributes = CodeEditor.baseAttributes
            text.wrappedValue = view.string
        }
    }
}
#endif
