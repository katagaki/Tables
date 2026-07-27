import Foundation

/// The evaluated content of a cell.
enum CellValue: Hashable, Sendable {
    case empty
    case number(Double)
    case text(String)
    case boolean(Bool)
    case error(CellError)

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    /// Numeric coercion used by arithmetic and most functions.
    var numericValue: Double? {
        switch self {
        case .empty: return 0
        case .number(let value): return value
        case .boolean(let flag): return flag ? 1 : 0
        case .text(let string):
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : Double(trimmed)
        case .error: return nil
        }
    }

    /// String coercion used by text functions and concatenation.
    var stringValue: String {
        switch self {
        case .empty: return ""
        case .number(let value): return Self.plainNumberString(value)
        case .text(let string): return string
        case .boolean(let flag): return flag ? "TRUE" : "FALSE"
        case .error(let error): return error.rawValue
        }
    }

    var errorValue: CellError? {
        if case .error(let error) = self { return error }
        return nil
    }

    /// Renders a double the way a spreadsheet does by default: no trailing zeros,
    /// scientific notation only for extreme magnitudes.
    static func plainNumberString(_ value: Double) -> String {
        if value.isNaN { return CellError.numberError.rawValue }
        if value.isInfinite { return CellError.divideByZero.rawValue }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        let magnitude = abs(value)
        if magnitude != 0, magnitude < 1e-9 || magnitude >= 1e15 {
            return String(format: "%.8E", value)
        }
        var text = String(format: "%.10f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

/// The classic spreadsheet error sentinels.
enum CellError: String, Hashable, Sendable, CaseIterable {
    case divideByZero = "#DIV/0!"
    case valueError = "#VALUE!"
    case referenceError = "#REF!"
    case nameError = "#NAME?"
    case numberError = "#NUM!"
    case notAvailable = "#N/A"
    case nullError = "#NULL!"
    /// Shown in the grid when a formula depends on itself. Excel has no such
    /// literal — it reports circularity out of band — so this one is ours.
    case circularReference = "#CIRC!"

    /// The literal to store in a workbook. OOXML defines a closed set of error
    /// values, and writing anything outside it makes the file unreadable, so the
    /// app's own sentinel is mapped onto the nearest standard one.
    var ooxmlValue: String {
        self == .circularReference ? CellError.valueError.rawValue : rawValue
    }
}
