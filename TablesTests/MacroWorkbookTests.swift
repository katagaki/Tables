import Foundation
import Testing
@testable import Tables

/// What a workbook with macros needs from a save beyond its cells: the names
/// that bind its modules to its sheets.
@Suite("Macro workbooks")
struct MacroWorkbookTests {
    @Test("Code names survive a save, and a duplicated sheet does not inherit one")
    func codeNames() throws {
        var sheet = Worksheet(name: "Data")
        sheet.codeName = "shtData"
        var workbook = Workbook(sheets: [sheet])
        workbook.codeName = "ThisWorkbook"

        let reloaded = try XLSXReader.workbook(from: XLSXWriter.data(from: workbook))
        #expect(reloaded.codeName == "ThisWorkbook")
        #expect(reloaded.sheets[0].codeName == "shtData")

        var copied = reloaded
        let duplicated = copied.duplicateSheet(copied.sheets[0].id)
        let copyID = try #require(duplicated)
        #expect(copied.sheets[copied.index(of: copyID)!].codeName == nil)
    }
}
