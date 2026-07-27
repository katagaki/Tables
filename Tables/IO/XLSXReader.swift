import Foundation

/// Reads an Office Open XML workbook (`.xlsx`) into the app's model.
enum XLSXReader {
    struct ReadError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static func workbook(from data: Data) throws -> Workbook {
        let entries = try ZipArchive.entries(in: data)

        guard let workbookEntry = entries["xl/workbook.xml"] else {
            throw ReadError(message: "The workbook is missing its main part.")
        }
        let workbookXML = try XMLLite.parse(workbookEntry)
        let relationships = parseRelationships(entries["xl/_rels/workbook.xml.rels"])
        let sharedStrings = parseSharedStrings(entries["xl/sharedStrings.xml"])
        let styles = parseStyles(entries["xl/styles.xml"])

        // Workbooks written on the classic Mac epoch count days from 1904.
        // Serials are normalized to the 1900 system on the way in so nothing
        // downstream has to know which system the file used.
        let usesMacEpoch = workbookXML.firstChild(named: "workbookPr")?.attribute("date1904") == "1"

        var sheets: [Worksheet] = []
        let sheetElements = workbookXML.firstChild(named: "sheets")?.children(named: "sheet") ?? []

        for (position, element) in sheetElements.enumerated() {
            let name = element.attribute("name") ?? "Sheet \(position + 1)"
            let target = element.attribute("id").flatMap { relationships[$0] }
            let path = resolvePath(target) ?? "xl/worksheets/sheet\(position + 1).xml"
            guard let payload = entries[path] ?? entries["xl/worksheets/sheet\(position + 1).xml"] else {
                sheets.append(Worksheet(name: name))
                continue
            }
            let sheetXML = try XMLLite.parse(payload)
            var sheet = parseSheet(
                sheetXML, name: name, sharedStrings: sharedStrings, styles: styles,
                usesMacEpoch: usesMacEpoch
            )
            sheet.name = name
            sheets.append(sheet)
        }

        guard !sheets.isEmpty else { throw ReadError(message: "The workbook contains no sheets.") }
        var workbook = Workbook(sheets: sheets)
        workbook.recalculate()
        return workbook
    }

    // MARK: - Package plumbing

    private static func parseRelationships(_ data: Data?) -> [String: String] {
        guard let data, let root = try? XMLLite.parse(data) else { return [:] }
        var result: [String: String] = [:]
        for relationship in root.children(named: "Relationship") {
            guard let id = relationship.attribute("Id"), let target = relationship.attribute("Target") else { continue }
            result[id] = target
        }
        return result
    }

    /// Relationship targets are relative to `xl/` unless already absolute.
    private static func resolvePath(_ target: String?) -> String? {
        guard var target else { return nil }
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        while target.hasPrefix("../") { target.removeFirst(3) }
        return target.hasPrefix("xl/") ? target : "xl/" + target
    }

    private static func parseSharedStrings(_ data: Data?) -> [String] {
        guard let data, let root = try? XMLLite.parse(data) else { return [] }
        return root.children(named: "si").map { item in
            if let direct = item.firstChild(named: "t") { return direct.text }
            // Rich text: concatenate every run.
            return item.children(named: "r").compactMap { $0.firstChild(named: "t")?.text }.joined()
        }
    }

    // MARK: - Styles

    private static let builtInNumberFormats: [Int: String] = [
        0: "General", 1: "0", 2: "0.00", 3: "#,##0", 4: "#,##0.00",
        9: "0%", 10: "0.00%", 11: "0.00E+00", 12: "# ?/?", 13: "# ??/??",
        14: "mm-dd-yy", 15: "d-mmm-yy", 16: "d-mmm", 17: "mmm-yy",
        18: "h:mm AM/PM", 19: "h:mm:ss AM/PM", 20: "h:mm", 21: "h:mm:ss",
        22: "m/d/yy h:mm", 37: "#,##0;(#,##0)", 38: "#,##0;[Red](#,##0)",
        39: "#,##0.00;(#,##0.00)", 40: "#,##0.00;[Red](#,##0.00)",
        45: "mm:ss", 46: "[h]:mm:ss", 47: "mmss.0", 48: "##0.0E+0", 49: "@",
    ]

    private static func parseStyles(_ data: Data?) -> [CellStyle] {
        guard let data, let root = try? XMLLite.parse(data) else { return [CellStyle.default] }

        var numberFormats = builtInNumberFormats
        for entry in root.firstChild(named: "numFmts")?.children(named: "numFmt") ?? [] {
            guard let id = entry.attribute("numFmtId").flatMap(Int.init),
                  let code = entry.attribute("formatCode") else { continue }
            numberFormats[id] = code
        }

        struct FontSpec {
            var bold = false, italic = false, underline = false, strike = false
            var size: Double = 12
            var name = "Helvetica Neue"
            var colorHex: String?
        }

        let fonts: [FontSpec] = (root.firstChild(named: "fonts")?.children(named: "font") ?? []).map { element in
            var spec = FontSpec()
            spec.bold = element.firstChild(named: "b") != nil
            spec.italic = element.firstChild(named: "i") != nil
            spec.underline = element.firstChild(named: "u") != nil
            spec.strike = element.firstChild(named: "strike") != nil
            if let size = element.firstChild(named: "sz")?.attribute("val").flatMap(Double.init) {
                spec.size = size
            }
            if let name = element.firstChild(named: "name")?.attribute("val") { spec.name = name }
            spec.colorHex = element.firstChild(named: "color")?.attribute("rgb")
            return spec
        }

        let fills: [String?] = (root.firstChild(named: "fills")?.children(named: "fill") ?? []).map { element in
            guard let pattern = element.firstChild(named: "patternFill"),
                  pattern.attribute("patternType") != "none" else { return nil }
            return pattern.firstChild(named: "fgColor")?.attribute("rgb")
        }

        struct BorderSpec {
            var edges: BorderEdges = []
            var colorHex: String?
        }

        let borders: [BorderSpec] = (root.firstChild(named: "borders")?.children(named: "border") ?? [])
            .map { element in
                var spec = BorderSpec()
                let sides: [(String, BorderEdges)] = [
                    ("left", .leading), ("right", .trailing), ("top", .top), ("bottom", .bottom),
                ]
                for (tag, edge) in sides {
                    guard let side = element.firstChild(named: tag),
                          let style = side.attribute("style"), style != "none" else { continue }
                    spec.edges.insert(edge)
                    if spec.colorHex == nil { spec.colorHex = side.firstChild(named: "color")?.attribute("rgb") }
                }
                return spec
            }

        let formats = root.firstChild(named: "cellXfs")?.children(named: "xf") ?? []
        guard !formats.isEmpty else { return [CellStyle.default] }

        return formats.map { element in
            var style = CellStyle()
            if let fontIndex = element.attribute("fontId").flatMap(Int.init), fonts.indices.contains(fontIndex) {
                let font = fonts[fontIndex]
                style.isBold = font.bold
                style.isItalic = font.italic
                style.isUnderlined = font.underline
                style.isStruckThrough = font.strike
                style.fontSize = font.size
                style.fontName = font.name
                style.textColorHex = font.colorHex
            }
            if let fillIndex = element.attribute("fillId").flatMap(Int.init), fills.indices.contains(fillIndex) {
                style.fillColorHex = fills[fillIndex]
            }
            if let borderIndex = element.attribute("borderId").flatMap(Int.init),
               borders.indices.contains(borderIndex) {
                style.borders = borders[borderIndex].edges
                style.borderColorHex = borders[borderIndex].colorHex
            }
            if let formatID = element.attribute("numFmtId").flatMap(Int.init) {
                style.numberFormat = numberFormats[formatID] ?? "General"
            }
            if let alignment = element.firstChild(named: "alignment") {
                switch alignment.attribute("horizontal") {
                case "left": style.horizontalAlignment = .leading
                case "center", "centerContinuous": style.horizontalAlignment = .center
                case "right": style.horizontalAlignment = .trailing
                default: style.horizontalAlignment = .automatic
                }
                switch alignment.attribute("vertical") {
                case "top": style.verticalAlignment = .top
                case "bottom": style.verticalAlignment = .bottom
                default: style.verticalAlignment = .middle
                }
                style.wrapsText = alignment.attribute("wrapText") == "1"
            }
            return style
        }
    }

    // MARK: - Sheet content

    private static func parseSheet(
        _ root: XMLElement, name: String, sharedStrings: [String], styles: [CellStyle],
        usesMacEpoch: Bool
    ) -> Worksheet {
        var sheet = Worksheet(name: name)
        var maximumRow = 0
        var maximumColumn = 0
        var sharedFormulas: [String: SharedFormula] = [:]

        // Column widths and visibility.
        for column in root.firstChild(named: "cols")?.children(named: "col") ?? [] {
            guard let first = column.attribute("min").flatMap(Int.init),
                  let last = column.attribute("max").flatMap(Int.init), first <= last else { continue }
            let hidden = column.attribute("hidden") == "1"
            // OOXML column width counts characters; convert to points.
            let width = column.attribute("width").flatMap(Double.init).map { $0 * 7 + 5 }
            for index in first...min(last, Worksheet.maximumColumnCount) {
                let zeroBased = index - 1
                if hidden { sheet.hiddenColumns.insert(zeroBased) }
                if let width, column.attribute("customWidth") == "1" {
                    sheet.columnWidths[zeroBased] = max(Worksheet.minimumColumnWidth, width)
                }
            }
        }

        for rowElement in root.firstChild(named: "sheetData")?.children(named: "row") ?? [] {
            guard let rowNumber = rowElement.attribute("r").flatMap(Int.init), rowNumber >= 1 else { continue }
            let rowIndex = rowNumber - 1
            maximumRow = max(maximumRow, rowNumber)

            if rowElement.attribute("hidden") == "1" { sheet.hiddenRows.insert(rowIndex) }
            if rowElement.attribute("customHeight") == "1",
               let height = rowElement.attribute("ht").flatMap(Double.init) {
                sheet.rowHeights[rowIndex] = max(Worksheet.minimumRowHeight, height * 1.35)
            }

            for cellElement in rowElement.children(named: "c") {
                guard let reference = cellElement.attribute("r"),
                      let address = CellAddress(a1: reference) else { continue }
                maximumColumn = max(maximumColumn, address.column + 1)

                var cell = Cell()
                if let styleIndex = cellElement.attribute("s").flatMap(Int.init),
                   styles.indices.contains(styleIndex) {
                    cell.style = styles[styleIndex]
                }
                if let element = cellElement.firstChild(named: "f") {
                    cell.formula = formula(from: element, at: address, shared: &sharedFormulas)
                }
                cell.value = decodeValue(cellElement, sharedStrings: sharedStrings)
                if usesMacEpoch, case .number(let serial) = cell.value,
                   CellFormatter.isDateFormat(cell.style.numberFormat) {
                    cell.value = .number(serial + macEpochOffset)
                }
                if !cell.isEmptyEntirely { sheet.cells[address] = cell }
            }
        }

        sheet.rowCount = max(Worksheet.defaultRowCount, min(maximumRow, Worksheet.maximumRowCount))
        sheet.columnCount = max(Worksheet.defaultColumnCount, min(maximumColumn, Worksheet.maximumColumnCount))
        sheet.hiddenRows = sheet.hiddenRows.filter { $0 < sheet.rowCount }
        sheet.hiddenColumns = sheet.hiddenColumns.filter { $0 < sheet.columnCount }
        return sheet
    }

    /// Where a shared formula was defined: its text and the cell that hosts it.
    private struct SharedFormula {
        var text: String
        var origin: CellAddress
    }

    /// Resolves a cell's `<f>` element, expanding shared formulas.
    ///
    /// Excel emits a shared formula whenever one is filled across a range: the
    /// first cell carries the text and an `si` index, and the rest carry only
    /// the index. Without expansion those cells keep their cached values but
    /// silently become static numbers.
    private static func formula(
        from element: XMLElement, at address: CellAddress, shared: inout [String: SharedFormula]
    ) -> String? {
        let text = element.text
        guard element.attribute("t") == "shared", let index = element.attribute("si") else {
            return text.isEmpty ? nil : text
        }

        if !text.isEmpty {
            shared[index] = SharedFormula(text: text, origin: address)
            return text
        }
        guard let master = shared[index] else { return nil }
        return FormulaReferenceShifter.translated(
            master.text,
            rowDelta: address.row - master.origin.row,
            columnDelta: address.column - master.origin.column
        )
    }

    /// Days between the 1900 and 1904 epochs. Only date-formatted values are
    /// serials, so only they get shifted.
    private static let macEpochOffset = 1462.0

    private static func decodeValue(_ element: XMLElement, sharedStrings: [String]) -> CellValue {
        let type = element.attribute("t") ?? "n"
        switch type {
        case "s":
            guard let raw = element.firstChild(named: "v")?.text.trimmed, let index = Int(raw),
                  sharedStrings.indices.contains(index) else { return .empty }
            return .text(sharedStrings[index])
        case "inlineStr":
            guard let inline = element.firstChild(named: "is") else { return .empty }
            if let direct = inline.firstChild(named: "t") { return .text(direct.text) }
            let runs = inline.children(named: "r").compactMap { $0.firstChild(named: "t")?.text }
            return .text(runs.joined())
        case "str":
            return .text(element.firstChild(named: "v")?.text ?? "")
        case "b":
            return .boolean((element.firstChild(named: "v")?.text.trimmed ?? "0") == "1")
        case "e":
            let raw = element.firstChild(named: "v")?.text.trimmed ?? ""
            return .error(CellError(rawValue: raw) ?? .valueError)
        case "d":
            guard let text = element.firstChild(named: "v")?.text.trimmed,
                  let date = ISO8601DateFormatter().date(from: text) else { return .empty }
            return .number(CellFormatter.serial(fromDate: date))
        default:
            guard let text = element.firstChild(named: "v")?.text.trimmed, !text.isEmpty else { return .empty }
            guard let number = Double(text) else { return .text(text) }
            return .number(number)
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
