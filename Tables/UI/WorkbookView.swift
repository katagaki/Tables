import SwiftUI

/// The document's root view: the grid, the formula bar beneath it, sheet tabs,
/// and whichever platform chrome belongs on top.
struct WorkbookView: View {
    @Binding var document: TablesDocument
    @State private var state = EditorState()
    @Namespace private var panelTransition

    private var workbook: Binding<Workbook> { $document.workbook }

    var body: some View {
        VStack(spacing: 0) {
            SheetGridView(workbook: workbook, state: state)
                // Keyboard navigation belongs to the grid, and only while no
                // text field is up — otherwise it holds focus away from them.
                .focusable(state.editingAddress == nil && !state.isFormulaBarActive)
                .focusEffectDisabled()
                .onKeyPress(action: handleKeyPress)
                .overlay(alignment: .bottom) {
                    #if os(iOS)
                    FloatingActionBar(workbook: workbook, state: state, namespace: panelTransition)
                        .padding(.bottom, 8)
                    #endif
                }

            Divider()
            FormulaBarView(workbook: workbook, state: state)
            Divider()
            SheetTabBarView(workbook: workbook, state: state)
                .background(.bar)
        }
        .background(Color.sheetBackground)
        .onAppear {
            if state.activeSheetID == nil {
                state.activeSheetID = document.workbook.sheets.first?.id
                state.refreshMetrics(in: document.workbook)
                // Saying this on open, once, is what gives the user a chance to
                // decide before they have changed anything.
                state.isShowingUnsupportedFeatureNotice = !document.unsupportedFeatures.isEmpty
            }
        }
        .onChange(of: state.activeSheetID) { _, _ in
            // CSV holds one sheet; export whichever one the user is looking at.
            document.csvExportSheetIndex = state.activeIndex(in: document.workbook)
        }
        .toolbar { sharingToolbar }
        #if os(macOS)
        .toolbar { macToolbar }
        .popover(item: $state.presentedPanel) { panel in
            panelContent(panel)
                .frame(width: 360, height: 480)
        }
        #else
        .sheet(item: $state.presentedPanel) { panel in
            NavigationStack {
                panelContent(panel)
                    .navigationTitle(panel.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarBackButtonHidden()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            // `.confirm` is the SDK's label-less Done button.
                            Button(role: .confirm) { state.presentedPanel = nil }
                        }
                    }
            }
            .navigationTransition(.zoom(sourceID: panel, in: panelTransition))
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
        }
        #endif
        .alert(
            "Alert.Error.Title",
            isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } }
            )
        ) {
            Button("Common.OK", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
        .alert(
            "Alert.UnsupportedFeatures.Title",
            isPresented: $state.isShowingUnsupportedFeatureNotice
        ) {
            Button("Common.Continue", role: .cancel) { state.isShowingUnsupportedFeatureNotice = false }
        } message: {
            Text(document.unsupportedFeatures.noticeMessage)
        }
    }

    // MARK: - Panels

    @ViewBuilder
    private func panelContent(_ panel: EditorPanel) -> some View {
        switch panel {
        case .format: FormatPanel(workbook: workbook, state: state)
        case .numberFormat: NumberFormatPanel(workbook: workbook, state: state)
        case .rowsAndColumns: RowsColumnsPanel(workbook: workbook, state: state)
        case .functions: FunctionsPanel(workbook: workbook, state: state)
        }
    }

    // MARK: - Toolbars

    private var export: WorkbookExport {
        WorkbookExport(
            workbook: document.workbook,
            name: state.activeSheet(in: document.workbook).name,
            sheetIndex: state.activeIndex(in: document.workbook)
        )
    }

    @ToolbarContentBuilder
    private var sharingToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ShareLink(item: export, preview: SharePreview(export.name, image: Image(systemName: "tablecells")))
                .accessibilityLabel("Toolbar.Share.Label")
        }
    }

    #if os(macOS)
    /// macOS gets one horizontal toolbar holding everything.
    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
        ToolbarItemGroup {
            toolbarToggle("bold", label: String(localized: "Toolbar.Bold"), isOn: currentStyle.isBold) {
                state.toggleBold(in: &document.workbook)
            }
            toolbarToggle("italic", label: String(localized: "Toolbar.Italic"), isOn: currentStyle.isItalic) {
                state.toggleItalic(in: &document.workbook)
            }
            toolbarToggle(
                "underline", label: String(localized: "Toolbar.Underline"),
                isOn: currentStyle.isUnderlined
            ) {
                state.toggleUnderline(in: &document.workbook)
            }
        }

        ToolbarItemGroup {
            ForEach(HorizontalTextAlignment.allCases.filter { $0 != .automatic }, id: \.self) { option in
                toolbarToggle(
                    option.symbolName, label: option.label,
                    isOn: currentStyle.horizontalAlignment == option
                ) {
                    state.applyStyle(in: &document.workbook) { $0.horizontalAlignment = option }
                }
            }
        }

        ToolbarItemGroup {
            toolbarToggle(
                "number", label: String(localized: "Toolbar.NumberFormat"),
                isOn: state.presentedPanel == .numberFormat
            ) {
                state.presentedPanel = .numberFormat
            }
            toolbarToggle(
                "paintpalette", label: String(localized: "Toolbar.CellFormat"),
                isOn: state.presentedPanel == .format
            ) {
                state.presentedPanel = .format
            }
            toolbarToggle("sum", label: String(localized: "Toolbar.Sum"), isOn: false) {
                state.insertAggregate("SUM", in: &document.workbook)
            }
            toolbarToggle(
                "function", label: String(localized: "Toolbar.InsertFunction"),
                isOn: state.presentedPanel == .functions
            ) {
                state.presentedPanel = .functions
            }
            toolbarToggle("tablecells", label: String(localized: "Toolbar.RowsAndColumns"),
                          isOn: state.presentedPanel == .rowsAndColumns) {
                state.presentedPanel = .rowsAndColumns
            }
        }
    }

    private var currentStyle: CellStyle { state.representativeStyle(in: document.workbook) }

    /// Active toolbar controls take a round highlight, matching the floating bar.
    private func toolbarToggle(
        _ symbol: String, label: String, isOn: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 26)
                .background(isOn ? Color.accentColor.opacity(0.22) : .clear, in: .circle)
                .foregroundStyle(isOn ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
    #endif

    // MARK: - Keyboard

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        let sheet = state.activeSheet(in: document.workbook)
        let isEditing = state.editingAddress != nil
        let extending = press.modifiers.contains(.shift)

        switch press.key {
        case .upArrow where !isEditing:
            state.move(.up, extending: extending, in: sheet)
            return .handled
        case .downArrow where !isEditing:
            state.move(.down, extending: extending, in: sheet)
            return .handled
        case .leftArrow where !isEditing:
            state.move(.left, extending: extending, in: sheet)
            return .handled
        case .rightArrow where !isEditing:
            state.move(.right, extending: extending, in: sheet)
            return .handled
        case .tab where !isEditing:
            state.move(extending ? .left : .right, in: sheet)
            return .handled
        // Traversing while typing keeps you typing in the next cell.
        case .tab where isEditing:
            state.commitEditing(
                in: &document.workbook, then: extending ? .left : .right, keepingEditor: true
            )
            return .handled
        case .return where isEditing:
            state.commitEditing(
                in: &document.workbook, then: extending ? .up : .down, keepingEditor: true
            )
            return .handled
        case .return where !isEditing:
            state.beginEditing(state.selectedAddress, in: document.workbook)
            return .handled
        case .escape where isEditing:
            state.cancelEditing()
            return .handled
        case .delete where !isEditing, .deleteForward where !isEditing:
            state.clearContents(in: &document.workbook)
            return .handled
        default:
            break
        }

        guard !isEditing, !press.characters.isEmpty else { return .ignored }

        if press.modifiers.contains(.command) {
            switch press.characters.lowercased() {
            case "b": state.toggleBold(in: &document.workbook); return .handled
            case "i": state.toggleItalic(in: &document.workbook); return .handled
            case "u": state.toggleUnderline(in: &document.workbook); return .handled
            case "c": state.copySelection(in: document.workbook); return .handled
            case "x": state.cutSelection(in: &document.workbook); return .handled
            case "v": state.paste(in: &document.workbook); return .handled
            case "a": state.selectAll(in: sheet); return .handled
            default: return .ignored
            }
        }

        // Any other printable key starts an edit with that character.
        guard let first = press.characters.first, !first.isNewline, first.isLetter || first.isNumber
                || first.isPunctuation || first.isSymbol || first == " " else {
            return .ignored
        }
        state.beginEditing(state.selectedAddress, in: document.workbook, replacingWith: press.characters)
        return .handled
    }
}
