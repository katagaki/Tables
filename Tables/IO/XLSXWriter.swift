import Foundation

/// Serializes the app's model back into an Office Open XML workbook.
enum XLSXWriter {
    static func data(from workbook: Workbook) throws -> Data {
        let strings = SharedStringTable(workbook: workbook)
        let styles = StyleTable(workbook: workbook)

        var parts: [(path: String, data: Data)] = [
            ("[Content_Types].xml", contentTypes(sheetCount: workbook.sheets.count).utf8Data),
            ("_rels/.rels", rootRelationships.utf8Data),
            ("xl/workbook.xml", workbookPart(workbook).utf8Data),
            ("xl/_rels/workbook.xml.rels", workbookRelationships(sheetCount: workbook.sheets.count).utf8Data),
            ("xl/styles.xml", styles.xml.utf8Data),
            ("xl/sharedStrings.xml", strings.xml.utf8Data),
        ]
        for (index, sheet) in workbook.sheets.enumerated() {
            parts.append((
                "xl/worksheets/sheet\(index + 1).xml",
                sheetPart(sheet, strings: strings, styles: styles).utf8Data
            ))
        }
        return try ZipArchive.archive(entries: parts)
    }

    private static let declaration = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    private static let mainNamespace = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    private static let relationshipNamespace = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    // MARK: - Package parts

    private static func contentTypes(sheetCount: Int) -> String {
        var xml = declaration
        xml += "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        xml += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        xml += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        xml += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        for index in 1...max(1, sheetCount) {
            xml += "<Override PartName=\"/xl/worksheets/sheet\(index).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        xml += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        xml += "<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/>"
        xml += "</Types>"
        return xml
    }

    private static var rootRelationships: String {
        declaration
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"\(relationshipNamespace)/officeDocument\" Target=\"xl/workbook.xml\"/>"
            + "</Relationships>"
    }

    private static func workbookRelationships(sheetCount: Int) -> String {
        var xml = declaration
        xml += "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for index in 1...max(1, sheetCount) {
            xml += "<Relationship Id=\"rId\(index)\" Type=\"\(relationshipNamespace)/worksheet\" Target=\"worksheets/sheet\(index).xml\"/>"
        }
        xml += "<Relationship Id=\"rId\(sheetCount + 1)\" Type=\"\(relationshipNamespace)/styles\" Target=\"styles.xml\"/>"
        xml += "<Relationship Id=\"rId\(sheetCount + 2)\" Type=\"\(relationshipNamespace)/sharedStrings\" Target=\"sharedStrings.xml\"/>"
        xml += "</Relationships>"
        return xml
    }

    private static func workbookPart(_ workbook: Workbook) -> String {
        var xml = declaration
        xml += "<workbook xmlns=\"\(mainNamespace)\" xmlns:r=\"\(relationshipNamespace)\"><sheets>"
        for (index, sheet) in workbook.sheets.enumerated() {
            xml += "<sheet name=\"\(XMLLite.escape(sheet.name))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
        }
        xml += "</sheets>"
        // Ask Excel to recalculate on open: we store our own cached results, and
        // where a function differs in the last digit its answer should win.
        xml += "<calcPr calcId=\"0\" fullCalcOnLoad=\"1\"/>"
        xml += "</workbook>"
        return xml
    }

    // MARK: - Worksheets

    private static func sheetPart(_ sheet: Worksheet, strings: SharedStringTable, styles: StyleTable) -> String {
        var xml = declaration
        xml += "<worksheet xmlns=\"\(mainNamespace)\">"
        xml += "<dimension ref=\"A1:\(CellAddress(row: sheet.rowCount - 1, column: sheet.columnCount - 1).a1)\"/>"

        // Column metadata: widths and hidden state.
        var columnEntries: [String] = []
        for column in 0..<sheet.columnCount {
            let hidden = sheet.hiddenColumns.contains(column)
            let custom = sheet.columnWidths[column]
            guard hidden || custom != nil else { continue }
            let points = custom ?? Worksheet.defaultColumnWidth
            let characters = max(1, (points - 5) / 7)
            var entry = "<col min=\"\(column + 1)\" max=\"\(column + 1)\" width=\"\(format(characters))\""
            if custom != nil { entry += " customWidth=\"1\"" }
            if hidden { entry += " hidden=\"1\"" }
            entry += "/>"
            columnEntries.append(entry)
        }
        if !columnEntries.isEmpty { xml += "<cols>" + columnEntries.joined() + "</cols>" }

        xml += "<sheetData>"
        let populatedRows = Set(sheet.cells.keys.map(\.row))
        let interestingRows = populatedRows
            .union(sheet.hiddenRows)
            .union(sheet.rowHeights.keys)
            .filter { $0 < sheet.rowCount }
            .sorted()

        for row in interestingRows {
            var attributes = "r=\"\(row + 1)\""
            if let height = sheet.rowHeights[row] {
                attributes += " ht=\"\(format(height / 1.35))\" customHeight=\"1\""
            }
            if sheet.hiddenRows.contains(row) { attributes += " hidden=\"1\"" }

            let cells = sheet.cells
                .filter { $0.key.row == row && $0.key.column < sheet.columnCount }
                .sorted { $0.key.column < $1.key.column }
            guard !cells.isEmpty else {
                xml += "<row \(attributes)/>"
                continue
            }
            xml += "<row \(attributes)>"
            for (address, cell) in cells {
                xml += cellPart(cell, at: address, strings: strings, styles: styles)
            }
            xml += "</row>"
        }
        xml += "</sheetData></worksheet>"
        return xml
    }

    private static func cellPart(
        _ cell: Cell, at address: CellAddress, strings: SharedStringTable, styles: StyleTable
    ) -> String {
        var attributes = "r=\"\(address.a1)\""
        let styleIndex = styles.index(for: cell.style)
        if styleIndex != 0 { attributes += " s=\"\(styleIndex)\"" }

        var body = ""
        if let formula = cell.formula {
            body += "<f>\(XMLLite.escape(formula))</f>"
        }

        switch cell.value {
        case .empty:
            break
        case .number(let number):
            body += "<v>\(format(number))</v>"
        case .boolean(let flag):
            attributes += " t=\"b\""
            body += "<v>\(flag ? 1 : 0)</v>"
        case .error(let error):
            attributes += " t=\"e\""
            body += "<v>\(XMLLite.escape(error.ooxmlValue))</v>"
        case .text(let text):
            if cell.formula != nil {
                attributes += " t=\"str\""
                body += "<v>\(XMLLite.escape(text))</v>"
            } else {
                attributes += " t=\"s\""
                body += "<v>\(strings.index(for: text))</v>"
            }
        }

        return body.isEmpty ? "<c \(attributes)/>" : "<c \(attributes)>\(body)</c>"
    }

    /// Round-trip-safe number rendering: full precision, no separators.
    private static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%.15g", value)
    }

    // MARK: - Shared strings

    final class SharedStringTable {
        private(set) var strings: [String] = []
        private var lookup: [String: Int] = [:]

        init(workbook: Workbook) {
            for sheet in workbook.sheets {
                for cell in sheet.cells.values {
                    guard cell.formula == nil, case .text(let text) = cell.value else { continue }
                    _ = index(for: text)
                }
            }
        }

        @discardableResult
        func index(for text: String) -> Int {
            if let existing = lookup[text] { return existing }
            let index = strings.count
            strings.append(text)
            lookup[text] = index
            return index
        }

        var xml: String {
            var xml = XLSXWriter.declaration
            xml += "<sst xmlns=\"\(XLSXWriter.mainNamespace)\" count=\"\(strings.count)\" uniqueCount=\"\(strings.count)\">"
            for text in strings {
                xml += "<si><t xml:space=\"preserve\">\(XMLLite.escape(text))</t></si>"
            }
            xml += "</sst>"
            return xml
        }
    }

    // MARK: - Styles

    final class StyleTable {
        private var styles: [CellStyle] = [.default]
        private var lookup: [CellStyle: Int] = [.default: 0]

        init(workbook: Workbook) {
            for sheet in workbook.sheets {
                for cell in sheet.cells.values where !cell.style.isDefault {
                    _ = index(for: cell.style)
                }
            }
        }

        @discardableResult
        func index(for style: CellStyle) -> Int {
            if let existing = lookup[style] { return existing }
            let index = styles.count
            styles.append(style)
            lookup[style] = index
            return index
        }

        /// Custom number format codes start at 164 by convention.
        private var customFormats: [String: Int] {
            var result: [String: Int] = [:]
            var nextID = 164
            for style in styles where style.numberFormat != "General" {
                guard result[style.numberFormat] == nil else { continue }
                result[style.numberFormat] = nextID
                nextID += 1
            }
            return result
        }

        var xml: String {
            let formats = customFormats
            var xml = XLSXWriter.declaration
            xml += "<styleSheet xmlns=\"\(XLSXWriter.mainNamespace)\">"

            if !formats.isEmpty {
                xml += "<numFmts count=\"\(formats.count)\">"
                for (code, id) in formats.sorted(by: { $0.value < $1.value }) {
                    xml += "<numFmt numFmtId=\"\(id)\" formatCode=\"\(XMLLite.escape(code))\"/>"
                }
                xml += "</numFmts>"
            }

            xml += "<fonts count=\"\(styles.count)\">"
            for style in styles {
                xml += "<font><sz val=\"\(XLSXWriter.format(style.fontSize))\"/>"
                xml += "<name val=\"\(XMLLite.escape(style.fontName))\"/>"
                if style.isBold { xml += "<b/>" }
                if style.isItalic { xml += "<i/>" }
                if style.isUnderlined { xml += "<u/>" }
                if style.isStruckThrough { xml += "<strike/>" }
                if let color = style.textColorHex { xml += "<color rgb=\"\(color)\"/>" }
                xml += "</font>"
            }
            xml += "</fonts>"

            // Indices 0 and 1 are reserved by the format for "none" and "gray125".
            xml += "<fills count=\"\(styles.count + 2)\">"
            xml += "<fill><patternFill patternType=\"none\"/></fill>"
            xml += "<fill><patternFill patternType=\"gray125\"/></fill>"
            for style in styles {
                if let color = style.fillColorHex {
                    xml += "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"\(color)\"/>"
                    xml += "<bgColor indexed=\"64\"/></patternFill></fill>"
                } else {
                    xml += "<fill><patternFill patternType=\"none\"/></fill>"
                }
            }
            xml += "</fills>"

            xml += "<borders count=\"\(styles.count + 1)\">"
            xml += "<border><left/><right/><top/><bottom/><diagonal/></border>"
            for style in styles {
                xml += "<border>"
                let sides: [(String, BorderEdges)] = [
                    ("left", .leading), ("right", .trailing), ("top", .top), ("bottom", .bottom),
                ]
                for (tag, edge) in sides {
                    if style.borders.contains(edge) {
                        xml += "<\(tag) style=\"thin\">"
                        xml += "<color rgb=\"\(style.borderColorHex ?? "FF8E8E93")\"/>"
                        xml += "</\(tag)>"
                    } else {
                        xml += "<\(tag)/>"
                    }
                }
                xml += "<diagonal/></border>"
            }
            xml += "</borders>"

            xml += "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
            xml += "<cellXfs count=\"\(styles.count)\">"
            for (index, style) in styles.enumerated() {
                let formatID = style.numberFormat == "General" ? 0 : (formats[style.numberFormat] ?? 0)
                let fillID = style.fillColorHex == nil ? 0 : index + 2
                let borderID = style.borders.isEmpty ? 0 : index + 1
                xml += "<xf numFmtId=\"\(formatID)\" fontId=\"\(index)\" fillId=\"\(fillID)\" borderId=\"\(borderID)\""
                xml += " xfId=\"0\" applyFont=\"1\" applyNumberFormat=\"1\" applyFill=\"1\" applyBorder=\"1\""
                xml += " applyAlignment=\"1\">"
                xml += "<alignment"
                switch style.horizontalAlignment {
                case .automatic: break
                case .leading: xml += " horizontal=\"left\""
                case .center: xml += " horizontal=\"center\""
                case .trailing: xml += " horizontal=\"right\""
                }
                switch style.verticalAlignment {
                case .top: xml += " vertical=\"top\""
                case .middle: xml += " vertical=\"center\""
                case .bottom: xml += " vertical=\"bottom\""
                }
                if style.wrapsText { xml += " wrapText=\"1\"" }
                xml += "/></xf>"
            }
            xml += "</cellXfs>"
            xml += "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>"
            xml += "</styleSheet>"
            return xml
        }
    }
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}
