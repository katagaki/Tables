import SwiftUI

/// Every mutation the UI performs on the document, in one place so the grid,
/// the toolbars and the keyboard commands all go through the same code.
extension EditorState {

    // MARK: - Editing

    func beginEditing(_ address: CellAddress, in workbook: Workbook, replacingWith seed: String? = nil) {
        let sheet = activeSheet(in: workbook)
        guard sheet.contains(address) else { return }
        select(address)
        editingAddress = address
        editingText = seed ?? sheet[address].editableText
        scrollTarget = address
    }

    func cancelEditing() {
        editingAddress = nil
        editingText = ""
        isFormulaBarActive = false
        pendingReferenceRange = nil
    }

    // MARK: - Building formulas by pointing

    /// Writes `range` into the formula being typed. Repeated calls replace the
    /// reference inserted last, so dragging grows one reference instead of
    /// appending a trail of them.
    func insertReference(_ range: CellRange, in workbook: Workbook) {
        guard isEnteringFormula else { return }
        let reference = range.normalized.a1

        if let previous = pendingReferenceRange {
            let previousText = previous.normalized.a1
            if editingText.hasSuffix(previousText) {
                editingText.removeLast(previousText.count)
            }
        } else if let last = editingText.last, last.isLetter || last.isNumber || last == ")" {
            // Following a completed term, join with an operator the user can replace.
            editingText.append("+")
        }
        editingText += reference
        pendingReferenceRange = range.normalized
    }

    /// Ends a pointing sequence so the next tap starts a fresh reference.
    func finishReferenceInsertion() {
        pendingReferenceRange = nil
    }

    /// Writes the in-progress text into its cell and recalculates.
    ///
    /// `keepingEditor` carries the current mode to the next cell: pressing Return
    /// or Tab while typing lands you typing in the neighbour, rather than
    /// dropping back to selection and making you re-open the editor.
    func commitEditing(
        in workbook: inout Workbook,
        then advance: MoveDirection? = .down,
        keepingEditor: Bool = false
    ) {
        guard let address = editingAddress else { return }
        let wasEditingInFormulaBar = isFormulaBarActive
        let index = activeIndex(in: workbook)
        let existing = workbook.sheets[index][address]
        workbook.sheets[index][address] = CellInputParser.cell(from: editingText, inheriting: existing.style)
        workbook.recalculate()

        editingAddress = nil
        editingText = ""
        isFormulaBarActive = false
        pendingReferenceRange = nil
        select(address)

        guard let advance else { return }
        move(advance, in: workbook.sheets[index])
        if keepingEditor {
            beginEditing(selectedAddress, in: workbook)
            isFormulaBarActive = wasEditingInFormulaBar
        }
    }

    /// Replaces the contents of every selected cell, keeping formatting.
    func clearContents(in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        for address in selection.addresses where workbook.sheets[index].contains(address) {
            var cell = workbook.sheets[index][address]
            cell.value = .empty
            cell.formula = nil
            workbook.sheets[index][address] = cell
        }
        workbook.recalculate()
    }

    func clearFormatting(in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        for address in selection.addresses where workbook.sheets[index].contains(address) {
            var cell = workbook.sheets[index][address]
            cell.style = .default
            workbook.sheets[index][address] = cell
        }
    }

    // MARK: - Formatting

    /// The style shown in the inspector: the anchor cell's, which is what edits build on.
    func representativeStyle(in workbook: Workbook) -> CellStyle {
        activeSheet(in: workbook)[selectedAddress].style
    }

    func applyStyle(in workbook: inout Workbook, _ transform: (inout CellStyle) -> Void) {
        let index = activeIndex(in: workbook)
        for address in selection.addresses where workbook.sheets[index].contains(address) {
            var cell = workbook.sheets[index][address]
            transform(&cell.style)
            workbook.sheets[index][address] = cell
        }
    }

    func toggleBold(in workbook: inout Workbook) {
        let target = !representativeStyle(in: workbook).isBold
        applyStyle(in: &workbook) { $0.isBold = target }
    }

    func toggleItalic(in workbook: inout Workbook) {
        let target = !representativeStyle(in: workbook).isItalic
        applyStyle(in: &workbook) { $0.isItalic = target }
    }

    func toggleUnderline(in workbook: inout Workbook) {
        let target = !representativeStyle(in: workbook).isUnderlined
        applyStyle(in: &workbook) { $0.isUnderlined = target }
    }

    func toggleStrikethrough(in workbook: inout Workbook) {
        let target = !representativeStyle(in: workbook).isStruckThrough
        applyStyle(in: &workbook) { $0.isStruckThrough = target }
    }

    // MARK: - Structure

    private func selectedRowRange(in sheet: Worksheet) -> ClosedRange<Int> {
        let box = selection.normalized
        return box.start.row...min(box.end.row, max(0, sheet.rowCount - 1))
    }

    private func selectedColumnRange(in sheet: Worksheet) -> ClosedRange<Int> {
        let box = selection.normalized
        return box.start.column...min(box.end.column, max(0, sheet.columnCount - 1))
    }

    func addRows(_ count: Int = 1, in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        workbook.sheets[index].addRows(count)
        finishStructuralEdit(in: workbook)
    }

    func addColumns(_ count: Int = 1, in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        workbook.sheets[index].addColumns(count)
        finishStructuralEdit(in: workbook)
    }

    func insertRows(above: Bool, in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        let range = selectedRowRange(in: workbook.sheets[index])
        let target = above ? range.lowerBound : range.upperBound + 1
        workbook.sheets[index].insertRows(range.count, at: target)
        workbook.recalculate()
        finishStructuralEdit(in: workbook)
    }

    func insertColumns(before: Bool, in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        let range = selectedColumnRange(in: workbook.sheets[index])
        let target = before ? range.lowerBound : range.upperBound + 1
        workbook.sheets[index].insertColumns(range.count, at: target)
        workbook.recalculate()
        finishStructuralEdit(in: workbook)
    }

    func deleteSelectedRows(in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        workbook.sheets[index].removeRows(selectedRowRange(in: workbook.sheets[index]))
        workbook.recalculate()
        finishStructuralEdit(in: workbook)
    }

    func deleteSelectedColumns(in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        workbook.sheets[index].removeColumns(selectedColumnRange(in: workbook.sheets[index]))
        workbook.recalculate()
        finishStructuralEdit(in: workbook)
    }

    func setSelectedRows(hidden: Bool, in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        workbook.sheets[index].setRows(selectedRowRange(in: workbook.sheets[index]), hidden: hidden)
        finishStructuralEdit(in: workbook)
    }

    func setSelectedColumns(hidden: Bool, in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        workbook.sheets[index].setColumns(selectedColumnRange(in: workbook.sheets[index]), hidden: hidden)
        finishStructuralEdit(in: workbook)
    }

    func unhideEverything(in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        workbook.sheets[index].unhideAll()
        finishStructuralEdit(in: workbook)
    }

    func resizeColumn(_ column: Int, to width: Double, in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        workbook.sheets[index].columnWidths[column] = max(Worksheet.minimumColumnWidth, width)
        finishStructuralEdit(in: workbook)
    }

    func resizeRow(_ row: Int, to height: Double, in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        workbook.sheets[index].rowHeights[row] = max(Worksheet.minimumRowHeight, height)
        finishStructuralEdit(in: workbook)
    }

    /// Sizes a column to its widest visible entry.
    func fitColumn(_ column: Int, in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        let sheet = workbook.sheets[index]
        var widest = Worksheet.minimumColumnWidth
        for row in 0..<sheet.rowCount where !sheet.hiddenRows.contains(row) {
            let cell = sheet[CellAddress(row: row, column: column)]
            let text = CellFormatter.displayText(for: cell)
            guard !text.isEmpty else { continue }
            let estimate = Double(text.count) * cell.style.fontSize * 0.62 + 20
            widest = max(widest, estimate)
        }
        workbook.sheets[index].columnWidths[column] = min(420, widest)
        finishStructuralEdit(in: workbook)
    }

    private func finishStructuralEdit(in workbook: Workbook) {
        clampSelection(to: activeSheet(in: workbook))
        refreshMetrics(in: workbook)
    }

    // MARK: - Clipboard

    func copySelection(in workbook: Workbook) {
        let sheet = activeSheet(in: workbook)
        let box = selection.normalized
        clipboard = box.rowRange.map { row in
            box.columnRange.map { column in sheet[CellAddress(row: row, column: column)] }
        }
        #if canImport(UIKit)
        UIPasteboard.general.string = plainText(for: box, in: sheet)
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plainText(for: box, in: sheet), forType: .string)
        #endif
    }

    func cutSelection(in workbook: inout Workbook) {
        copySelection(in: workbook)
        clearContents(in: &workbook)
    }

    func paste(in workbook: inout Workbook) {
        if let clipboard, !clipboard.isEmpty {
            paste(cells: clipboard, in: &workbook)
            return
        }
        #if canImport(UIKit)
        let text = UIPasteboard.general.string
        #else
        let text = NSPasteboard.general.string(forType: .string)
        #endif
        guard let text, !text.isEmpty else { return }
        let rows = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { line in
            line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        }
        let cells = rows.map { row in row.map { CellInputParser.cell(from: $0, inheriting: .default) } }
        paste(cells: cells, in: &workbook)
    }

    private func paste(cells: [[Cell]], in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        let origin = selection.normalized.start
        var lastRow = origin.row
        var lastColumn = origin.column

        for (rowOffset, row) in cells.enumerated() {
            for (columnOffset, cell) in row.enumerated() {
                let address = CellAddress(row: origin.row + rowOffset, column: origin.column + columnOffset)
                guard workbook.sheets[index].contains(address) else { continue }
                workbook.sheets[index][address] = cell
                lastRow = max(lastRow, address.row)
                lastColumn = max(lastColumn, address.column)
            }
        }
        workbook.recalculate()
        anchor = origin
        selection = CellRange(start: origin, end: CellAddress(row: lastRow, column: lastColumn))
    }

    private func plainText(for range: CellRange, in sheet: Worksheet) -> String {
        range.rowRange.map { row in
            range.columnRange
                .map { CellFormatter.displayText(for: sheet[CellAddress(row: row, column: $0)]) }
                .joined(separator: "\t")
        }
        .joined(separator: "\n")
    }

    // MARK: - Sheets

    func addSheet(in workbook: inout Workbook) {
        let id = workbook.addSheet()
        selectSheet(id, in: workbook)
    }

    func duplicateActiveSheet(in workbook: inout Workbook) {
        guard let id = workbook.duplicateSheet(activeSheet(in: workbook).id) else { return }
        selectSheet(id, in: workbook)
    }

    func deleteSheet(_ id: Worksheet.ID, in workbook: inout Workbook) {
        guard workbook.sheets.count > 1 else {
            errorMessage = "A workbook needs at least one sheet."
            return
        }
        let wasActive = activeSheet(in: workbook).id == id
        workbook.removeSheet(id)
        if wasActive, let first = workbook.sheets.first {
            selectSheet(first.id, in: workbook)
        }
    }

    // MARK: - Quick insert

    /// Wraps the selected range in a function and writes it just past the range.
    func insertAggregate(_ function: String, in workbook: inout Workbook) {
        let index = activeIndex(in: workbook)
        let sheet = workbook.sheets[index]
        let box = selection.normalized

        let target: CellAddress
        let reference: String
        if box.isSingleCell {
            // Nothing to summarize yet — just start the formula for the user.
            beginEditing(box.start, in: workbook, replacingWith: "=\(function)(")
            return
        } else if box.end.row + 1 < sheet.rowCount {
            target = CellAddress(row: box.end.row + 1, column: box.start.column)
            reference = CellRange(
                start: box.start,
                end: CellAddress(row: box.end.row, column: box.start.column)
            ).a1
        } else {
            target = CellAddress(row: box.start.row, column: min(box.end.column + 1, sheet.columnCount - 1))
            reference = CellRange(
                start: box.start,
                end: CellAddress(row: box.start.row, column: box.end.column)
            ).a1
        }

        var cell = workbook.sheets[index][target]
        cell.formula = "\(function)(\(reference))"
        cell.value = .empty
        workbook.sheets[index][target] = cell
        workbook.recalculate()
        select(target)
        scrollTarget = target
    }
}
