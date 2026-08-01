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
        let styles = parseStyles(entries["xl/styles.xml"], theme: parseTheme(entries))
        let styleSheetElements = preservedStyleSheetElements(entries["xl/styles.xml"])
        let hasDifferentialFormats = styleSheetElements.contains { $0.name == "dxfs" }

        // Workbooks written on the classic Mac epoch count days from 1904.
        // Serials are normalized to the 1900 system on the way in so nothing
        // downstream has to know which system the file used.
        let usesMacEpoch = workbookXML.firstChild(named: "workbookPr")?.attribute("date1904") == "1"

        var sheets: [Worksheet] = []
        var sheetPaths: [String] = []
        /// Unmodelled worksheet children, per sheet, with the element they were
        /// found on. Whether each one survives is only known once the package as
        /// a whole has been worked out, so reporting waits until then.
        var sheetFindings: [[(feature: UnsupportedFeature, elementName: String)]] = []
        let sheetElements = workbookXML.firstChild(named: "sheets")?.children(named: "sheet") ?? []

        for (position, element) in sheetElements.enumerated() {
            let name = element.attribute("name") ?? Workbook.defaultSheetName(position + 1)
            let target = element.attribute("id").flatMap { relationships[$0] }
            let fallbackPath = "xl/worksheets/sheet\(position + 1).xml"
            let path = resolvePath(target) ?? fallbackPath
            // `veryHidden` only differs in whether Excel's own UI offers to
            // reveal it, which is a distinction we have no place to keep.
            let state = element.attribute("state")
            let isHidden = state == "hidden" || state == "veryHidden"

            guard let payload = entries[path] ?? entries[fallbackPath] else {
                var placeholder = Worksheet(name: name)
                placeholder.isHidden = isHidden
                sheets.append(placeholder)
                sheetPaths.append(path)
                sheetFindings.append([])
                continue
            }
            let sheetXML = try XMLLite.parse(payload)
            var sheet = parseSheet(
                sheetXML, name: name, sharedStrings: sharedStrings, styles: styles,
                usesMacEpoch: usesMacEpoch, hasDifferentialFormats: hasDifferentialFormats
            )
            sheet.name = name
            sheet.isHidden = isHidden
            sheets.append(sheet)
            sheetPaths.append(entries[path] != nil ? path : fallbackPath)
            sheetFindings.append(unsupportedFindings(in: sheetXML))
        }

        guard !sheets.isEmpty else { throw ReadError(message: "The workbook contains no sheets.") }
        // A file claiming every sheet is hidden is malformed — Excel requires
        // one visible — and honouring it would leave the tab strip empty.
        if sheets.allSatisfy(\.isHidden) { sheets[0].isHidden = false }
        var workbook = Workbook(sheets: sheets, definedNames: parseDefinedNames(workbookXML, sheets: sheets))

        var report = UnsupportedFeatureReport()
        var preserved = PackagePreservation.plan(
            entries: entries, sheets: workbook.sheets, sheetPaths: sheetPaths, report: &report
        )
        preserved.styleSheetElements = styleSheetElements
        for index in workbook.sheets.indices {
            // A sheet child naming a relationship id is only re-emittable while
            // the part that resolves those ids comes with it.
            if preserved.sheetRelationshipParts[workbook.sheets[index].id] == nil {
                workbook.sheets[index].preservedElements.removeAll(where: \.needsSheetRelationships)
            }
            let kept = Set(workbook.sheets[index].preservedElements.map(\.name))
            for finding in sheetFindings[index] {
                report.record(finding.feature, isPreserved: kept.contains(finding.elementName))
            }
        }
        workbook.preservedPackage = preserved
        workbook.unsupportedFeatures = report
        workbook.recalculate()
        return workbook
    }

    /// The unmodelled children of one worksheet that are worth telling the user
    /// about. `<pageMargins>` is left out deliberately: near every generator
    /// writes one, and naming it would make the notice appear for files that
    /// have nothing a user would recognise as a lost feature.
    private static func unsupportedFindings(
        in root: XMLElement
    ) -> [(feature: UnsupportedFeature, elementName: String)] {
        var findings: [(feature: UnsupportedFeature, elementName: String)] = []
        for child in root.children {
            let feature: UnsupportedFeature?
            switch child.name {
            case "conditionalFormatting": feature = .conditionalFormatting
            case "dataValidations": feature = .dataValidation
            case "autoFilter": feature = .autoFilter
            case "sheetProtection": feature = .sheetProtection
            case "hyperlinks": feature = .hyperlinks
            case "tableParts": feature = .tables
            case "drawing": feature = .chartsAndImages
            case "printOptions", "pageSetup": feature = .printSetup
            case "sheetViews":
                // Without a pane split this is only where the cursor was left,
                // which nobody would call a feature.
                let isSplit = child.children(named: "sheetView").contains { $0.firstChild(named: "pane") != nil }
                feature = isSplit ? .frozenPanes : nil
            default:
                feature = nil
            }
            if let feature { findings.append((feature, child.name)) }
        }
        return findings
    }

    /// Excel's own entries share the `<definedNames>` list. Print areas and
    /// print titles stand on their own and describe intent we would otherwise
    /// destroy, so they survive a round trip untouched. The rest — chiefly
    /// `_xlnm._FilterDatabase` — describe parts we do not write, and handing
    /// one back would point Excel at an autofilter that is no longer in the
    /// file, which it reports as damage.
    private static let preservedBuiltInNames: Set<String> = ["_xlnm.print_area", "_xlnm.print_titles"]

    private static func parseDefinedNames(_ root: XMLElement, sheets: [Worksheet]) -> [DefinedName] {
        var result: [DefinedName] = []
        for element in root.firstChild(named: "definedNames")?.children(named: "definedName") ?? [] {
            guard let name = element.attribute("name")?.trimmed, !name.isEmpty else { continue }
            let formula = element.text.trimmed
            guard !formula.isEmpty else { continue }

            let lowered = name.lowercased()
            if lowered.hasPrefix(DefinedName.builtInPrefix), !preservedBuiltInNames.contains(lowered) { continue }

            var scope: Worksheet.ID?
            if let position = element.attribute("localSheetId").flatMap(Int.init) {
                // A scope pointing at a sheet we could not read is not a
                // workbook-scoped name: keeping it would let it shadow one.
                guard sheets.indices.contains(position) else { continue }
                scope = sheets[position].id
            }
            result.append(DefinedName(name: name, formula: formula, scope: scope))
        }
        return result
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

    /// Reads the workbook's colour scheme. The theme part is optional, and
    /// generators that omit it still mean the standard Office colours, so a
    /// missing or unreadable part falls back rather than losing every colour.
    private static func parseTheme(_ entries: [String: Data]) -> ThemeColorScheme {
        let payload = entries["xl/theme/theme1.xml"]
            ?? entries.first { $0.key.hasPrefix("xl/theme/") && $0.key.hasSuffix(".xml") }?.value
        guard let payload, let root = try? XMLLite.parse(payload) else { return .office }
        return ThemeColorScheme(themeXML: root)
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

    private static func parseStyles(_ data: Data?, theme: ThemeColorScheme) -> [CellStyle] {
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
            spec.colorHex = ThemeColorPalette.resolvedARGB(
                from: element.firstChild(named: "color"), theme: theme
            )
            return spec
        }

        let fills: [String?] = (root.firstChild(named: "fills")?.children(named: "fill") ?? []).map { element in
            guard let pattern = element.firstChild(named: "patternFill"),
                  pattern.attribute("patternType") != "none" else { return nil }
            return ThemeColorPalette.resolvedARGB(
                from: pattern.firstChild(named: "fgColor"), theme: theme
            )
        }

        struct BorderSpec {
            var sides: [BorderEdge: BorderSide] = [:]
            var diagonal: DiagonalBorder?
        }

        let borders: [BorderSpec] = (root.firstChild(named: "borders")?.children(named: "border") ?? [])
            .map { element in
                var spec = BorderSpec()
                for edge in BorderEdge.allCases {
                    guard let side = element.firstChild(named: edge.ooxmlTag),
                          let style = side.attribute("style"), style != "none" else { continue }
                    // An unrecognised token still means "there is a rule here",
                    // so an exotic style degrades to thin rather than vanishing.
                    spec.sides[edge] = BorderSide(
                        lineStyle: BorderLineStyle(rawValue: style) ?? .thin,
                        colorHex: ThemeColorPalette.resolvedARGB(
                            from: side.firstChild(named: "color"), theme: theme
                        )
                    )
                }

                // The directions live on <border>, the style on <diagonal>; a
                // file may carry one without the other and means nothing by it.
                let goesUp = element.attribute("diagonalUp") == "1"
                let goesDown = element.attribute("diagonalDown") == "1"
                if let diagonal = element.firstChild(named: "diagonal"),
                   let style = diagonal.attribute("style"), style != "none", goesUp || goesDown {
                    spec.diagonal = DiagonalBorder(
                        lineStyle: BorderLineStyle(rawValue: style) ?? .thin,
                        colorHex: ThemeColorPalette.resolvedARGB(
                            from: diagonal.firstChild(named: "color"), theme: theme
                        ),
                        goesUp: goesUp,
                        goesDown: goesDown
                    )
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
                style.borderSides = borders[borderIndex].sides
                style.diagonalBorder = borders[borderIndex].diagonal
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
                style.indent = alignment.attribute("indent").flatMap(Int.init).map { max(0, $0) } ?? 0
                if let rotation = alignment.attribute("textRotation").flatMap(Int.init),
                   rotation == CellStyle.stackedTextRotation || (0...180).contains(rotation) {
                    style.textRotation = rotation
                }
            }
            return style
        }
    }

    // MARK: - Sheet content

    private static func parseSheet(
        _ root: XMLElement, name: String, sharedStrings: [String], styles: [CellStyle],
        usesMacEpoch: Bool, hasDifferentialFormats: Bool
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
            let width = column.attribute("width").flatMap(Double.init)
                .map { Worksheet.columnWidthPoints(characters: $0) }
            for index in first...min(last, Worksheet.maximumColumnCount) {
                let zeroBased = index - 1
                if hidden { sheet.hiddenColumns.insert(zeroBased) }
                if let width, width > 0, column.attribute("customWidth") == "1" {
                    sheet.columnWidths[zeroBased] = width
                }
            }
        }

        for rowElement in root.firstChild(named: "sheetData")?.children(named: "row") ?? [] {
            guard let rowNumber = rowElement.attribute("r").flatMap(Int.init), rowNumber >= 1 else { continue }
            let rowIndex = rowNumber - 1
            maximumRow = max(maximumRow, rowNumber)

            if rowElement.attribute("hidden") == "1" { sheet.hiddenRows.insert(rowIndex) }
            // `ht` is already in points, the same unit as our geometry, and the
            // resize floor is an interaction limit that must not rewrite a file.
            if rowElement.attribute("customHeight") == "1",
               let height = rowElement.attribute("ht").flatMap(Double.init), height > 0 {
                sheet.rowHeights[rowIndex] = height
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

        // A merged region can reach past the last populated cell, and the grid
        // has to be big enough to hold it, so these are read before the extents
        // are fixed.
        var merges: [CellRange] = []
        for element in root.firstChild(named: "mergeCells")?.children(named: "mergeCell") ?? [] {
            guard let reference = element.attribute("ref"),
                  let range = CellRange(a1Range: reference)?.normalized,
                  !range.isSingleCell else { continue }
            maximumRow = max(maximumRow, range.end.row + 1)
            maximumColumn = max(maximumColumn, range.end.column + 1)
            merges.append(range)
        }

        sheet.rowCount = max(Worksheet.defaultRowCount, min(maximumRow, Worksheet.maximumRowCount))
        sheet.columnCount = max(Worksheet.defaultColumnCount, min(maximumColumn, Worksheet.maximumColumnCount))
        sheet.hiddenRows = sheet.hiddenRows.filter { $0 < sheet.rowCount }
        sheet.hiddenColumns = sheet.hiddenColumns.filter { $0 < sheet.columnCount }
        // `merge` rejects anything that would overlap what is already there, so
        // a file with contradictory regions loses the later ones rather than
        // becoming a sheet we cannot draw.
        for range in merges { sheet.merge(range) }
        sheet.preservedElements = preservedChildren(
            of: root, hasDifferentialFormats: hasDifferentialFormats
        )
        return sheet
    }

    /// Worksheet children we neither read nor write, but keep verbatim.
    ///
    /// `<drawing>` is here even though nothing in the app draws one: without
    /// it, a chart or image part we carried through the package would sit in
    /// the file with no sheet pointing at it.
    private static let preservedWorksheetChildNames: Set<String> = [
        "sheetViews", "sheetProtection", "autoFilter", "conditionalFormatting",
        "dataValidations", "hyperlinks", "printOptions", "pageMargins", "pageSetup",
        "drawing", "legacyDrawing", "tableParts",
    ]

    private static func preservedChildren(
        of root: XMLElement, hasDifferentialFormats: Bool
    ) -> [PreservedElement] {
        root.children.compactMap { child in
            guard preservedWorksheetChildNames.contains(child.name) else { return nil }
            // A rule styled by a differential format indexes into the `<dxfs>`
            // table; without that table the index points at nothing.
            if child.name == "conditionalFormatting", !hasDifferentialFormats,
               child.children(named: "cfRule").contains(where: { $0.attribute("dxfId") != nil }) {
                return nil
            }
            guard let xml = XMLLite.serialize(child) else { return nil }
            return PreservedElement(name: child.name, xml: xml)
        }
    }

    /// Children of `<styleSheet>` we neither read nor write, but keep so that
    /// the things indexing into them stay meaningful. `<dxfs>` is the reason
    /// this exists; `<tableStyles>` and `<colors>` are the same argument for
    /// tables and for a workbook that redefined the indexed palette.
    private static let preservedStyleSheetChildNames: Set<String> = ["dxfs", "tableStyles", "colors"]

    private static func preservedStyleSheetElements(_ data: Data?) -> [PreservedElement] {
        guard let data, let root = try? XMLLite.parse(data) else { return [] }
        return root.children.compactMap { child in
            guard preservedStyleSheetChildNames.contains(child.name),
                  let xml = XMLLite.serialize(child) else { return nil }
            return PreservedElement(name: child.name, xml: xml)
        }
    }

    // MARK: - Package preservation

    /// Works out which parts of an opened package survive a save.
    ///
    /// The rule is all-or-nothing, per part: a part is kept only when every
    /// part it reaches through its own relationships is either kept too or
    /// regenerated by us, when the package declares a content type for it, and
    /// when a relationship we still write points at it. Anything failing any of
    /// those is dropped whole and reported as lost — a reference into a part
    /// that is no longer in the file is exactly what makes Excel declare the
    /// workbook damaged and offer to repair it.
    enum PackagePreservation {
        /// Part families the writer never generates and can therefore carry
        /// through untouched.
        ///
        /// `xl/comments` has no trailing slash on purpose: Excel writes
        /// `xl/comments1.xml` while other generators write `xl/comments/…`.
        static let preservablePathPrefixes = [
            "xl/theme/", "xl/comments", "xl/drawings/", "xl/tables/",
            "xl/charts/", "xl/media/", "xl/printerSettings/", "docProps/",
        ]

        /// PivotTables are excluded even though their parts are self-contained,
        /// because what binds a pivot cache to the workbook is the `<pivotCaches>`
        /// element of `xl/workbook.xml` — a part we regenerate from our own
        /// model and cannot reproduce. Keeping the parts without it leaves the
        /// tables pointing at a cache the workbook no longer declares.
        static let pivotPathPrefixes = ["xl/pivotCache", "xl/pivotTables"]

        static func plan(
            entries: [String: Data], sheets: [Worksheet], sheetPaths: [String],
            report: inout UnsupportedFeatureReport
        ) -> PreservedPackage {
            let types = contentTypes(entries["[Content_Types].xml"])

            var generated: Set<String> = [
                "[Content_Types].xml", "_rels/.rels", "xl/workbook.xml",
                "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/sharedStrings.xml",
            ]
            for index in sheets.indices { generated.insert("xl/worksheets/sheet\(index + 1).xml") }

            // Candidates have to be typeable before dependencies are weighed:
            // an untypeable part is already lost, and pretending otherwise
            // would let something else be kept on the strength of it.
            let candidates = entries.keys.filter { path in
                guard preservablePathPrefixes.contains(where: path.hasPrefix) else { return false }
                guard !isRelationshipsPart(path) else { return false }
                return types.declaresType(for: path)
            }

            // Dropping one part can strand another that pointed at it, so the
            // sweep repeats until nothing more falls away.
            var retained = Set(candidates)
            var settled = false
            while !settled {
                let survivors = retained.filter { path in
                    dependencies(of: path, in: entries).allSatisfy {
                        retained.contains($0) || generated.contains($0)
                    }
                }
                settled = survivors.count == retained.count
                retained = survivors
            }

            // A sheet's `_rels` is emitted whole, so it is kept only when every
            // target in it is: rewriting it to skip one would strand whichever
            // worksheet child names that id.
            var sheetRelationshipParts: [Worksheet.ID: Data] = [:]
            for (index, sheet) in sheets.enumerated() {
                let path = relationshipsPath(for: sheetPaths[index])
                guard let payload = entries[path] else { continue }
                let targets = relationships(in: payload).compactMap {
                    packagePath(of: $0, relativeTo: directory(of: sheetPaths[index]))
                }
                guard targets.allSatisfy({ retained.contains($0) || generated.contains($0) }) else { continue }
                sheetRelationshipParts[sheet.id] = payload
            }

            let rootEntries = relationships(in: entries["_rels/.rels"])
            let workbookEntries = relationships(in: entries["xl/_rels/workbook.xml.rels"])
            var roots: [String] = []
            roots += rootEntries.compactMap { packagePath(of: $0, relativeTo: "") }
            roots += workbookEntries.compactMap { packagePath(of: $0, relativeTo: "xl") }
            for (index, sheet) in sheets.enumerated() where sheetRelationshipParts[sheet.id] != nil {
                roots += relationships(in: sheetRelationshipParts[sheet.id]).compactMap {
                    packagePath(of: $0, relativeTo: directory(of: sheetPaths[index]))
                }
            }
            retained.formIntersection(reachable(from: roots, within: retained, entries: entries))

            var package = PreservedPackage()
            package.sheetRelationshipParts = sheetRelationshipParts
            for path in retained {
                package.parts[path] = entries[path]
                types.apply(to: path, in: &package)
                // The relationships of a kept part come with it; they are how
                // anything it reaches stays reachable.
                let relationshipsPath = relationshipsPath(for: path)
                if let payload = entries[relationshipsPath] { package.parts[relationshipsPath] = payload }
            }
            package.rootRelationships = rootEntries
                .filter { packagePath(of: $0, relativeTo: "").map(retained.contains) == true }
                .map(\.preserved)
            package.workbookRelationships = workbookEntries
                .filter { packagePath(of: $0, relativeTo: "xl").map(retained.contains) == true }
                .map(\.preserved)

            recordPackageFeatures(entries: entries, retained: retained, report: &report)
            return package
        }

        /// Notes the package-level features found in the file. A family counts
        /// as preserved only when every one of its parts survived: a workbook
        /// with two comment parts and one kept is not one whose comments are safe.
        private static func recordPackageFeatures(
            entries: [String: Data], retained: Set<String>, report: inout UnsupportedFeatureReport
        ) {
            func note(_ feature: UnsupportedFeature, matching predicate: (String) -> Bool) {
                let found = entries.keys.filter { !isRelationshipsPart($0) && predicate($0) }
                guard !found.isEmpty else { return }
                report.record(feature, isPreserved: found.allSatisfy(retained.contains))
            }
            note(.comments) { $0.hasPrefix("xl/comments") }
            note(.tables) { $0.hasPrefix("xl/tables/") }
            note(.chartsAndImages) {
                $0.hasPrefix("xl/charts/") || $0.hasPrefix("xl/media/") || $0.hasPrefix("xl/drawings/drawing")
            }
            note(.pivotTables) { path in pivotPathPrefixes.contains(where: path.hasPrefix) }
            note(.documentProperties) { $0.hasPrefix("docProps/") }
        }

        // MARK: Package graph

        private static func reachable(
            from roots: [String], within retained: Set<String>, entries: [String: Data]
        ) -> Set<String> {
            var seen: Set<String> = []
            var queue = roots.filter(retained.contains)
            while let path = queue.popLast() {
                guard seen.insert(path).inserted else { continue }
                queue += dependencies(of: path, in: entries).filter { retained.contains($0) }
            }
            return seen
        }

        private static func dependencies(of path: String, in entries: [String: Data]) -> [String] {
            relationships(in: entries[relationshipsPath(for: path)])
                .compactMap { packagePath(of: $0, relativeTo: directory(of: path)) }
        }

        /// One `<Relationship>` as the file wrote it, id included: ids matter
        /// inside a sheet's own `_rels`, which we re-emit unchanged.
        struct RelationshipEntry {
            var type: String
            var target: String
            var targetMode: String?

            var preserved: PreservedRelationship {
                PreservedRelationship(type: type, target: target, targetMode: targetMode)
            }
        }

        static func relationships(in data: Data?) -> [RelationshipEntry] {
            guard let data, let root = try? XMLLite.parse(data) else { return [] }
            return root.children(named: "Relationship").compactMap { element in
                guard let type = element.attribute("Type"),
                      let target = element.attribute("Target") else { return nil }
                return RelationshipEntry(
                    type: type, target: target, targetMode: element.attribute("TargetMode")
                )
            }
        }

        /// Where a relationship lands inside the package, or `nil` when it
        /// points outside it — an external hyperlink has no part to keep.
        static func packagePath(of entry: RelationshipEntry, relativeTo directory: String) -> String? {
            guard entry.targetMode != "External" else { return nil }
            return absolutePath(entry.target, relativeTo: directory)
        }

        static func absolutePath(_ target: String, relativeTo directory: String) -> String {
            if target.hasPrefix("/") { return String(target.dropFirst()) }
            var components = directory.split(separator: "/").map(String.init)
            for step in target.split(separator: "/") {
                switch step {
                case "..": if !components.isEmpty { components.removeLast() }
                case ".": break
                default: components.append(String(step))
                }
            }
            return components.joined(separator: "/")
        }

        static func directory(of path: String) -> String {
            guard let slash = path.lastIndex(of: "/") else { return "" }
            return String(path[path.startIndex..<slash])
        }

        static func relationshipsPath(for path: String) -> String {
            let folder = directory(of: path)
            let name = folder.isEmpty ? path : String(path.dropFirst(folder.count + 1))
            return folder.isEmpty ? "_rels/\(name).rels" : "\(folder)/_rels/\(name).rels"
        }

        static func isRelationshipsPart(_ path: String) -> Bool { path.hasSuffix(".rels") }

        // MARK: Content types

        /// The `[Content_Types].xml` of the file being read, which is the only
        /// place that says what a part we do not understand actually is.
        struct ContentTypes {
            var defaults: [String: String] = [:]
            var overrides: [String: String] = [:]

            func declaresType(for path: String) -> Bool {
                if overrides["/" + path] != nil { return true }
                let ext = fileExtension(of: path)
                // Every `.xml` part matches the generic default, which says
                // nothing useful; without an override we cannot type it.
                guard ext != "xml" else { return false }
                return defaults[ext] != nil
            }

            func apply(to path: String, in package: inout PreservedPackage) {
                if let override = overrides["/" + path] {
                    package.contentTypeOverrides["/" + path] = override
                    return
                }
                let ext = fileExtension(of: path)
                if let fallback = defaults[ext] { package.contentTypeDefaults[ext] = fallback }
            }

            private func fileExtension(of path: String) -> String {
                guard let dot = path.lastIndex(of: "."), dot > path.startIndex else { return "" }
                return String(path[path.index(after: dot)...]).lowercased()
            }
        }

        static func contentTypes(_ data: Data?) -> ContentTypes {
            var types = ContentTypes()
            guard let data, let root = try? XMLLite.parse(data) else { return types }
            for element in root.children(named: "Default") {
                guard let ext = element.attribute("Extension"),
                      let type = element.attribute("ContentType") else { continue }
                types.defaults[ext.lowercased()] = type
            }
            for element in root.children(named: "Override") {
                guard let name = element.attribute("PartName"),
                      let type = element.attribute("ContentType") else { continue }
                types.overrides[name] = type
            }
            return types
        }
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
