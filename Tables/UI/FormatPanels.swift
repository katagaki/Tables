import SwiftUI

/// Cell appearance controls. Shared by the iOS sheet and the macOS popover.
struct FormatPanel: View {
    @Binding var workbook: Workbook
    @Bindable var state: EditorState

    private var style: CellStyle { state.representativeStyle(in: workbook) }

    var body: some View {
        Form {
            Section("Text") {
                HStack(spacing: 12) {
                    styleToggle("bold", isOn: style.isBold) { state.toggleBold(in: &workbook) }
                    styleToggle("italic", isOn: style.isItalic) { state.toggleItalic(in: &workbook) }
                    styleToggle("underline", isOn: style.isUnderlined) { state.toggleUnderline(in: &workbook) }
                    styleToggle("strikethrough", isOn: style.isStruckThrough) {
                        state.toggleStrikethrough(in: &workbook)
                    }
                }

                LabeledContent("Size") {
                    HStack(spacing: 16) {
                        Button {
                            state.applyStyle(in: &workbook) { $0.fontSize = max(6, $0.fontSize - 1) }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 17, weight: .medium))
                                .frame(width: 30, height: 30)
                                .contentShape(.rect)
                        }
                        .accessibilityIdentifier("fontSize.decrease")
                        .accessibilityLabel("Smaller text")
                        Text(String(Int(style.fontSize)))
                            .font(.system(size: 17, weight: .medium))
                            .monospacedDigit()
                            .frame(minWidth: 30)
                            .accessibilityIdentifier("fontSize.value")
                        Button {
                            state.applyStyle(in: &workbook) { $0.fontSize = min(96, $0.fontSize + 1) }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .medium))
                                .frame(width: 30, height: 30)
                                .contentShape(.rect)
                        }
                        .accessibilityIdentifier("fontSize.increase")
                        .accessibilityLabel("Larger text")
                    }
                    .buttonStyle(.borderless)
                }

                SystemColorSwatches(
                    role: .text,
                    selectedHex: style.textColorHex,
                    customColor: Binding(
                        get: { style.textColor ?? .primary },
                        set: { newValue in
                            state.applyStyle(in: &workbook) { $0.textColorHex = newValue.argbHex }
                        }
                    ),
                    onSelect: { swatch in
                        state.applyStyle(in: &workbook) { $0.textColorHex = swatch.argbHex }
                    },
                    onClear: {
                        state.applyStyle(in: &workbook) { $0.textColorHex = nil }
                    }
                )
            }

            Section("Fill") {
                SystemColorSwatches(
                    role: .fill,
                    selectedHex: style.fillColorHex,
                    customColor: Binding(
                        get: { style.fillColor ?? .clear },
                        set: { newValue in
                            state.applyStyle(in: &workbook) { $0.fillColorHex = newValue.argbHex }
                        }
                    ),
                    onSelect: { swatch in
                        state.applyStyle(in: &workbook) { $0.fillColorHex = swatch.argbHex }
                    },
                    onClear: {
                        state.applyStyle(in: &workbook) { $0.fillColorHex = nil }
                    }
                )
            }

            Section("Alignment") {
                Picker("Horizontal", selection: Binding(
                    get: { style.horizontalAlignment },
                    set: { value in state.applyStyle(in: &workbook) { $0.horizontalAlignment = value } }
                )) {
                    ForEach(HorizontalTextAlignment.allCases, id: \.self) { option in
                        Label(option.label, systemImage: option.symbolName).tag(option)
                    }
                }
                Picker("Vertical", selection: Binding(
                    get: { style.verticalAlignment },
                    set: { value in state.applyStyle(in: &workbook) { $0.verticalAlignment = value } }
                )) {
                    ForEach(VerticalTextAlignment.allCases, id: \.self) { option in
                        Label(option.label, systemImage: option.symbolName).tag(option)
                    }
                }
                Toggle("Wrap Text", isOn: Binding(
                    get: { style.wrapsText },
                    set: { value in state.applyStyle(in: &workbook) { $0.wrapsText = value } }
                ))

                LabeledContent("Indent") {
                    HStack(spacing: 12) {
                        Button {
                            state.applyStyle(in: &workbook) { $0.indent = max(0, $0.indent - 1) }
                        } label: {
                            Image(systemName: "decrease.indent")
                        }
                        Text(String(style.indent))
                            .font(.system(size: 13, weight: .medium))
                            .frame(minWidth: 26)
                        Button {
                            state.applyStyle(in: &workbook) { $0.indent = min(250, $0.indent + 1) }
                        } label: {
                            Image(systemName: "increase.indent")
                        }
                    }
                    .buttonStyle(.borderless)
                }

                Picker("Rotation", selection: Binding(
                    get: { style.textRotation },
                    set: { value in state.applyStyle(in: &workbook) { $0.textRotation = value } }
                )) {
                    // OOXML stores clockwise angles as 90 + the angle.
                    Text("None").tag(0)
                    Text("45° Up").tag(45)
                    Text("90° Up").tag(90)
                    Text("45° Down").tag(135)
                    Text("90° Down").tag(180)
                    Text("Stacked").tag(CellStyle.stackedTextRotation)
                }
            }

            Section("Borders") {
                HStack(spacing: 8) {
                    borderButton("square", edges: .all, label: "All edges")
                    borderButton("square.tophalf.filled", edges: .top, label: "Top")
                    borderButton("square.bottomhalf.filled", edges: .bottom, label: "Bottom")
                    borderButton("square.lefthalf.filled", edges: .leading, label: "Left")
                    borderButton("square.righthalf.filled", edges: .trailing, label: "Right")
                }

                Picker("Line Style", selection: Binding(
                    // Dictionary order is arbitrary, so pick a fixed edge order:
                    // a mixed selection has to show one style, not a random one.
                    get: {
                        BorderEdge.allCases.compactMap { style.borderSides[$0]?.lineStyle }.first
                            ?? style.diagonalBorder?.lineStyle ?? .thin
                    },
                    set: { value in
                        state.applyStyle(in: &workbook) { current in
                            for edge in current.borderSides.keys {
                                current.borderSides[edge]?.lineStyle = value
                            }
                            current.diagonalBorder?.lineStyle = value
                        }
                    }
                )) {
                    ForEach(BorderLineStyle.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }

                Toggle("Diagonal Up", isOn: Binding(
                    get: { style.diagonalBorder?.goesUp ?? false },
                    set: { value in
                        state.applyStyle(in: &workbook) { current in
                            current.setDiagonal(up: value, down: current.diagonalBorder?.goesDown ?? false)
                        }
                    }
                ))
                Toggle("Diagonal Down", isOn: Binding(
                    get: { style.diagonalBorder?.goesDown ?? false },
                    set: { value in
                        state.applyStyle(in: &workbook) { current in
                            current.setDiagonal(up: current.diagonalBorder?.goesUp ?? false, down: value)
                        }
                    }
                ))

                Button("Remove Borders") {
                    state.applyStyle(in: &workbook) {
                        $0.borders = []
                        $0.diagonalBorder = nil
                    }
                }
            }

            Section("Merge") {
                Button("Merge Cells") { state.mergeSelection(in: &workbook) }
                    .disabled(!state.canMergeSelection(in: workbook))
                Button("Unmerge Cells") { state.unmergeSelection(in: &workbook) }
                    .disabled(!state.canUnmergeSelection(in: workbook))
            }

            Section {
                Button("Clear All Formatting", role: .destructive) {
                    state.clearFormatting(in: &workbook)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func styleToggle(_ symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 46, height: 46)
                .background(isOn ? Color.accentColor.opacity(0.2) : .clear, in: .circle)
                .foregroundStyle(isOn ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
    }

    private func borderButton(_ symbol: String, edges: BorderEdges, label: String) -> some View {
        Button {
            state.applyStyle(in: &workbook) { current in
                if current.borders.isSuperset(of: edges) {
                    current.borders.subtract(edges)
                } else {
                    current.borders.formUnion(edges)
                }
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 19))
                .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Number format presets plus a free-form OOXML format code field.
struct NumberFormatPanel: View {
    @Binding var workbook: Workbook
    @Bindable var state: EditorState

    @State private var customCode = ""

    private var currentCode: String { state.representativeStyle(in: workbook).numberFormat }

    var body: some View {
        Form {
            Section("Presets") {
                ForEach(NumberFormatPreset.allCases) { preset in
                    Button {
                        state.applyStyle(in: &workbook) { $0.numberFormat = preset.code }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.label)
                                Text(sample(for: preset))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if currentCode == preset.code {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Custom Format Code") {
                TextField("e.g. #,##0.00 \"kg\"", text: $customCode)
                    .font(.system(size: 13))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
                Button("Apply") {
                    let code = customCode.trimmed
                    guard !code.isEmpty else { return }
                    state.applyStyle(in: &workbook) { $0.numberFormat = code }
                }
                .disabled(customCode.trimmed.isEmpty)
            }
        }
        .formStyle(.grouped)
        .onAppear { customCode = currentCode }
    }

    private func sample(for preset: NumberFormatPreset) -> String {
        let value: CellValue = preset == .text ? .text("Text") : .number(preset.code.contains("%") ? 0.128 : 1234.5)
        return CellFormatter.displayText(for: value, format: preset.code)
    }
}

/// Row and column structure: add, insert, delete, hide, resize.
struct RowsColumnsPanel: View {
    @Binding var workbook: Workbook
    @Bindable var state: EditorState

    private var activeSheet: Worksheet { state.activeSheet(in: workbook) }

    var body: some View {
        Form {
            Section("Sheet Size") {
                LabeledContent("Rows", value: String(activeSheet.rowCount))
                LabeledContent("Columns", value: String(activeSheet.columnCount))
                Button("Add 1 Row") { state.addRows(in: &workbook) }
                Button("Add 10 Rows") { state.addRows(10, in: &workbook) }
                Button("Add 1 Column") { state.addColumns(in: &workbook) }
                Button("Add 5 Columns") { state.addColumns(5, in: &workbook) }
            }

            Section("Rows") {
                Button("Insert Above") { state.insertRows(above: true, in: &workbook) }
                Button("Insert Below") { state.insertRows(above: false, in: &workbook) }
                Button("Hide Selected") { state.setSelectedRows(hidden: true, in: &workbook) }
                Button("Show Selected") { state.setSelectedRows(hidden: false, in: &workbook) }
                Button("Delete Selected", role: .destructive) { state.deleteSelectedRows(in: &workbook) }
                    .disabled(activeSheet.rowCount <= 1)
            }

            Section("Columns") {
                Button("Insert Before") { state.insertColumns(before: true, in: &workbook) }
                Button("Insert After") { state.insertColumns(before: false, in: &workbook) }
                Button("Hide Selected") { state.setSelectedColumns(hidden: true, in: &workbook) }
                Button("Show Selected") { state.setSelectedColumns(hidden: false, in: &workbook) }
                Button("Delete Selected", role: .destructive) { state.deleteSelectedColumns(in: &workbook) }
                    .disabled(activeSheet.columnCount <= 1)
            }

            Section {
                let hiddenCount = activeSheet.hiddenRows.count + activeSheet.hiddenColumns.count
                Button("Show All Hidden (\(hiddenCount))") { state.unhideEverything(in: &workbook) }
                    .disabled(hiddenCount == 0)
            }
        }
        .formStyle(.grouped)
    }
}

/// A searchable list of built-in functions that seeds the formula editor.
struct FunctionsPanel: View {
    @Binding var workbook: Workbook
    @Bindable var state: EditorState

    @State private var query = ""

    private var matches: [String] {
        let trimmed = query.trimmed
        guard !trimmed.isEmpty else { return FormulaFunctions.names }
        return FormulaFunctions.names.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List {
            ForEach(matches, id: \.self) { name in
                Button {
                    insert(name)
                } label: {
                    HStack {
                        Text(name).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $query, prompt: "Search functions")
    }

    private func insert(_ name: String) {
        let box = state.selection.normalized
        if box.isSingleCell {
            state.beginEditing(box.start, in: workbook, replacingWith: "=\(name)(")
        } else {
            state.insertAggregate(name, in: &workbook)
        }
        state.presentedPanel = nil
    }
}
