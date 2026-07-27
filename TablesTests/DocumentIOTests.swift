import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Tables

@Suite("ZIP container")
struct ZipArchiveTests {
    @Test("Entries survive a write/read round trip")
    func roundTrip() throws {
        let small = Data("hello".utf8)
        let large = Data(String(repeating: "spreadsheet ", count: 5_000).utf8)
        let binary = Data((0..<4096).map { UInt8($0 % 251) })

        let archive = try ZipArchive.archive(entries: [
            ("a.txt", small), ("nested/b.xml", large), ("c.bin", binary),
        ])
        let entries = try ZipArchive.entries(in: archive)

        #expect(entries.count == 3)
        #expect(entries["a.txt"] == small)
        #expect(entries["nested/b.xml"] == large)
        #expect(entries["c.bin"] == binary)
    }

    @Test("Non-archives are rejected rather than misread")
    func rejectsGarbage() {
        #expect(throws: (any Error).self) {
            _ = try ZipArchive.entries(in: Data(repeating: 0x41, count: 512))
        }
    }

    @Test("CRC-32 matches the known check value")
    func checksum() {
        #expect(ZipArchive.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }
}

@Suite("XLSX round trip")
struct XLSXTests {
    private func sampleWorkbook() -> Workbook {
        var first = Worksheet(name: "Numbers")
        first.rowCount = 24
        first.columnCount = 6

        var bold = CellStyle.default
        bold.isBold = true
        bold.fillColorHex = "FFFFE08A"
        bold.horizontalAlignment = .center

        var currency = CellStyle.default
        currency.numberFormat = NumberFormatPreset.currency.code
        currency.borders = .all

        first[CellAddress(a1: "A1")!] = Cell(value: .text("Region"), formula: nil, style: bold)
        first[CellAddress(a1: "B1")!] = Cell(value: .text("Revenue"), formula: nil, style: bold)
        first[CellAddress(a1: "A2")!] = Cell(value: .text("North"), formula: nil, style: .default)
        first[CellAddress(a1: "B2")!] = Cell(value: .number(1200.5), formula: nil, style: currency)
        first[CellAddress(a1: "A3")!] = Cell(value: .text("South"), formula: nil, style: .default)
        first[CellAddress(a1: "B3")!] = Cell(value: .number(980), formula: nil, style: currency)
        first[CellAddress(a1: "B4")!] = Cell(value: .empty, formula: "SUM(B2:B3)", style: currency)
        first[CellAddress(a1: "C2")!] = Cell(value: .boolean(true), formula: nil, style: .default)
        first[CellAddress(a1: "C3")!] = Cell(value: .error(.notAvailable), formula: nil, style: .default)

        first.columnWidths[0] = 160
        first.rowHeights[0] = 44
        first.hiddenColumns.insert(4)
        first.hiddenRows.insert(9)

        let second = Worksheet(name: "Empty Sheet")

        var workbook = Workbook(sheets: [first, second])
        workbook.recalculate()
        return workbook
    }

    @Test("Values, formulas and structure survive a save/open cycle")
    func roundTrip() throws {
        let original = sampleWorkbook()
        let data = try XLSXWriter.data(from: original)
        let reloaded = try XLSXReader.workbook(from: data)

        #expect(reloaded.sheets.count == 2)
        #expect(reloaded.sheets[0].name == "Numbers")
        #expect(reloaded.sheets[1].name == "Empty Sheet")

        let sheet = reloaded.sheets[0]
        #expect(sheet[CellAddress(a1: "A1")!].value == .text("Region"))
        #expect(sheet[CellAddress(a1: "B2")!].value == .number(1200.5))
        #expect(sheet[CellAddress(a1: "C2")!].value == .boolean(true))
        #expect(sheet[CellAddress(a1: "C3")!].value == .error(.notAvailable))
        #expect(sheet[CellAddress(a1: "B4")!].formula == "SUM(B2:B3)")
        #expect(sheet[CellAddress(a1: "B4")!].value == .number(2180.5))

        #expect(sheet.hiddenColumns.contains(4))
        #expect(sheet.hiddenRows.contains(9))
        #expect(abs(sheet.width(ofColumn: 0) - 160) < 2)
    }

    @Test("Formatting survives a save/open cycle")
    func formatting() throws {
        let data = try XLSXWriter.data(from: sampleWorkbook())
        let sheet = try XLSXReader.workbook(from: data).sheets[0]

        let header = sheet[CellAddress(a1: "A1")!].style
        #expect(header.isBold)
        #expect(header.fillColorHex == "FFFFE08A")
        #expect(header.horizontalAlignment == .center)

        let money = sheet[CellAddress(a1: "B2")!].style
        #expect(money.numberFormat == NumberFormatPreset.currency.code)
        #expect(money.borders == .all)
    }

    @Test("The package really is a ZIP with the expected parts")
    func packageLayout() throws {
        let data = try XLSXWriter.data(from: sampleWorkbook())
        #expect(data.starts(with: [0x50, 0x4B]))

        let entries = try ZipArchive.entries(in: data)
        #expect(entries["[Content_Types].xml"] != nil)
        #expect(entries["_rels/.rels"] != nil)
        #expect(entries["xl/workbook.xml"] != nil)
        #expect(entries["xl/styles.xml"] != nil)
        #expect(entries["xl/worksheets/sheet1.xml"] != nil)
        #expect(entries["xl/worksheets/sheet2.xml"] != nil)
    }

    @Test("Sheet names needing escapes round-trip")
    func escaping() throws {
        var sheet = Worksheet(name: "R&D <2024>")
        sheet[CellAddress(a1: "A1")!] = Cell(value: .text("a \"quoted\" & <tagged> value"),
                                             formula: nil, style: .default)
        let data = try XLSXWriter.data(from: Workbook(sheets: [sheet]))
        let reloaded = try XLSXReader.workbook(from: data)
        #expect(reloaded.sheets[0].name == "R&D <2024>")
        #expect(reloaded.sheets[0][CellAddress(a1: "A1")!].value == .text("a \"quoted\" & <tagged> value"))
    }
}

@Suite("CSV")
struct CSVTests {
    @Test("Quoting, embedded delimiters and newlines parse correctly")
    func parsing() {
        let text = """
        name,note,amount
        Ada,"Says ""hello"", loudly",10
        Bob,"multi
        line",20

        """
        let workbook = CSVCodec.workbook(from: Data(text.utf8), sheetName: "Imported")
        let sheet = workbook.sheets[0]

        #expect(sheet[CellAddress(a1: "A2")!].value == .text("Ada"))
        #expect(sheet[CellAddress(a1: "B2")!].value == .text("Says \"hello\", loudly"))
        #expect(sheet[CellAddress(a1: "C2")!].value == .number(10))
        #expect(sheet[CellAddress(a1: "B3")!].value == .text("multi\nline"))
    }

    @Test("Semicolon files are sniffed")
    func delimiterSniffing() {
        let workbook = CSVCodec.workbook(from: Data("a;b;c\n1;2;3\n".utf8), sheetName: "S")
        #expect(workbook.sheets[0][CellAddress(a1: "C2")!].value == .number(3))
    }

    @Test("Export writes displayed values and re-imports cleanly")
    func exportRoundTrip() {
        let workbook = CSVCodec.workbook(
            from: Data("x,y\n1,2\n3,=A3+B2\n".utf8), sheetName: "S"
        )
        let exported = CSVCodec.data(from: workbook.sheets[0])
        let text = String(decoding: exported, as: UTF8.self)
        #expect(text.hasPrefix("x,y"))

        let reimported = CSVCodec.workbook(from: exported, sheetName: "S")
        #expect(reimported.sheets[0][CellAddress(a1: "A2")!].value == .number(1))
    }

    @Test("CRLF line endings split rows", arguments: ["\r\n", "\n", "\r"])
    func lineEndings(separator: String) {
        let text = ["a,b", "1,2", "3,4"].joined(separator: separator) + separator
        let sheet = CSVCodec.workbook(from: Data(text.utf8), sheetName: "S").sheets[0]
        #expect(sheet[CellAddress(a1: "A2")!].value == .number(1))
        #expect(sheet[CellAddress(a1: "B3")!].value == .number(4))
    }

    @Test("A blank import still gets the default grid")
    func defaultSize() {
        let workbook = CSVCodec.workbook(from: Data(), sheetName: "Blank")
        #expect(workbook.sheets[0].rowCount == Worksheet.defaultRowCount)
        #expect(workbook.sheets[0].columnCount == Worksheet.defaultColumnCount)
    }
}

@Suite("Document types")
struct DocumentTypeTests {
    @Test("The workbook type resolves to a real xlsx type on every platform")
    func workbookType() {
        #expect(UTType.openXMLWorkbook.identifier == "org.openxmlformats.spreadsheetml.sheet")
        #expect(UTType.openXMLWorkbook.preferredFilenameExtension == "xlsx")
        #expect(TablesDocument.writableContentTypes.first == .openXMLWorkbook)
    }
}
