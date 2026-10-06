import Foundation
import Testing
@testable import Tables

/// The help book makes promises; these hold the interpreter to them.
@Suite("Macro help")
struct MacroHelpTests {
    @Test("Every piece of prose in the book is in the string catalog")
    func prose() {
        var keys: [String] = ["Help.Title", "Help.Footer", "Help.Unavailable"]
        for topic in MacroHelp.topics {
            keys.append("Help.\(topic.id).Title")
            keys += topic.paragraphs
            for group in topic.groups {
                if !group.isCode { keys.append(group.title) }
                if let note = group.note { keys.append(note) }
            }
        }
        for key in keys {
            #expect(String(localized: String.LocalizationValue(key)) != key, "Missing \(key)")
        }
    }

    /// The error a one-argument call to `name` stops with, or nil if it runs.
    private func errorCalling(_ name: String) throws -> VBAError? {
        let interpreter = try VBAInterpreter(
            modules: [("Module1", .standard, "Sub T()\n    Dim x\n    x = \(name)(1)\nEnd Sub")], host: nil
        )
        do {
            _ = try interpreter.run("T")
            return nil
        } catch let error as VBAError {
            return error
        }
    }

    @Test("Functions listed as available are ones the interpreter knows")
    func availableFunctions() throws {
        let listed = MacroHelp.textFunctions + MacroHelp.mathFunctions + MacroHelp.conversionFunctions
            + MacroHelp.dateFunctions + MacroHelp.informationFunctions + MacroHelp.interactionFunctions
        for name in listed {
            let error = try errorCalling(name)
            // Number 35 is "Sub or Function not defined"; anything else means it ran.
            #expect(error?.number != 35, "\(name) is listed but not defined")
            #expect(error?.number != 445, "\(name) is listed but not supported")
        }
    }

    @Test("Functions listed as unavailable say so")
    func unavailableFunctions() throws {
        for name in MacroHelp.unavailableFunctions {
            #expect(try errorCalling(name)?.number == 445, "\(name) should report that it is not supported")
        }
    }

    /// Reads `member` of an object made fresh from a two-sheet workbook, so
    /// members that change things cannot affect one another.
    private func error(reading member: String, of make: (VBAExcelHost) -> any VBAObject) throws -> VBAError? {
        var sheet = Worksheet(name: "Data")
        sheet.codeName = "Sheet1"
        let host = VBAExcelHost(workbook: Workbook(sheets: [sheet, Worksheet(name: "Other")]), name: "Book.xlsm")
        let interpreter = try VBAInterpreter(modules: [], host: host)
        do {
            _ = try make(host).member(member, .none, in: interpreter)
            return nil
        } catch let error as VBAError {
            return error
        }
    }

    private var objects: [(name: String, available: [String], unavailable: [String],
                           make: (VBAExcelHost) -> any VBAObject)] {
        func range(_ host: VBAExcelHost) -> VBARangeObject {
            host.range(host.workbook.sheets[0].id, CellRange(start: CellAddress(a1: "A1")!, end: CellAddress(a1: "B2")!))
        }
        return [
            ("Application", MacroHelp.applicationMembers, MacroHelp.unavailableApplicationMembers, { $0.application }),
            ("Workbook", MacroHelp.workbookMembers, MacroHelp.unavailableWorkbookMembers, { $0.workbookObject }),
            ("Worksheets", MacroHelp.sheetsMembers, [], { VBASheetsObject(host: $0, worksheetsOnly: true) }),
            ("Worksheet", MacroHelp.worksheetMembers, [], { $0.worksheetObject($0.workbook.sheets[0].id) }),
            ("Range", MacroHelp.rangeMembers, MacroHelp.unavailableRangeMembers, { range($0) }),
            ("Font", MacroHelp.fontMembers, [], { VBAFontObject(range: range($0)) }),
            ("Interior", MacroHelp.interiorMembers, [], { VBAInteriorObject(range: range($0)) }),
            ("Borders", MacroHelp.bordersMembers, [], { VBABordersObject(range: range($0), edges: [9]) }),
        ]
    }

    @Test("Members listed as available are ones the objects answer to")
    func availableMembers() throws {
        for object in objects {
            for member in object.available {
                // 438 is "Object doesn't support this property or method".
                #expect(try error(reading: member, of: object.make)?.number != 438, "\(object.name).\(member)")
            }
        }
    }

    @Test("Members listed as unavailable say so")
    func unavailableMembers() throws {
        for object in objects {
            for member in object.unavailable {
                #expect(try error(reading: member, of: object.make)?.number == 445, "\(object.name).\(member)")
            }
        }
    }

    @Test("Search finds names with or without their object")
    func search() {
        #expect(MacroHelp.search("autofilter").contains { $0.name == "AutoFilter" && !$0.group.isAvailable })
        #expect(MacroHelp.search("Range.Offset").contains { $0.name == "Offset" && $0.group.isAvailable })
        #expect(MacroHelp.search("DateAdd").first?.topic.id == "Functions")
        #expect(MacroHelp.search("   ").isEmpty)
    }
}
