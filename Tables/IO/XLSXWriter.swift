import Foundation

/// Serializes the app's model back into an Office Open XML workbook.
enum XLSXWriter {
    static func data(from workbook: Workbook) throws -> Data {
        let strings = SharedStringTable(workbook: workbook)
        let styles = StyleTable(workbook: workbook)
        let preserved = workbook.preservedPackage

        var parts: [(path: String, data: Data)] = [
            (
                "[Content_Types].xml",
                contentTypes(sheetCount: workbook.sheets.count, preserved: preserved).utf8Data
            ),
            ("_rels/.rels", rootRelationships(preserved: preserved).utf8Data),
            ("xl/workbook.xml", workbookPart(workbook).utf8Data),
            (
                "xl/_rels/workbook.xml.rels",
                workbookRelationships(sheetCount: workbook.sheets.count, preserved: preserved).utf8Data
            ),
            ("xl/styles.xml", styles.xml.utf8Data),
            ("xl/sharedStrings.xml", strings.xml.utf8Data),
        ]
        for (index, sheet) in workbook.sheets.enumerated() {
            let relationships = preserved.sheetRelationshipParts[sheet.id]
            parts.append((
                "xl/worksheets/sheet\(index + 1).xml",
                sheetPart(
                    sheet, strings: strings, styles: styles, hasRelationshipsPart: relationships != nil
                ).utf8Data
            ))
            // A sheet's `_rels` follows it to its new position: the file names
            // change when sheets are reordered, the contents do not.
            if let relationships {
                parts.append(("xl/worksheets/_rels/sheet\(index + 1).xml.rels", relationships))
            }
        }
        for path in preserved.parts.keys.sorted() {
            parts.append((path, preserved.parts[path] ?? Data()))
        }
        return try ZipArchive.archive(entries: parts)
    }

    private static let declaration = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    private static let mainNamespace = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    private static let relationshipNamespace = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    // MARK: - Package parts

    private static func contentTypes(sheetCount: Int, preserved: PreservedPackage) -> String {
        var xml = declaration
        xml += "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        xml += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        xml += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        // The two extensions above are already stated; restating either would
        // make the part invalid rather than merely redundant.
        for (ext, type) in preserved.contentTypeDefaults.sorted(by: { $0.key < $1.key })
        where ext != "rels" && ext != "xml" {
            xml += "<Default Extension=\"\(XMLLite.escape(ext))\" ContentType=\"\(XMLLite.escape(type))\"/>"
        }
        xml += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        for index in 1...max(1, sheetCount) {
            xml += "<Override PartName=\"/xl/worksheets/sheet\(index).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        xml += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        xml += "<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/>"
        for (name, type) in preserved.contentTypeOverrides.sorted(by: { $0.key < $1.key })
        where !generatedPartNames.contains(name) {
            xml += "<Override PartName=\"\(XMLLite.escape(name))\" ContentType=\"\(XMLLite.escape(type))\"/>"
        }
        xml += "</Types>"
        return xml
    }

    /// Part names we always write an override for ourselves, so a preserved
    /// one naming the same part is skipped rather than duplicated.
    private static let generatedPartNames: Set<String> = [
        "/xl/workbook.xml", "/xl/styles.xml", "/xl/sharedStrings.xml",
    ]

    private static func rootRelationships(preserved: PreservedPackage) -> String {
        var xml = declaration
        xml += "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        xml += "<Relationship Id=\"rId1\" Type=\"\(relationshipNamespace)/officeDocument\" Target=\"xl/workbook.xml\"/>"
        xml += relationshipEntries(preserved.rootRelationships, startingAt: 2)
        xml += "</Relationships>"
        return xml
    }

    private static func workbookRelationships(sheetCount: Int, preserved: PreservedPackage) -> String {
        var xml = declaration
        xml += "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for index in 1...max(1, sheetCount) {
            xml += "<Relationship Id=\"rId\(index)\" Type=\"\(relationshipNamespace)/worksheet\" Target=\"worksheets/sheet\(index).xml\"/>"
        }
        xml += "<Relationship Id=\"rId\(sheetCount + 1)\" Type=\"\(relationshipNamespace)/styles\" Target=\"styles.xml\"/>"
        xml += "<Relationship Id=\"rId\(sheetCount + 2)\" Type=\"\(relationshipNamespace)/sharedStrings\" Target=\"sharedStrings.xml\"/>"
        xml += relationshipEntries(preserved.workbookRelationships, startingAt: sheetCount + 3)
        xml += "</Relationships>"
        return xml
    }

    /// Re-emits carried-over relationships under fresh ids.
    ///
    /// Renumbering is safe here and only here: nothing in the parts we generate
    /// names these ids, because the parts they reach — the theme, the document
    /// properties — are found by relationship type instead.
    private static func relationshipEntries(
        _ relationships: [PreservedRelationship], startingAt firstID: Int
    ) -> String {
        var xml = ""
        for (offset, relationship) in relationships.enumerated() {
            xml += "<Relationship Id=\"rId\(firstID + offset)\""
            xml += " Type=\"\(XMLLite.escape(relationship.type))\""
            xml += " Target=\"\(XMLLite.escape(relationship.target))\""
            if let mode = relationship.targetMode { xml += " TargetMode=\"\(XMLLite.escape(mode))\"" }
            xml += "/>"
        }
        return xml
    }

    private static func workbookPart(_ workbook: Workbook) -> String {
        var xml = declaration
        xml += "<workbook xmlns=\"\(mainNamespace)\" xmlns:r=\"\(relationshipNamespace)\"><sheets>"
        let hasVisibleSheet = workbook.sheets.contains { !$0.isHidden }
        for (index, sheet) in workbook.sheets.enumerated() {
            xml += "<sheet name=\"\(XMLLite.escape(sheet.name))\" sheetId=\"\(index + 1)\""
            // Excel refuses to open a workbook with nothing visible, so the
            // first sheet stays visible however the model got into that state.
            if sheet.isHidden, hasVisibleSheet || index > 0 { xml += " state=\"hidden\"" }
            xml += " r:id=\"rId\(index + 1)\"/>"
        }
        xml += "</sheets>"
        // Element order inside `<workbook>` is schema-enforced: `<definedNames>`
        // sits between `<sheets>` and `<calcPr>`, and Excel rejects the part if
        // it appears anywhere else.
        // A name scoped to a sheet that is gone is dropped rather than written
        // unscoped: promoting it to workbook scope would let it answer formulas
        // it never applied to.
        let names = workbook.definedNames.compactMap { name -> (DefinedName, Int?)? in
            guard let scope = name.scope else { return (name, nil) }
            guard let position = workbook.index(of: scope) else { return nil }
            return (name, position)
        }
        if !names.isEmpty {
            xml += "<definedNames>"
            for (name, position) in names {
                xml += "<definedName name=\"\(XMLLite.escape(name.name))\""
                if let position { xml += " localSheetId=\"\(position)\"" }
                xml += ">\(XMLLite.escape(name.formula))</definedName>"
            }
            xml += "</definedNames>"
        }
        // Ask Excel to recalculate on open: we store our own cached results, and
        // where a function differs in the last digit its answer should win.
        xml += "<calcPr calcId=\"0\" fullCalcOnLoad=\"1\"/>"
        xml += "</workbook>"
        return xml
    }

    // MARK: - Worksheets

    /// The order `CT_Worksheet` fixes for the children of `<worksheet>`, from
    /// ECMA-376 Part 1 §18.3.1.99. Excel refuses to open a worksheet whose
    /// children appear in any other order, so every fragment we write — ours
    /// and the ones carried over from the file — is placed by this list.
    private static let worksheetChildOrder: [String] = [
        "sheetPr", "dimension", "sheetViews", "sheetFormatPr", "cols", "sheetData",
        "sheetCalcPr", "sheetProtection", "protectedRanges", "scenarios", "autoFilter",
        "sortState", "dataConsolidate", "customSheetViews", "mergeCells", "phoneticPr",
        "conditionalFormatting", "dataValidations", "hyperlinks", "printOptions",
        "pageMargins", "pageSetup", "headerFooter", "rowBreaks", "colBreaks",
        "customProperties", "cellWatches", "ignoredErrors", "smartTags", "drawing",
        "legacyDrawing", "legacyDrawingHF", "picture", "oleObjects", "controls",
        "webPublishItems", "tableParts", "extLst",
    ]

    private static func sheetPart(
        _ sheet: Worksheet, strings: SharedStringTable, styles: StyleTable,
        hasRelationshipsPart: Bool
    ) -> String {
        /// Fragments paired with their schema position, plus the order they
        /// were added in so repeatable children — several `<conditionalFormatting>`
        /// blocks, say — keep the sequence the file had them in.
        var fragments: [(order: Int, sequence: Int, xml: String)] = []
        func add(_ name: String, _ body: String) {
            let order = worksheetChildOrder.firstIndex(of: name) ?? worksheetChildOrder.count
            fragments.append((order, fragments.count, body))
        }

        add("dimension", "<dimension ref=\"A1:\(CellAddress(row: sheet.rowCount - 1, column: sheet.columnCount - 1).a1)\"/>")

        // Our defaults differ from Excel's, so state them: otherwise every row
        // and column we did not size explicitly would render at Excel's size.
        var xml = "<sheetFormatPr defaultRowHeight=\"\(format(Worksheet.defaultRowHeight))\""
        xml += " defaultColWidth=\"\(format(Worksheet.columnWidthCharacters(points: Worksheet.defaultColumnWidth)))\"/>"
        add("sheetFormatPr", xml)

        // Column metadata: widths and hidden state.
        var columnEntries: [String] = []
        for column in 0..<sheet.columnCount {
            let hidden = sheet.hiddenColumns.contains(column)
            let custom = sheet.columnWidths[column]
            guard hidden || custom != nil else { continue }
            let points = custom ?? Worksheet.defaultColumnWidth
            let characters = max(0, Worksheet.columnWidthCharacters(points: points))
            var entry = "<col min=\"\(column + 1)\" max=\"\(column + 1)\" width=\"\(format(characters))\""
            if custom != nil { entry += " customWidth=\"1\"" }
            if hidden { entry += " hidden=\"1\"" }
            entry += "/>"
            columnEntries.append(entry)
        }
        if !columnEntries.isEmpty { add("cols", "<cols>" + columnEntries.joined() + "</cols>") }

        xml = "<sheetData>"
        let populatedRows = Set(sheet.cells.keys.map(\.row))
        let interestingRows = populatedRows
            .union(sheet.hiddenRows)
            .union(sheet.rowHeights.keys)
            .filter { $0 < sheet.rowCount }
            .sorted()

        for row in interestingRows {
            var attributes = "r=\"\(row + 1)\""
            if let height = sheet.rowHeights[row] {
                attributes += " ht=\"\(format(height))\" customHeight=\"1\""
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
        xml += "</sheetData>"
        add("sheetData", xml)

        var merges: [CellRange] = []
        for range in sheet.mergedRanges {
            let box: CellRange = range.normalized
            guard box.end.row < sheet.rowCount, box.end.column < sheet.columnCount else { continue }
            merges.append(box)
        }
        merges.sort { first, second in
            first.start == second.start ? first.end < second.end : first.start < second.start
        }
        if !merges.isEmpty {
            xml = "<mergeCells count=\"\(merges.count)\">"
            for merge in merges { xml += "<mergeCell ref=\"\(merge.a1)\"/>" }
            xml += "</mergeCells>"
            add("mergeCells", xml)
        }

        for element in sheet.preservedElements {
            // A duplicated sheet carries its predecessor's fragments but not
            // its `_rels`, so the ids in them would resolve to nothing.
            guard hasRelationshipsPart || !element.needsSheetRelationships else { continue }
            add(element.name, element.xml)
        }

        // Sorting rather than appending in place is what keeps the carried-over
        // fragments in their schema slots instead of wherever we happened to
        // reach them.
        fragments.sort { $0.order == $1.order ? $0.sequence < $1.sequence : $0.order < $1.order }
        return declaration
            + "<worksheet xmlns=\"\(mainNamespace)\">"
            + fragments.map(\.xml).joined()
            + "</worksheet>"
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
        /// Stand-in for a side whose source file named no colour.
        private let defaultBorderColorHex = "FF8E8E93"

        private var styles: [CellStyle] = [.default]
        private var lookup: [CellStyle: Int] = [.default: 0]
        /// Carried-over children of the original `<styleSheet>`.
        private let preservedElements: [PreservedElement]

        /// The order `CT_Stylesheet` fixes for the children we re-emit, from
        /// ECMA-376 Part 1 §18.8.39. They all follow `<cellStyles>`, which is
        /// the last one we generate ourselves.
        private static let trailingElementOrder = ["dxfs", "tableStyles", "colors", "extLst"]

        init(workbook: Workbook) {
            preservedElements = workbook.preservedPackage.styleSheetElements
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
                let diagonal = style.diagonalBorder.flatMap { $0.isVisible ? $0 : nil }
                xml += "<border"
                if diagonal?.goesUp == true { xml += " diagonalUp=\"1\"" }
                if diagonal?.goesDown == true { xml += " diagonalDown=\"1\"" }
                xml += ">"
                // Excel requires the sides in schema order, not the order we
                // happen to iterate a dictionary in.
                for edge in [BorderEdge.leading, .trailing, .top, .bottom] {
                    guard let side = style.borderSides[edge] else {
                        xml += "<\(edge.ooxmlTag)/>"
                        continue
                    }
                    xml += "<\(edge.ooxmlTag) style=\"\(side.lineStyle.rawValue)\">"
                    xml += "<color rgb=\"\(side.colorHex ?? defaultBorderColorHex)\"/>"
                    xml += "</\(edge.ooxmlTag)>"
                }
                if let diagonal {
                    xml += "<diagonal style=\"\(diagonal.lineStyle.rawValue)\">"
                    xml += "<color rgb=\"\(diagonal.colorHex ?? defaultBorderColorHex)\"/>"
                    xml += "</diagonal>"
                } else {
                    xml += "<diagonal/>"
                }
                xml += "</border>"
            }
            xml += "</borders>"

            xml += "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
            xml += "<cellXfs count=\"\(styles.count)\">"
            for (index, style) in styles.enumerated() {
                let formatID = style.numberFormat == "General" ? 0 : (formats[style.numberFormat] ?? 0)
                let fillID = style.fillColorHex == nil ? 0 : index + 2
                let hasBorder = !style.borderSides.isEmpty || style.diagonalBorder?.isVisible == true
                let borderID = hasBorder ? index + 1 : 0
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
                if style.indent > 0 { xml += " indent=\"\(style.indent)\"" }
                if style.textRotation != 0 { xml += " textRotation=\"\(style.textRotation)\"" }
                xml += "/></xf>"
            }
            xml += "</cellXfs>"
            xml += "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>"
            for element in preservedElements.sorted(by: {
                (Self.trailingElementOrder.firstIndex(of: $0.name) ?? Self.trailingElementOrder.count)
                    < (Self.trailingElementOrder.firstIndex(of: $1.name) ?? Self.trailingElementOrder.count)
            }) {
                xml += element.xml
            }
            xml += "</styleSheet>"
            return xml
        }
    }
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}
