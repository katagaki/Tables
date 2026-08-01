import SwiftUI

/// Builds the action list for a cell, in the same shape the header menus use so
/// the long-press and double-tap paths can share one description of the menu.
@MainActor
struct CellMenuBuilder {
    /// The cell the menu was opened from, so it can act on that cell even when
    /// the selection is somewhere else.
    let address: CellAddress
    let workbook: Binding<Workbook>
    let state: EditorState

    private var activeSheet: Worksheet { state.activeSheet(in: workbook.wrappedValue) }

    /// Whether there is anything to paste — the app's own clipboard if the copy
    /// happened here, otherwise text sitting on the system pasteboard.
    private var canPaste: Bool {
        if let clipboard = state.clipboard, !clipboard.isEmpty { return true }
        #if canImport(UIKit)
        return UIPasteboard.general.hasStrings
        #else
        return NSPasteboard.general.canReadObject(forClasses: [NSString.self])
        #endif
    }

    func actions() -> [HeaderMenuAction] {
        [
            // The way into the in-cell editor by touch, now that the double tap
            // raises this menu instead of opening it.
            HeaderMenuAction(title: String(localized: "CellMenu.Edit"), symbol: "pencil") {
                target()
                state.beginEditing(address, in: workbook.wrappedValue)
            },
            .separator,
            HeaderMenuAction(title: String(localized: "CellMenu.Copy"), symbol: "doc.on.doc") {
                target()
                state.copySelection(in: workbook.wrappedValue)
            },
            HeaderMenuAction(title: String(localized: "CellMenu.Cut"), symbol: "scissors") {
                target()
                state.cutSelection(in: &workbook.wrappedValue)
            },
            HeaderMenuAction(
                title: String(localized: "CellMenu.Paste"), symbol: "doc.on.clipboard",
                isEnabled: canPaste
            ) {
                target()
                state.paste(in: &workbook.wrappedValue)
            },
            .separator,
            HeaderMenuAction(
                title: String(localized: "CellMenu.ResetFormatting"), symbol: "paintbrush"
            ) {
                target()
                state.clearFormatting(in: &workbook.wrappedValue)
            },
        ]
    }

    /// Points the selection at the cell this menu belongs to, unless it is
    /// already part of a larger selection the user made.
    private func target() {
        guard !state.selection.normalized.contains(address) else { return }
        state.select(address, in: activeSheet)
    }
}
