import Foundation

/// Recalculates every formula in a workbook, memoizing per-cell results and
/// detecting circular references.
final class CalculationEngine: FormulaContext {
    private struct Key: Hashable {
        var sheet: Int
        var address: CellAddress
    }

    private let workbook: Workbook
    private var sheetIndicesByName: [String: Int] = [:]
    private var cache: [Key: CellValue] = [:]
    private var evaluating: Set<Key> = []
    private var parseCache: [String: Result<FormulaNode, FormulaParseFailure>] = [:]
    private var activeSheetIndex = 0

    private struct FormulaParseFailure: Error { var message: String }

    init(workbook: Workbook) {
        self.workbook = workbook
        for (index, sheet) in workbook.sheets.enumerated() {
            sheetIndicesByName[sheet.name.lowercased()] = index
        }
    }

    /// Returns a copy of the workbook with every formula cell's cached value refreshed.
    static func recalculated(_ workbook: Workbook) -> Workbook {
        let engine = CalculationEngine(workbook: workbook)
        var result = workbook
        for (sheetIndex, sheet) in workbook.sheets.enumerated() {
            for (address, cell) in sheet.cells where cell.formula != nil {
                engine.activeSheetIndex = sheetIndex
                var updated = cell
                updated.value = engine.value(at: address, sheetIndex: sheetIndex)
                result.sheets[sheetIndex].cells[address] = updated
            }
        }
        return result
    }

    /// Evaluates a formula body in the context of a sheet without storing anything.
    static func preview(formula body: String, in workbook: Workbook, sheetIndex: Int) -> CellValue {
        let engine = CalculationEngine(workbook: workbook)
        engine.activeSheetIndex = sheetIndex
        return engine.evaluate(body: body, sheetIndex: sheetIndex)
    }

    // MARK: - FormulaContext

    var currentSheetName: String {
        workbook.sheets.indices.contains(activeSheetIndex) ? workbook.sheets[activeSheetIndex].name : ""
    }

    func value(at address: CellAddress, sheetName: String?) -> CellValue {
        guard let index = resolveSheetIndex(sheetName) else { return .error(.referenceError) }
        return value(at: address, sheetIndex: index)
    }

    func bounds(forSheetNamed name: String?) -> (rows: Int, columns: Int)? {
        guard let index = resolveSheetIndex(name) else { return nil }
        let sheet = workbook.sheets[index]
        return (sheet.rowCount, sheet.columnCount)
    }

    // MARK: - Evaluation

    private func resolveSheetIndex(_ name: String?) -> Int? {
        guard let name else { return workbook.sheets.indices.contains(activeSheetIndex) ? activeSheetIndex : nil }
        return sheetIndicesByName[name.lowercased()]
    }

    private func value(at address: CellAddress, sheetIndex: Int) -> CellValue {
        guard workbook.sheets.indices.contains(sheetIndex) else { return .error(.referenceError) }
        let sheet = workbook.sheets[sheetIndex]
        guard sheet.contains(address) else { return .empty }

        let key = Key(sheet: sheetIndex, address: address)
        if let cached = cache[key] { return cached }

        let cell = sheet[address]
        guard let formula = cell.formula else { return cell.value }

        guard !evaluating.contains(key) else { return .error(.circularReference) }
        evaluating.insert(key)
        defer { evaluating.remove(key) }

        let previousSheet = activeSheetIndex
        activeSheetIndex = sheetIndex
        let result = evaluate(body: formula, sheetIndex: sheetIndex)
        activeSheetIndex = previousSheet

        cache[key] = result
        return result
    }

    private func evaluate(body: String, sheetIndex: Int) -> CellValue {
        switch parsed(body) {
        case .failure:
            return .error(.nameError)
        case .success(let node):
            let previousSheet = activeSheetIndex
            activeSheetIndex = sheetIndex
            defer { activeSheetIndex = previousSheet }
            return FormulaEvaluator(context: self).evaluate(node).single
        }
    }

    private func parsed(_ body: String) -> Result<FormulaNode, FormulaParseFailure> {
        if let cached = parseCache[body] { return cached }
        let outcome: Result<FormulaNode, FormulaParseFailure>
        do {
            outcome = .success(try FormulaParser.parse(body))
        } catch let error as FormulaParseError {
            outcome = .failure(FormulaParseFailure(message: error.message))
        } catch let error as FormulaLexError {
            outcome = .failure(FormulaParseFailure(message: error.message))
        } catch {
            outcome = .failure(FormulaParseFailure(message: "Invalid formula"))
        }
        parseCache[body] = outcome
        return outcome
    }
}

extension Workbook {
    /// Refreshes every cached formula result in place.
    mutating func recalculate() {
        self = CalculationEngine.recalculated(self)
    }
}

// MARK: - Parsing user input

enum CellInputParser {
    /// Interprets raw text typed into a cell: formulas, numbers, percentages,
    /// booleans, and everything else as text.
    static func cell(from input: String, inheriting style: CellStyle) -> Cell {
        var cell = Cell(value: .empty, formula: nil, style: style)
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty { return cell }

        if trimmed.hasPrefix("=") {
            cell.formula = String(trimmed.dropFirst())
            cell.value = .empty
            return cell
        }

        // Explicitly text-formatted cells never coerce.
        if style.numberFormat == NumberFormatPreset.text.code {
            cell.value = .text(input)
            return cell
        }

        if trimmed.caseInsensitiveCompare("TRUE") == .orderedSame {
            cell.value = .boolean(true)
            return cell
        }
        if trimmed.caseInsensitiveCompare("FALSE") == .orderedSame {
            cell.value = .boolean(false)
            return cell
        }
        if let error = CellError.allCases.first(where: { $0.rawValue == trimmed.uppercased() }) {
            cell.value = .error(error)
            return cell
        }
        if let number = number(from: trimmed) {
            cell.value = .number(number.value)
            if let format = number.impliedFormat, cell.style.numberFormat == NumberFormatPreset.general.code {
                cell.style.numberFormat = format
            }
            return cell
        }
        cell.value = .text(input)
        return cell
    }

    private struct ParsedNumber {
        var value: Double
        var impliedFormat: String?
    }

    private static func number(from text: String) -> ParsedNumber? {
        if let plain = Double(text) { return ParsedNumber(value: plain, impliedFormat: nil) }

        var working = text
        var impliedFormat: String?

        if working.hasSuffix("%") {
            working.removeLast()
            guard let value = Double(working.replacingOccurrences(of: ",", with: "")) else { return nil }
            return ParsedNumber(value: value / 100, impliedFormat: NumberFormatPreset.percent.code)
        }

        // A leading currency symbol implies currency formatting.
        if let first = working.first, "$€£¥".contains(first) {
            working.removeFirst()
            impliedFormat = NumberFormatPreset.currency.code
        }

        let stripped = working.replacingOccurrences(of: ",", with: "")
        guard stripped.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789")) != nil,
              let value = Double(stripped) else { return nil }
        if impliedFormat == nil, working.contains(",") {
            impliedFormat = NumberFormatPreset.thousands.code
        }
        return ParsedNumber(value: value, impliedFormat: impliedFormat)
    }
}
