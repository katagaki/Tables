import SwiftUI

/// The bottom strip of worksheet tabs, Numbers-style.
struct SheetTabBarView: View {
    @Binding var workbook: Workbook
    @Bindable var state: EditorState

    @State private var renamingSheetID: Worksheet.ID?
    @State private var draftName = ""
    @FocusState private var isRenaming: Bool

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    state.addSheet(in: &workbook)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .help("Add a sheet")
                // `help` is a tooltip, and tooltips do not exist on iOS — without
                // this the control is an unlabelled glyph to VoiceOver.
                .accessibilityLabel("Add a sheet")

                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(workbook.visibleSheets) { sheet in
                            tab(for: sheet)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)

                if !hiddenSheets.isEmpty { hiddenSheetsMenu }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var hiddenSheets: [Worksheet] { workbook.sheets.filter(\.isHidden) }

    /// The only way back to a hidden sheet, so hiding one is never a one-way door.
    private var hiddenSheetsMenu: some View {
        Menu {
            ForEach(hiddenSheets) { sheet in
                Button(sheet.name) { state.setSheet(sheet.id, hidden: false, in: &workbook) }
            }
        } label: {
            Image(systemName: "eye.slash")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30, height: 30)
        .glassEffect(.regular.interactive(), in: .circle)
        .help("Show a hidden sheet")
        .accessibilityLabel("Show a hidden sheet")
        .accessibilityLabel("Hidden sheets (\(hiddenSheets.count))")
    }

    @ViewBuilder
    private func tab(for sheet: Worksheet) -> some View {
        let isActive = sheet.id == state.activeSheet(in: workbook).id

        Group {
            if renamingSheetID == sheet.id {
                TextField("Sheet name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($isRenaming)
                    .frame(minWidth: 80)
                    .onSubmit { commitRename(for: sheet) }
            } else {
                Text(sheet.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(isActive ? Color.accentColor : .primary)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .glassEffect(
            isActive ? .regular.tint(Color.accentColor.opacity(0.22)).interactive() : .regular.interactive(),
            in: .capsule
        )
        .contentShape(.capsule)
        .onTapGesture {
            if isActive {
                beginRename(sheet)
            } else {
                state.selectSheet(sheet.id, in: workbook)
            }
        }
        .contextMenu {
            Button("Rename…") { beginRename(sheet) }
            Button("Duplicate") {
                state.selectSheet(sheet.id, in: workbook)
                state.duplicateActiveSheet(in: &workbook)
            }
            Button("Hide") { state.setSheet(sheet.id, hidden: true, in: &workbook) }
                .disabled(workbook.visibleSheets.count <= 1)
            Divider()
            Button("Delete", role: .destructive) {
                state.deleteSheet(sheet.id, in: &workbook)
            }
            .disabled(workbook.sheets.count <= 1)
        }
    }

    private func beginRename(_ sheet: Worksheet) {
        draftName = sheet.name
        renamingSheetID = sheet.id
        isRenaming = true
    }

    private func commitRename(for sheet: Worksheet) {
        workbook.renameSheet(sheet.id, to: draftName)
        renamingSheetID = nil
        isRenaming = false
    }
}
