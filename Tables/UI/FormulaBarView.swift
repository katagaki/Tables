import SwiftUI

/// The address box plus formula field. It sits below the grid, within thumb
/// reach, and is sized for comfortable reading.
struct FormulaBarView: View {
    @Binding var workbook: Workbook
    @Bindable var state: EditorState

    @FocusState private var isFocused: Bool

    private var activeSheet: Worksheet { state.activeSheet(in: workbook) }
    private var selectedCell: Cell { activeSheet[state.selectedAddress] }

    /// Formulas get a monospaced face; ordinary values do not.
    private var isShowingFormula: Bool {
        state.editingAddress == nil ? selectedCell.formula != nil : state.editingText.hasPrefix("=")
    }

    private var displayedText: Binding<String> {
        Binding(
            get: { state.editingAddress == nil ? selectedCell.editableText : state.editingText },
            set: { newValue in
                if state.editingAddress == nil {
                    state.editingAddress = state.selectedAddress
                }
                state.editingText = newValue
            }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(state.selection.a1)
                .accessibilityIdentifier("addressBox")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 66, alignment: .leading)
                .lineLimit(1)

            Divider().frame(height: 24)

            Image(systemName: "function")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isShowingFormula ? Color.accentColor : .secondary)

            TextField("Enter a value or formula", text: displayedText)
                .accessibilityIdentifier("formulaField")
                .textFieldStyle(.plain)
                .font(isShowingFormula ? .system(size: 16, design: .monospaced) : .system(size: 16))
                .focused($isFocused)
                .onSubmit { state.commitEditing(in: &workbook, keepingEditor: true) }
                .onEscapeKey { state.cancelEditing() }
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif

            if state.editingAddress != nil {
                Button {
                    state.cancelEditing()
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Discard edit")

                Button {
                    state.commitEditing(in: &workbook, then: nil)
                    isFocused = false
                } label: {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Accept edit")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.bar)
        .onChange(of: isFocused) { _, focused in
            state.isFormulaBarActive = focused
            if focused, state.editingAddress == nil {
                state.editingAddress = state.selectedAddress
                state.editingText = selectedCell.editableText
            }
        }
        // Pointing at cells appends references; keep the caret at the end so the
        // next character the user types lands after them.
        .onChange(of: state.pendingReferenceRange) { _, _ in
            guard state.isEnteringFormula, state.isFormulaBarActive else { return }
            isFocused = true
        }
    }
}
