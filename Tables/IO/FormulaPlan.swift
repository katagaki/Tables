import Foundation

/// How each formula is stored: as an ordinary formula where Excel's old rules
/// give the same answer, and otherwise as an array formula, marked dynamic
/// when it spills rather than filling a fixed block.
struct FormulaPlan {
    enum Form {
        case plain(String)
        case array(String, block: CellRange, dynamic: Bool)
    }

    static let metadataPath = "xl/metadata.xml"
    static let metadataContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheetMetadata+xml"
    static let metadataRelationshipType = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/sheetMetadata"

    /// The metadata Excel writes to mark a formula as a dynamic array. Cells
    /// carrying `cm="1"` point at its one entry.
    static let metadataPart = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <metadata xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
        xmlns:xda="http://schemas.microsoft.com/office/spreadsheetml/2017/dynamicarray">\
        <metadataTypes count="1"><metadataType name="XLDAPR" minSupportedVersion="120000" copy="1" pasteAll="1" \
        pasteValues="1" merge="1" splitFirst="1" rowColShift="1" clearFormats="1" clearComments="1" assign="1" \
        coerce="1" cellMeta="1"/></metadataTypes>\
        <futureMetadata name="XLDAPR" count="1"><bk><extLst><ext uri="{bdbb8cdc-fa1e-496e-a857-3c3f30c029c3}">\
        <xda:dynamicArrayProperties fDynamic="1" fCollapsed="0"/></ext></extLst></bk></futureMetadata>\
        <cellMetadata count="1"><bk><rc t="1" v="0"/></bk></cellMetadata></metadata>
        """

    private(set) var forms: [Worksheet.ID: [CellAddress: Form]] = [:]
    private(set) var usesDynamicArrays = false

    init(workbook: Workbook) {
        let isRangeName = workbook.isRangeName
        for sheet in workbook.sheets {
            var sheetForms: [CellAddress: Form] = [:]
            for (address, cell) in sheet.cells {
                guard let formula = cell.formula else { continue }
                if let extent = cell.arrayExtent {
                    let block = CellRange(start: address, end: CellAddress(
                        row: address.row + extent.rows - 1, column: address.column + extent.columns - 1))
                    sheetForms[address] = .array(FormulaDialect.toFile(formula), block: block, dynamic: false)
                } else if let legacy = FormulaDialect.legacyForm(formula, isRangeName: isRangeName) {
                    sheetForms[address] = .plain(FormulaDialect.toFile(legacy))
                } else {
                    let block = sheet.spills[address] ?? CellRange(address)
                    sheetForms[address] = .array(FormulaDialect.toFile(formula), block: block, dynamic: true)
                    usesDynamicArrays = true
                }
            }
            forms[sheet.id] = sheetForms
        }
    }
}

extension Workbook {
    /// Whether a defined name stands for more than one cell, which decides
    /// where Excel's old rules intersected it down to one.
    var isRangeName: (String) -> Bool {
        let names = Set(definedNames.compactMap { name -> String? in
            switch try? FormulaParser.parse(name.formula) {
            case .range(_, let start, let end)? where start != end: return name.name.lowercased()
            case .sheetSpan?: return name.name.lowercased()
            default: return nil
            }
        })
        return { names.contains($0.lowercased()) }
    }
}
