import Testing
@testable import Tables

/// Builds a one-sheet workbook from an A1-keyed table of raw entries.
private func makeWorkbook(_ entries: [String: String], name: String = "Sheet 1") -> Workbook {
    var sheet = Worksheet(name: name)
    for (reference, input) in entries {
        guard let address = CellAddress(a1: reference) else { continue }
        sheet.rowCount = max(sheet.rowCount, address.row + 1)
        sheet.columnCount = max(sheet.columnCount, address.column + 1)
        sheet[address] = CellInputParser.cell(from: input, inheriting: .default)
    }
    var workbook = Workbook(sheets: [sheet])
    workbook.recalculate()
    return workbook
}

private func value(_ workbook: Workbook, _ reference: String, sheet: Int = 0) -> CellValue {
    workbook.sheets[sheet][CellAddress(a1: reference)!].value
}

private func number(_ workbook: Workbook, _ reference: String, sheet: Int = 0) -> Double? {
    value(workbook, reference, sheet: sheet).numericValue
}

@Suite("Cell addressing")
struct CellAddressTests {
    @Test("Column names round-trip past Z")
    func columnNames() {
        #expect(CellAddress.columnName(0) == "A")
        #expect(CellAddress.columnName(25) == "Z")
        #expect(CellAddress.columnName(26) == "AA")
        #expect(CellAddress.columnName(701) == "ZZ")
        #expect(CellAddress.columnName(702) == "AAA")
        for index in [0, 1, 25, 26, 27, 51, 52, 701, 702, 1000] {
            #expect(CellAddress.columnIndex(CellAddress.columnName(index)) == index)
        }
    }

    @Test("A1 references parse, including dollar anchors")
    func parsing() {
        #expect(CellAddress(a1: "A1") == CellAddress(row: 0, column: 0))
        #expect(CellAddress(a1: "$C$7") == CellAddress(row: 6, column: 2))
        #expect(CellAddress(a1: "AB12") == CellAddress(row: 11, column: 27))
        #expect(CellAddress(a1: "1A") == nil)
        #expect(CellAddress(a1: "A") == nil)
    }
}

@Suite("Formula evaluation")
struct FormulaEvaluationTests {
    @Test("Arithmetic honours precedence and associativity")
    func arithmetic() {
        let workbook = makeWorkbook([
            "A1": "=1+2*3",
            "A2": "=(1+2)*3",
            "A3": "=2^3^2",
            "A4": "=-3^2",
            "A5": "=10/4",
            "A6": "=50%",
        ])
        #expect(number(workbook, "A1") == 7)
        #expect(number(workbook, "A2") == 9)
        #expect(number(workbook, "A3") == 512)   // right-associative
        #expect(number(workbook, "A4") == 9)     // unary minus binds first here
        #expect(number(workbook, "A5") == 2.5)
        #expect(number(workbook, "A6") == 0.5)
    }

    @Test("Division by zero yields the standard error")
    func divideByZero() {
        let workbook = makeWorkbook(["A1": "=1/0"])
        #expect(value(workbook, "A1") == .error(.divideByZero))
    }

    @Test("References and ranges resolve")
    func references() {
        let workbook = makeWorkbook([
            "A1": "10", "A2": "20", "A3": "30",
            "B1": "=A1+A2",
            "B2": "=SUM(A1:A3)",
            "B3": "=AVERAGE(A1:A3)",
            "B4": "=COUNT(A1:A3)",
            "B5": "=MAX(A1:A3)-MIN(A1:A3)",
        ])
        #expect(number(workbook, "B1") == 30)
        #expect(number(workbook, "B2") == 60)
        #expect(number(workbook, "B3") == 20)
        #expect(number(workbook, "B4") == 3)
        #expect(number(workbook, "B5") == 20)
    }

    @Test("Formulas chain through other formulas")
    func chaining() {
        let workbook = makeWorkbook([
            "A1": "5", "A2": "=A1*2", "A3": "=A2*2", "A4": "=A3+A1",
        ])
        #expect(number(workbook, "A4") == 25)
    }

    @Test("Circular references are caught instead of hanging")
    func circular() {
        let workbook = makeWorkbook(["A1": "=B1", "B1": "=A1"])
        #expect(value(workbook, "A1").errorValue == .circularReference)
    }

    @Test("Cross-sheet references resolve by name")
    func crossSheet() {
        var first = Worksheet(name: "Data")
        first[CellAddress(a1: "A1")!] = CellInputParser.cell(from: "42", inheriting: .default)
        var second = Worksheet(name: "Report")
        second[CellAddress(a1: "A1")!] = CellInputParser.cell(from: "=Data!A1*2", inheriting: .default)
        var workbook = Workbook(sheets: [first, second])
        workbook.recalculate()
        #expect(number(workbook, "A1", sheet: 1) == 84)
    }

    @Test("Text, logic and lookup functions behave")
    func library() {
        let workbook = makeWorkbook([
            "A1": "apple", "A2": "banana", "A3": "cherry",
            "B1": "10", "B2": "20", "B3": "30",
            "C1": "=UPPER(A1)",
            "C2": "=LEFT(A2,3)",
            "C3": "=LEN(A3)",
            "C4": "=CONCAT(A1,\"-\",A2)",
            "C5": "=IF(B2>15,\"big\",\"small\")",
            "C6": "=VLOOKUP(\"banana\",A1:B3,2,FALSE)",
            "C7": "=SUMIF(B1:B3,\">15\")",
            "C8": "=COUNTIF(A1:A3,\"cherry\")",
            "C9": "=IFERROR(1/0,\"safe\")",
            "C10": "=AND(TRUE,B1<B2)",
            "C11": "=ROUND(2.567,2)",
            "C12": "=INDEX(A1:B3,2,1)",
            "C13": "=MATCH(30,B1:B3,0)",
        ])
        #expect(value(workbook, "C1") == .text("APPLE"))
        #expect(value(workbook, "C2") == .text("ban"))
        #expect(number(workbook, "C3") == 6)
        #expect(value(workbook, "C4") == .text("apple-banana"))
        #expect(value(workbook, "C5") == .text("big"))
        #expect(number(workbook, "C6") == 20)
        #expect(number(workbook, "C7") == 50)
        #expect(number(workbook, "C8") == 1)
        #expect(value(workbook, "C9") == .text("safe"))
        #expect(value(workbook, "C10") == .boolean(true))
        #expect(number(workbook, "C11") == 2.57)
        #expect(value(workbook, "C12") == .text("banana"))
        #expect(number(workbook, "C13") == 3)
    }

    @Test("Unknown names surface as #NAME?")
    func unknownFunction() {
        let workbook = makeWorkbook(["A1": "=NOTAFUNCTION(1)"])
        #expect(value(workbook, "A1").errorValue == .nameError)
    }

    @Test("Comparison operators produce booleans")
    func comparisons() {
        let workbook = makeWorkbook([
            "A1": "=1<2", "A2": "=2<=2", "A3": "=3<>3", "A4": "=\"a\"=\"A\"",
        ])
        #expect(value(workbook, "A1") == .boolean(true))
        #expect(value(workbook, "A2") == .boolean(true))
        #expect(value(workbook, "A3") == .boolean(false))
        #expect(value(workbook, "A4") == .boolean(true))
    }
}

@Suite("Typed input")
struct CellInputTests {
    @Test("Numbers, percentages and currency are recognized")
    func coercion() {
        #expect(CellInputParser.cell(from: "42", inheriting: .default).value == .number(42))
        #expect(CellInputParser.cell(from: "-3.5", inheriting: .default).value == .number(-3.5))

        let percent = CellInputParser.cell(from: "25%", inheriting: .default)
        #expect(percent.value == .number(0.25))
        #expect(percent.style.numberFormat == NumberFormatPreset.percent.code)

        let currency = CellInputParser.cell(from: "$1,200.50", inheriting: .default)
        #expect(currency.value == .number(1200.5))
        #expect(currency.style.numberFormat == NumberFormatPreset.currency.code)
    }

    @Test("Text-formatted cells never coerce")
    func textFormatWins() {
        var style = CellStyle.default
        style.numberFormat = NumberFormatPreset.text.code
        #expect(CellInputParser.cell(from: "007", inheriting: style).value == .text("007"))
    }

    @Test("A leading equals sign starts a formula")
    func formulas() {
        let cell = CellInputParser.cell(from: "=SUM(A1:A2)", inheriting: .default)
        #expect(cell.formula == "SUM(A1:A2)")
    }
}

@Suite("Number formatting")
struct NumberFormatTests {
    @Test("Preset codes render as expected")
    func presets() {
        #expect(CellFormatter.displayText(for: .number(1234.5), format: "General") == "1234.5")
        #expect(CellFormatter.displayText(for: .number(1234.5), format: "0") == "1235")
        #expect(CellFormatter.displayText(for: .number(1234.5), format: "0.00") == "1234.50")
        #expect(CellFormatter.displayText(for: .number(1234.5), format: "#,##0") == "1,235")
        #expect(CellFormatter.displayText(for: .number(1234.5), format: "$#,##0.00") == "$1,234.50")
        #expect(CellFormatter.displayText(for: .number(0.128), format: "0%") == "13%")
        #expect(CellFormatter.displayText(for: .number(0.128), format: "0.00%") == "12.80%")
    }

    @Test("Negative numbers use the second section when present")
    func sections() {
        #expect(CellFormatter.displayText(for: .number(-42), format: "#,##0;(#,##0)") == "(42)")
        #expect(CellFormatter.displayText(for: .number(-42), format: "0.00") == "-42.00")
    }

    @Test("Date serials render through date tokens")
    func dates() {
        // 45000 is 2023-03-15 in the 1900 date system.
        let serial = CellFormatter.serial(fromDate: CellFormatter.date(fromSerial: 45_000))
        #expect(abs(serial - 45_000) < 0.0001)
        #expect(CellFormatter.displayText(for: .number(45_000), format: "yyyy-mm-dd") == "2023-03-15")
    }

    @Test("Errors and booleans bypass numeric formatting")
    func passthrough() {
        #expect(CellFormatter.displayText(for: .error(.valueError), format: "0.00") == "#VALUE!")
        #expect(CellFormatter.displayText(for: .boolean(true), format: "0.00") == "TRUE")
    }
}

@Suite("Position functions through the engine")
struct EnginePositionFunctionTests {
    /// `ROW()` and `COLUMN()` with no argument report the cell they sit in, so
    /// they only work if the engine tells the evaluator where it is.
    @Test("Bare ROW and COLUMN report the containing cell")
    func bareForms() {
        var sheet = Worksheet(name: "S")
        sheet[CellAddress(a1: "C7")!] = CellInputParser.cell(from: "=ROW()", inheriting: .default)
        sheet[CellAddress(a1: "D2")!] = CellInputParser.cell(from: "=COLUMN()", inheriting: .default)
        sheet[CellAddress(a1: "B3")!] = CellInputParser.cell(from: "=ROW()*COLUMN()", inheriting: .default)
        var workbook = Workbook(sheets: [sheet])
        workbook.recalculate()

        #expect(workbook.sheets[0][CellAddress(a1: "C7")!].value == .number(7))
        #expect(workbook.sheets[0][CellAddress(a1: "D2")!].value == .number(4))
        #expect(workbook.sheets[0][CellAddress(a1: "B3")!].value == .number(6))
    }

    @Test("An explicit reference still wins over the containing cell")
    func referenceForm() {
        var sheet = Worksheet(name: "S")
        sheet[CellAddress(a1: "A1")!] = CellInputParser.cell(from: "=ROW(B9)", inheriting: .default)
        var workbook = Workbook(sheets: [sheet])
        workbook.recalculate()
        #expect(workbook.sheets[0][CellAddress(a1: "A1")!].value == .number(9))
    }
}
