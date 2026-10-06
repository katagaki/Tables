import SwiftUI

/// The document's root view: the grid, the formula bar beneath it, sheet tabs,
/// and whichever platform chrome belongs on top.
struct WorkbookView: View {
    @Binding var document: TablesDocument
    /// The file's name, which macros see as `ThisWorkbook.Name`.
    var fileName: String?
    @State private var state = EditorState()
    @State private var history = WorkbookHistory()
    @State private var macroRunner = MacroRunner()
    @State private var isShowingMacros = false
    /// The macro waiting on the user's say-so before the first run.
    @State private var pendingMacro: MacroCatalog.Macro?
    /// Asked once per window: after that, running a macro just runs it.
    @State private var hasAllowedMacros = false
    @State private var macroInput = ""
    @Environment(\.undoManager) private var undoManager
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Namespace private var panelTransition

    private var workbook: Binding<Workbook> { $document.workbook }

    var body: some View {
        VStack(spacing: 0) {
            sheetContent
                // Keyboard navigation belongs to the grid, and only while no
                // text field is up — otherwise it holds focus away from them.
                .focusable(state.editingAddress == nil && !state.isFormulaBarActive)
                .focusEffectDisabled()
                .onKeyPress(action: handleKeyPress)
                .overlay(alignment: .bottom) {
                    #if os(iOS)
                    FloatingActionBar(
                        workbook: workbook, state: state, namespace: panelTransition,
                        // Any workbook can be given macros; delimited text has nowhere to keep them.
                        showMacros: document.isPlainText ? nil : { isShowingMacros = true },
                        isMacroRunning: macroRunner.isRunning
                    )
                        .padding(.bottom, 8)
                    #endif
                }

            Divider()
            // A chart sheet has no cells to show a formula for.
            if !activeSheet.isChartSheet {
                FormulaBarView(workbook: workbook, state: state)
                Divider()
            }
            SheetTabBarView(workbook: workbook, state: state)
                .background(.bar)
        }
        .background(Color.sheetBackground)
        .overlay { if macroRunner.isRunning { runningMacroOverlay } }
        .modifier(MacroPrompts(runner: macroRunner, input: $macroInput))
        .sheet(isPresented: $isShowingMacros) { macrosSheet }
        .confirmationDialog(
            "Macros.Confirm.Title",
            isPresented: Binding(get: { pendingMacro != nil }, set: { if !$0 { pendingMacro = nil } }),
            titleVisibility: .visible,
            presenting: pendingMacro
        ) { macro in
            Button("Macros.Confirm.Run") {
                hasAllowedMacros = true
                runMacro(macro)
            }
        } message: { _ in
            Text("Macros.Confirm.Message")
        }
        .onAppear {
            state.allowsFormatting = !document.isPlainText
            if state.activeSheetID == nil {
                state.activeSheetID = document.workbook.sheets.first?.id
                state.refreshMetrics(in: document.workbook)
            }
            attachHistory()
        }
        .onChange(of: undoManager) { _, _ in attachHistory() }
        .onChange(of: document.workbook) { old, new in history.record(from: old, to: new) }
        .onChange(of: state.activeSheetID) { _, _ in
            // CSV holds one sheet; export whichever one the user is looking at.
            document.csvExport.sheetIndex = state.activeIndex(in: document.workbook)
        }
        #if os(iOS)
        .toolbar { undoToolbar }
        .toolbar { moreToolbar }
        #endif
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
    }

    private var activeSheet: Worksheet { state.activeSheet(in: document.workbook) }

    @ViewBuilder
    private var sheetContent: some View {
        if activeSheet.isChartSheet {
            ChartSheetView(workbook: workbook, state: state, sheet: activeSheet)
        } else {
            SheetGridView(workbook: workbook, state: state)
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
        case .chart: ChartPanel(workbook: workbook, state: state)
        case .comment: CommentPanel(workbook: workbook, state: state)
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

    private func attachHistory() {
        let document = $document
        let state = state
        history.attach(
            to: undoManager,
            read: { document.wrappedValue.workbook },
            write: { document.wrappedValue.workbook = $0 },
            restored: { now, before in state.showRestored(now, replacing: before) }
        )
    }

    #if os(iOS)
    /// macOS has Undo and Redo in its Edit menu; iOS has nowhere to put them
    /// but here, and a hardware keyboard reaches them through these too.
    @ToolbarContentBuilder
    private var undoToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Toolbar.Undo", systemImage: "arrow.uturn.backward") { history.undo() }
                .disabled(!history.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityIdentifier("undo")
            if horizontalSizeClass != .compact {
                redoButton
            }
        }
    }

    private var redoButton: some View {
        Button("Toolbar.Redo", systemImage: "arrow.uturn.forward") { history.redo() }
            .disabled(!history.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .accessibilityIdentifier("redo")
    }

    /// Secondary actions are gathered into the navigation bar's "…" menu.
    @ToolbarContentBuilder
    private var moreToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .secondaryAction) {
            // A narrow bar has no room for Redo and would push it into this
            // menu itself, below everything here. Placing it keeps Source Code last.
            if horizontalSizeClass == .compact {
                redoButton
            }
            Section {
                Link(destination: URL(string: "https://github.com/katagaki/Tables")!) {
                    Label("Toolbar.SourceCode", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
    }
    #endif

    @ToolbarContentBuilder
    private var sharingToolbar: some ToolbarContent {
        #if os(macOS)
        // On iOS this lives in the floating action bar instead.
        if !document.isPlainText {
            ToolbarItem(placement: .primaryAction) {
                Button("Toolbar.Macros", systemImage: "curlybraces") { isShowingMacros = true }
                    .disabled(macroRunner.isRunning)
                    .help(String(localized: "Toolbar.Macros"))
                    .accessibilityIdentifier("macros")
            }
        }
        #endif
        // Declared before the share button so it sits beside it on the inside.
        if !document.unsupportedFeatures.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.isShowingUnsupportedFeatureNotice = true
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .accessibilityIdentifier("unsupportedFeatures")
                .accessibilityLabel("Toolbar.UnsupportedFeatures.Label")
                .popover(isPresented: $state.isShowingUnsupportedFeatureNotice) {
                    UnsupportedFeatureNotice(report: document.unsupportedFeatures)
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            ShareLink(item: export, preview: SharePreview(export.name, image: Image(systemName: "tablecells")))
                .accessibilityLabel("Toolbar.Share.Label")
        }
    }

    #if os(macOS)
    /// macOS gets one horizontal toolbar holding everything.
    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
        // Delimited text keeps no styling, so there is nothing to format.
        if state.allowsFormatting {
            formattingToolbar
        }

        ToolbarItemGroup {
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

        ToolbarItemGroup {
            Menu {
                InsertChartMenuItems(workbook: $document.workbook, state: state)
            } label: {
                Image(systemName: "chart.bar.xaxis")
            }
            .menuIndicator(.hidden)
            .disabled(activeSheet.isChartSheet)
            .help(String(localized: "Toolbar.InsertChart"))
            .accessibilityLabel(String(localized: "Toolbar.InsertChart"))

            if state.selectedChartID != nil {
                toolbarToggle(
                    "slider.horizontal.3", label: String(localized: "Toolbar.EditChart"),
                    isOn: state.presentedPanel == .chart
                ) {
                    state.presentedPanel = .chart
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var formattingToolbar: some ToolbarContent {
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

    // MARK: - Macros

    private var macrosSheet: some View {
        let loaded = Result { try document.workbook.macroProject.map(VBAProject.init(data:)) }
        return MacrosView(
            project: (try? loaded.get()) ?? nil,
            loadError: loaded.failureDescription,
            isMacroEnabledFile: document.isMacroEnabled,
            workingFolder: MacroFiles.folder(forWorkbookNamed: fileName),
            output: macroRunner.output,
            run: { module, procedure in
                let macro = MacroCatalog.Macro(module: module, procedure: procedure)
                isShowingMacros = false
                if hasAllowedMacros {
                    runMacro(macro)
                } else {
                    pendingMacro = macro
                }
            },
            edit: { change in
                guard let data = document.workbook.macroProject else { return }
                var project = try VBAProject(data: data)
                try change(&project)
                document.workbook.setMacroProject(try project.data())
            },
            createProject: { try document.workbook.createMacroProject() }
        )
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    /// Runs a macro on a copy of the workbook and puts back what it made
    /// of it in one change, so a single undo takes the whole run back.
    private func runMacro(_ macro: MacroCatalog.Macro) {
        guard let data = document.workbook.macroProject, let project = try? VBAProject(data: data) else { return }
        state.commitEditing(in: &document.workbook, then: nil)
        let before = document.workbook
        Task {
            let outcome = await macroRunner.run(
                macro.procedure, in: macro.module, project: project, workbook: before,
                workbookName: fileName ?? String(localized: "Macros.DefaultWorkbookName"),
                activeSheet: state.activeSheetID, selection: state.selection,
                workingFolder: MacroFiles.folder(forWorkbookNamed: fileName)
            )
            if outcome.workbook != before { document.workbook = outcome.workbook }
            if outcome.activeSheetID != state.activeSheetID, outcome.workbook.index(of: outcome.activeSheetID) != nil {
                state.selectSheet(outcome.activeSheetID, in: outcome.workbook)
            }
            state.selection = outcome.selection
            state.anchor = outcome.selection.start
            state.additionalSelections = []
            state.clampSelection(to: state.activeSheet(in: document.workbook))
            state.refreshMetrics(in: document.workbook)
            if let failure = outcome.failure {
                state.errorMessage = String(format: String(localized: "Macros.Failed"), failure)
            }
        }
    }

    /// While a macro runs the sheet is the macro's: a veil keeps edits off
    /// it, and says how to stop a macro that does not finish.
    private var runningMacroOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.08)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture {}
            HStack(spacing: 12) {
                ProgressView()
                Text(String(format: String(localized: "Macros.Running"), macroRunner.runningMacro ?? ""))
                    .lineLimit(1)
                Button("Macros.Stop", role: .destructive) { macroRunner.stop() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("stopMacro")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Keyboard

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        let sheet = state.activeSheet(in: document.workbook)
        let isEditing = state.editingAddress != nil
        let extending = press.modifiers.contains(.shift)

        // With a chart picked out, the keyboard is about the chart.
        if state.selectedChartID != nil, !isEditing {
            switch press.key {
            case .delete, .deleteForward:
                state.deleteSelectedChart(in: &document.workbook)
                return .handled
            case .escape where !sheet.isChartSheet:
                state.selectChart(nil)
                return .handled
            case .return:
                state.presentedPanel = .chart
                return .handled
            default:
                if !sheet.isChartSheet { state.selectChart(nil) }
            }
        }
        // Likewise a picture.
        if state.selectedDrawingID != nil, !isEditing {
            switch press.key {
            case .delete, .deleteForward:
                state.deleteSelectedDrawing(in: &document.workbook)
                return .handled
            case .escape:
                state.selectDrawing(nil)
                return .handled
            default:
                state.selectDrawing(nil)
            }
        }
        // There are no cells on a chart sheet to move between or type into.
        guard !sheet.isChartSheet else { return .ignored }

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
            case "b" where state.allowsFormatting: state.toggleBold(in: &document.workbook); return .handled
            case "i" where state.allowsFormatting: state.toggleItalic(in: &document.workbook); return .handled
            case "u" where state.allowsFormatting: state.toggleUnderline(in: &document.workbook); return .handled
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

/// What the toolbar's warning button says: which parts of the file Tables can
/// only carry, and which it will drop.
///
/// A popover rather than an alert: nothing here needs deciding, so it has no
/// business stopping the user before they have seen their spreadsheet.
private struct UnsupportedFeatureNotice: View {
    var report: UnsupportedFeatureReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Notice.UnsupportedFeatures.Title", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .labelStyle(.titleAndIcon)
            Text(report.noticeMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                // A popover sizes itself to its content, and without this the
                // message is laid out on one unbroken line.
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .padding(20)
        .frame(idealWidth: 300, maxWidth: 340, alignment: .leading)
        // iPhone turns a popover into a sheet unless it is told not to.
        .presentationCompactAdaptation(.popover)
    }
}
