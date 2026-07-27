import Foundation

/// A value flowing through evaluation. Ranges stay rectangular so lookup
/// functions can index them by row and column.
enum FormulaValue: Hashable, Sendable {
    case scalar(CellValue)
    case matrix([[CellValue]])

    var flattened: [CellValue] {
        switch self {
        case .scalar(let value): return [value]
        case .matrix(let rows): return rows.flatMap { $0 }
        }
    }

    /// Collapses a range to a single value, as an operator would.
    var single: CellValue {
        switch self {
        case .scalar(let value): return value
        case .matrix(let rows): return rows.first?.first ?? .empty
        }
    }

    var firstError: CellError? {
        flattened.compactMap(\.errorValue).first
    }

    static func number(_ value: Double) -> FormulaValue { .scalar(.number(value)) }
    static func text(_ value: String) -> FormulaValue { .scalar(.text(value)) }
    static func boolean(_ value: Bool) -> FormulaValue { .scalar(.boolean(value)) }
    static func failure(_ error: CellError) -> FormulaValue { .scalar(.error(error)) }
}

/// Read access to a workbook for the evaluator, plus recursion tracking.
protocol FormulaContext: AnyObject {
    /// The sheet a formula without an explicit sheet qualifier refers to.
    var currentSheetName: String { get }
    /// The already-evaluated value of a cell, computing it on demand.
    func value(at address: CellAddress, sheetName: String?) -> CellValue
    /// The extent of a sheet, so open-ended ranges can be clamped.
    func bounds(forSheetNamed name: String?) -> (rows: Int, columns: Int)?
}

struct FormulaEvaluator {
    let context: any FormulaContext

    func evaluate(_ node: FormulaNode) -> FormulaValue {
        switch node {
        case .number(let value):
            return .number(value)
        case .text(let value):
            return .text(value)
        case .boolean(let value):
            return .boolean(value)
        case .errorLiteral(let error):
            return .failure(error)

        case .reference(let sheet, let address):
            return .scalar(context.value(at: address, sheetName: sheet))

        case .range(let sheet, let start, let end):
            return matrix(sheet: sheet, start: start, end: end)

        case .unary(let symbol, let operand):
            let value = evaluate(operand).single
            if let error = value.errorValue { return .failure(error) }
            guard symbol == "-" else { return .scalar(value) }
            guard let number = value.numericValue else { return .failure(.valueError) }
            return .number(-number)

        case .postfixPercent(let operand):
            let value = evaluate(operand).single
            if let error = value.errorValue { return .failure(error) }
            guard let number = value.numericValue else { return .failure(.valueError) }
            return .number(number / 100)

        case .binary(let symbol, let lhs, let rhs):
            return applyBinary(symbol, evaluate(lhs), evaluate(rhs))

        case .array(let rows):
            let resolved = rows.map { row in row.map { evaluate($0).single } }
            return resolved.isEmpty ? .scalar(.empty) : .matrix(resolved)

        case .call(let name, let arguments):
            return FormulaFunctions.call(name, arguments: arguments, evaluator: self)
        }
    }

    /// Materializes a range, clamped to the target sheet's extent.
    func matrix(sheet: String?, start: CellAddress, end: CellAddress) -> FormulaValue {
        let box = CellRange(start: start, end: end).normalized
        guard let extent = context.bounds(forSheetNamed: sheet) else { return .failure(.referenceError) }
        let lastRow = min(box.end.row, max(0, extent.rows - 1))
        let lastColumn = min(box.end.column, max(0, extent.columns - 1))
        guard box.start.row <= lastRow, box.start.column <= lastColumn else {
            return .matrix([[.empty]])
        }
        var rows: [[CellValue]] = []
        rows.reserveCapacity(lastRow - box.start.row + 1)
        for row in box.start.row...lastRow {
            var line: [CellValue] = []
            line.reserveCapacity(lastColumn - box.start.column + 1)
            for column in box.start.column...lastColumn {
                line.append(context.value(at: CellAddress(row: row, column: column), sheetName: sheet))
            }
            rows.append(line)
        }
        return .matrix(rows)
    }

    // MARK: - Operators

    private func applyBinary(_ symbol: String, _ lhs: FormulaValue, _ rhs: FormulaValue) -> FormulaValue {
        let left = lhs.single
        let right = rhs.single
        if let error = left.errorValue ?? right.errorValue { return .failure(error) }

        if symbol == "&" {
            return .text(left.stringValue + right.stringValue)
        }

        if ["=", "<>", "<", ">", "<=", ">="].contains(symbol) {
            return .boolean(compare(left, right, using: symbol))
        }

        guard let a = left.numericValue, let b = right.numericValue else { return .failure(.valueError) }
        switch symbol {
        case "+": return .number(a + b)
        case "-": return .number(a - b)
        case "*": return .number(a * b)
        case "/":
            guard b != 0 else { return .failure(.divideByZero) }
            return .number(a / b)
        case "^":
            let result = pow(a, b)
            return result.isFinite ? .number(result) : .failure(.numberError)
        default:
            return .failure(.valueError)
        }
    }

    private func compare(_ lhs: CellValue, _ rhs: CellValue, using symbol: String) -> Bool {
        let ordering: ComparisonResult
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)):
            ordering = a.compare(b, options: .caseInsensitive)
        case (.text, _) where !rhs.isEmpty:
            ordering = .orderedDescending  // text sorts after numbers
        case (_, .text) where !lhs.isEmpty:
            ordering = .orderedAscending
        default:
            let a = lhs.numericValue ?? 0
            let b = rhs.numericValue ?? 0
            ordering = a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
        }
        switch symbol {
        case "=": return ordering == .orderedSame
        case "<>": return ordering != .orderedSame
        case "<": return ordering == .orderedAscending
        case ">": return ordering == .orderedDescending
        case "<=": return ordering != .orderedDescending
        case ">=": return ordering != .orderedAscending
        default: return false
        }
    }
}
