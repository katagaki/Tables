import Foundation

/// The built-in function library. Functions receive unevaluated arguments so
/// that `IF`, `IFERROR` and friends can control evaluation themselves.
enum FormulaFunctions {
    static let names: [String] = [
        "ABS", "AND", "AVERAGE", "AVERAGEA", "AVERAGEIF", "AVERAGEIFS", "CEILING", "CHAR",
        "CHOOSE", "CODE", "COLUMN", "CONCAT", "CONCATENATE", "COUNT", "COUNTA", "COUNTBLANK",
        "COUNTIF", "COUNTIFS", "DATE",
        "DAY", "DEGREES", "EXACT", "EXP", "FALSE", "FIND", "FLOOR", "HLOOKUP", "HOUR", "IF",
        "IFERROR", "IFNA", "IFS", "INDEX", "INT", "ISBLANK", "ISERROR", "ISEVEN", "ISLOGICAL",
        "ISNUMBER", "ISODD", "ISTEXT", "LARGE", "LEFT", "LEN", "LN", "LOG", "LOG10", "LOWER",
        "MATCH", "MAX", "MEDIAN", "MID", "MIN", "MINUTE", "MOD", "MONTH", "NA", "NOT", "NOW",
        "OR", "PI", "POWER", "PRODUCT", "PROPER", "RADIANS", "RAND", "RANDBETWEEN", "REPLACE",
        "REPT", "RIGHT", "ROUND", "ROUNDDOWN", "ROUNDUP", "ROW", "SEARCH", "SECOND", "SIGN",
        "SMALL", "SQRT", "STDEV", "SUBSTITUTE", "SUM", "SUMIF", "SUMIFS", "SUMPRODUCT", "SWITCH",
        "TEXT", "TEXTJOIN", "TIME",
        "TODAY", "TRIM", "TRUE", "TRUNC", "UPPER", "VALUE", "VAR", "VLOOKUP", "WEEKDAY",
        "XLOOKUP", "XOR",
        "YEAR", "COS", "SIN", "TAN", "ACOS", "ASIN", "ATAN", "ATAN2",
    ]

    // MARK: - Dispatch

    static func call(_ name: String, arguments: [FormulaNode], evaluator: FormulaEvaluator) -> FormulaValue {
        var call = CallFrame(name: name, nodes: arguments, evaluator: evaluator)
        return dispatch(&call)
    }

    /// Bundles an invocation so each implementation can pull what it needs.
    private struct CallFrame {
        let name: String
        let nodes: [FormulaNode]
        let evaluator: FormulaEvaluator

        var count: Int { nodes.count }

        func value(_ index: Int) -> FormulaValue {
            guard index < nodes.count else { return .scalar(.empty) }
            return evaluator.evaluate(nodes[index])
        }

        func scalar(_ index: Int) -> CellValue { value(index).single }

        func number(_ index: Int) -> Double? { scalar(index).numericValue }

        func string(_ index: Int) -> String { scalar(index).stringValue }

        func boolean(_ index: Int) -> Bool {
            let value = scalar(index)
            if case .text(let text) = value {
                if text.caseInsensitiveCompare("TRUE") == .orderedSame { return true }
                if text.caseInsensitiveCompare("FALSE") == .orderedSame { return false }
            }
            return (value.numericValue ?? 0) != 0
        }

        /// Every cell across all arguments, ranges expanded.
        var allValues: [CellValue] { nodes.indices.flatMap { evaluator.evaluate(nodes[$0]).flattened } }

        /// The first error found in any argument, if any.
        var propagatedError: CellError? { allValues.compactMap(\.errorValue).first }

        /// Numbers only — text and blanks are skipped, the way `SUM` does it.
        var numbers: [Double] {
            allValues.compactMap { value in
                switch value {
                case .number(let number): return number
                case .boolean(let flag): return flag ? 1 : 0
                default: return nil
                }
            }
        }
    }

    private static func dispatch(_ call: inout CallFrame) -> FormulaValue {
        switch call.name {
        // MARK: Aggregates
        case "SUM": return aggregate(call) { $0.reduce(0, +) }
        case "PRODUCT": return aggregate(call) { $0.isEmpty ? 0 : $0.reduce(1, *) }
        case "AVERAGE", "AVERAGEA":
            if let error = call.propagatedError { return .failure(error) }
            let numbers = call.numbers
            guard !numbers.isEmpty else { return .failure(.divideByZero) }
            return .number(numbers.reduce(0, +) / Double(numbers.count))
        case "MIN": return aggregate(call) { $0.min() ?? 0 }
        case "MAX": return aggregate(call) { $0.max() ?? 0 }
        case "MEDIAN":
            if let error = call.propagatedError { return .failure(error) }
            let sorted = call.numbers.sorted()
            guard !sorted.isEmpty else { return .failure(.numberError) }
            let middle = sorted.count / 2
            return .number(sorted.count % 2 == 1
                           ? sorted[middle]
                           : (sorted[middle - 1] + sorted[middle]) / 2)
        case "STDEV", "VAR":
            if let error = call.propagatedError { return .failure(error) }
            let numbers = call.numbers
            guard numbers.count > 1 else { return .failure(.divideByZero) }
            let mean = numbers.reduce(0, +) / Double(numbers.count)
            let variance = numbers.reduce(0) { $0 + pow($1 - mean, 2) } / Double(numbers.count - 1)
            return .number(call.name == "VAR" ? variance : sqrt(variance))
        case "COUNT":
            return .number(Double(call.allValues.filter { if case .number = $0 { return true }; return false }.count))
        case "COUNTA":
            return .number(Double(call.allValues.filter { !$0.isEmpty }.count))
        case "COUNTBLANK":
            return .number(Double(call.allValues.filter(\.isEmpty).count))
        case "LARGE", "SMALL":
            guard call.count >= 2, let rank = call.number(1) else { return .failure(.valueError) }
            let pool = call.value(0).flattened.compactMap { value -> Double? in
                if case .number(let number) = value { return number }
                return nil
            }
            let sorted = call.name == "LARGE" ? pool.sorted(by: >) : pool.sorted()
            let position = Int(rank) - 1
            guard position >= 0, position < sorted.count else { return .failure(.numberError) }
            return .number(sorted[position])
        case "SUMPRODUCT":
            let columns = call.nodes.indices.map { call.evaluator.evaluate(call.nodes[$0]).flattened }
            guard let width = columns.first?.count, columns.allSatisfy({ $0.count == width }) else {
                return .failure(.valueError)
            }
            var total = 0.0
            for position in 0..<width {
                var product = 1.0
                for column in columns { product *= column[position].numericValue ?? 0 }
                total += product
            }
            return .number(total)

        // MARK: Conditional aggregates
        case "SUMIF", "COUNTIF", "AVERAGEIF":
            return conditionalAggregate(call)
        case "SUMIFS", "COUNTIFS", "AVERAGEIFS":
            return multiCriteriaAggregate(call)

        // MARK: Logic
        case "IF":
            guard call.count >= 2 else { return .failure(.valueError) }
            if let error = call.scalar(0).errorValue { return .failure(error) }
            if call.boolean(0) { return call.value(1) }
            return call.count >= 3 ? call.value(2) : .boolean(false)
        case "IFS":
            var index = 0
            while index + 1 < call.count {
                if let error = call.scalar(index).errorValue { return .failure(error) }
                if call.boolean(index) { return call.value(index + 1) }
                index += 2
            }
            return .failure(.notAvailable)
        case "SWITCH":
            return switchCase(call)
        case "IFERROR", "IFNA":
            let primary = call.value(0)
            let trapped: Bool
            if call.name == "IFNA" {
                trapped = primary.firstError == .notAvailable
            } else {
                trapped = primary.firstError != nil
            }
            return trapped ? (call.count >= 2 ? call.value(1) : .scalar(.empty)) : primary
        case "AND":
            if let error = call.propagatedError { return .failure(error) }
            return .boolean(call.nodes.indices.allSatisfy { call.boolean($0) })
        case "OR":
            if let error = call.propagatedError { return .failure(error) }
            return .boolean(call.nodes.indices.contains { call.boolean($0) })
        case "XOR":
            if let error = call.propagatedError { return .failure(error) }
            return .boolean(call.nodes.indices.filter { call.boolean($0) }.count % 2 == 1)
        case "NOT":
            return .boolean(!call.boolean(0))
        case "TRUE": return .boolean(true)
        case "FALSE": return .boolean(false)
        case "NA": return .failure(.notAvailable)

        // MARK: Information
        case "ISBLANK": return .boolean(call.value(0).single.isEmpty)
        case "ISERROR": return .boolean(call.value(0).firstError != nil)
        case "ISNUMBER":
            if case .number = call.scalar(0) { return .boolean(true) }
            return .boolean(false)
        case "ISTEXT":
            if case .text = call.scalar(0) { return .boolean(true) }
            return .boolean(false)
        case "ISLOGICAL":
            if case .boolean = call.scalar(0) { return .boolean(true) }
            return .boolean(false)
        case "ISEVEN", "ISODD":
            guard let number = call.number(0) else { return .failure(.valueError) }
            let isEven = Int(number.rounded(.towardZero)) % 2 == 0
            return .boolean(call.name == "ISEVEN" ? isEven : !isEven)
        case "ROW", "COLUMN":
            // With no argument the answer is the position of the calling cell.
            let address: CellAddress?
            if call.nodes.isEmpty {
                address = call.evaluator.currentAddress
            } else if case .reference(_, let referenced)? = call.nodes.first {
                address = referenced
            } else {
                address = nil
            }
            guard let address else { return .failure(.valueError) }
            return .number(Double(call.name == "ROW" ? address.row + 1 : address.column + 1))

        // MARK: Math
        case "ABS": return unaryMath(call, abs)
        case "SQRT":
            guard let value = call.number(0) else { return .failure(.valueError) }
            return value < 0 ? .failure(.numberError) : .number(sqrt(value))
        case "EXP": return unaryMath(call, exp)
        case "LN":
            guard let value = call.number(0) else { return .failure(.valueError) }
            return value <= 0 ? .failure(.numberError) : .number(log(value))
        case "LOG10": return logarithm(call, base: 10)
        case "LOG": return logarithm(call, base: call.count >= 2 ? call.number(1) ?? 10 : 10)
        case "SIGN":
            guard let value = call.number(0) else { return .failure(.valueError) }
            return .number(value > 0 ? 1 : (value < 0 ? -1 : 0))
        case "INT": return unaryMath(call) { $0.rounded(.down) }
        case "TRUNC": return roundingFunction(call, rule: .towardZero)
        case "ROUND": return roundingFunction(call, rule: .toNearestOrAwayFromZero)
        case "ROUNDUP": return roundingFunction(call, rule: .awayFromZero)
        case "ROUNDDOWN": return roundingFunction(call, rule: .towardZero)
        case "MOD":
            guard let a = call.number(0), let b = call.number(1) else { return .failure(.valueError) }
            guard b != 0 else { return .failure(.divideByZero) }
            return .number(a - b * (a / b).rounded(.down))
        case "POWER":
            guard let a = call.number(0), let b = call.number(1) else { return .failure(.valueError) }
            let result = pow(a, b)
            return result.isFinite ? .number(result) : .failure(.numberError)
        case "CEILING", "FLOOR":
            guard let value = call.number(0) else { return .failure(.valueError) }
            let step = call.count >= 2 ? (call.number(1) ?? 1) : 1
            guard step != 0 else { return .failure(.divideByZero) }
            let quotient = value / step
            return .number(step * (call.name == "CEILING" ? quotient.rounded(.up) : quotient.rounded(.down)))
        case "PI": return .number(.pi)
        case "RADIANS": return unaryMath(call) { $0 * .pi / 180 }
        case "DEGREES": return unaryMath(call) { $0 * 180 / .pi }
        case "COS": return unaryMath(call, cos)
        case "SIN": return unaryMath(call, sin)
        case "TAN": return unaryMath(call, tan)
        case "ACOS": return unaryMath(call, acos)
        case "ASIN": return unaryMath(call, asin)
        case "ATAN": return unaryMath(call, atan)
        case "ATAN2":
            guard let x = call.number(0), let y = call.number(1) else { return .failure(.valueError) }
            return .number(atan2(y, x))
        case "RAND": return .number(Double.random(in: 0..<1))
        case "RANDBETWEEN":
            guard let low = call.number(0), let high = call.number(1), low <= high else {
                return .failure(.numberError)
            }
            return .number(Double(Int.random(in: Int(low)...Int(high))))

        // MARK: Text
        case "CONCAT", "CONCATENATE":
            return .text(call.allValues.map(\.stringValue).joined())
        case "TEXTJOIN":
            return textJoin(call)
        case "LEN": return .number(Double(call.string(0).count))
        case "LOWER": return .text(call.string(0).lowercased())
        case "UPPER": return .text(call.string(0).uppercased())
        case "PROPER": return .text(call.string(0).capitalized)
        case "TRIM":
            let collapsed = call.string(0).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            return .text(collapsed)
        case "LEFT", "RIGHT":
            let text = call.string(0)
            let count = call.count >= 2 ? Int(call.number(1) ?? 1) : 1
            guard count >= 0 else { return .failure(.valueError) }
            return .text(call.name == "LEFT" ? String(text.prefix(count)) : String(text.suffix(count)))
        case "MID":
            let characters = Array(call.string(0))
            guard let start = call.number(1), let length = call.number(2), start >= 1, length >= 0 else {
                return .failure(.valueError)
            }
            let from = min(max(0, Int(start) - 1), characters.count)
            let to = min(from + Int(length), characters.count)
            return .text(String(characters[from..<to]))
        case "REPT":
            guard let times = call.number(1), times >= 0 else { return .failure(.valueError) }
            return .text(String(repeating: call.string(0), count: min(Int(times), 10_000)))
        case "EXACT":
            return .boolean(call.string(0) == call.string(1))
        case "FIND", "SEARCH":
            let needle = call.string(0)
            let haystack = call.string(1)
            let start = call.count >= 3 ? max(1, Int(call.number(2) ?? 1)) : 1
            guard start <= haystack.count + 1 else { return .failure(.valueError) }
            let searchStart = haystack.index(haystack.startIndex, offsetBy: start - 1)
            let options: String.CompareOptions = call.name == "SEARCH" ? [.caseInsensitive] : []
            guard !needle.isEmpty else { return .number(Double(start)) }
            guard let found = haystack.range(of: needle, options: options,
                                             range: searchStart..<haystack.endIndex) else {
                return .failure(.valueError)
            }
            return .number(Double(haystack.distance(from: haystack.startIndex, to: found.lowerBound) + 1))
        case "SUBSTITUTE":
            let text = call.string(0)
            let old = call.string(1)
            let new = call.string(2)
            guard !old.isEmpty else { return .text(text) }
            if call.count >= 4, let occurrence = call.number(3) {
                return .text(replace(text, old, new, occurrence: Int(occurrence)))
            }
            return .text(text.replacingOccurrences(of: old, with: new))
        case "REPLACE":
            let characters = Array(call.string(0))
            guard let start = call.number(1), let length = call.number(2), start >= 1 else {
                return .failure(.valueError)
            }
            let from = min(Int(start) - 1, characters.count)
            let to = min(from + max(0, Int(length)), characters.count)
            return .text(String(characters[0..<from]) + call.string(3) + String(characters[to...]))
        case "TEXT":
            return .text(CellFormatter.displayText(for: call.scalar(0), format: call.string(1)))
        case "VALUE":
            let trimmed = call.string(0).trimmingCharacters(in: .whitespaces)
            guard let number = Double(trimmed) else { return .failure(.valueError) }
            return .number(number)
        case "CHAR":
            guard let code = call.number(0), let scalar = UnicodeScalar(UInt32(max(0, code))) else {
                return .failure(.valueError)
            }
            return .text(String(Character(scalar)))
        case "CODE":
            guard let scalar = call.string(0).unicodeScalars.first else { return .failure(.valueError) }
            return .number(Double(scalar.value))

        // MARK: Dates
        case "TODAY":
            return .number(CellFormatter.serial(fromDate: Date()).rounded(.down))
        case "NOW":
            return .number(CellFormatter.serial(fromDate: Date()))
        case "DATE":
            guard let year = call.number(0), let month = call.number(1), let day = call.number(2) else {
                return .failure(.valueError)
            }
            var components = DateComponents()
            components.year = Int(year)
            components.month = Int(month)
            components.day = Int(day)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            guard let date = calendar.date(from: components) else { return .failure(.numberError) }
            return .number(CellFormatter.serial(fromDate: date).rounded(.down))
        case "TIME":
            guard let hour = call.number(0), let minute = call.number(1), let second = call.number(2) else {
                return .failure(.valueError)
            }
            return .number((hour * 3600 + minute * 60 + second) / 86_400)
        case "YEAR", "MONTH", "DAY", "HOUR", "MINUTE", "SECOND", "WEEKDAY":
            guard let serial = call.number(0) else { return .failure(.valueError) }
            return .number(Double(datePart(call.name, serial: serial)))

        // MARK: Lookup
        case "CHOOSE":
            guard let index = call.number(0) else { return .failure(.valueError) }
            let position = Int(index)
            guard position >= 1, position < call.count else { return .failure(.valueError) }
            return call.value(position)
        case "INDEX":
            guard case .matrix(let rows) = call.value(0) else { return call.value(0) }
            let rowIndex = Int(call.number(1) ?? 1)
            let columnIndex = call.count >= 3 ? Int(call.number(2) ?? 1) : 1
            // A single-row or single-column range accepts one index.
            if call.count == 2, rows.count == 1 {
                guard rowIndex >= 1, rowIndex <= (rows.first?.count ?? 0) else { return .failure(.referenceError) }
                return .scalar(rows[0][rowIndex - 1])
            }
            guard rowIndex >= 1, rowIndex <= rows.count,
                  columnIndex >= 1, columnIndex <= rows[rowIndex - 1].count else {
                return .failure(.referenceError)
            }
            return .scalar(rows[rowIndex - 1][columnIndex - 1])
        case "MATCH":
            return match(call)
        case "VLOOKUP", "HLOOKUP":
            return lookup(call)
        case "XLOOKUP":
            return crossLookup(call)

        default:
            return .failure(.nameError)
        }
    }

    // MARK: - Shared helpers

    private static func aggregate(_ call: CallFrame, _ reduce: ([Double]) -> Double) -> FormulaValue {
        if let error = call.propagatedError { return .failure(error) }
        return .number(reduce(call.numbers))
    }

    private static func unaryMath(_ call: CallFrame, _ transform: (Double) -> Double) -> FormulaValue {
        guard let value = call.number(0) else { return .failure(.valueError) }
        let result = transform(value)
        return result.isFinite ? .number(result) : .failure(.numberError)
    }

    private static func logarithm(_ call: CallFrame, base: Double?) -> FormulaValue {
        guard let value = call.number(0), let base, value > 0, base > 0, base != 1 else {
            return .failure(.numberError)
        }
        return .number(log(value) / log(base))
    }

    private static func roundingFunction(_ call: CallFrame, rule: FloatingPointRoundingRule) -> FormulaValue {
        guard let value = call.number(0) else { return .failure(.valueError) }
        let places = call.count >= 2 ? Int(call.number(1) ?? 0) : 0
        let factor = pow(10.0, Double(places))
        guard factor.isFinite, factor != 0 else { return .failure(.numberError) }
        return .number((value * factor).rounded(rule) / factor)
    }

    private static func replace(_ text: String, _ old: String, _ new: String, occurrence: Int) -> String {
        guard occurrence >= 1 else { return text }
        var result = text
        var searchStart = result.startIndex
        var seen = 0
        while let found = result.range(of: old, range: searchStart..<result.endIndex) {
            seen += 1
            if seen == occurrence {
                result.replaceSubrange(found, with: new)
                return result
            }
            searchStart = found.upperBound
        }
        return result
    }

    private static func datePart(_ name: String, serial: Double) -> Int {
        let date = CellFormatter.date(fromSerial: serial)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        switch name {
        case "YEAR": return parts.year ?? 1900
        case "MONTH": return parts.month ?? 1
        case "DAY": return parts.day ?? 1
        case "HOUR": return parts.hour ?? 0
        case "MINUTE": return parts.minute ?? 0
        case "SECOND": return parts.second ?? 0
        default: return parts.weekday ?? 1
        }
    }

    // MARK: - Criteria

    /// Parses `">=10"`, `"<>x"`, `"apple"` and applies it to a candidate value.
    private struct Criterion {
        var symbol: String
        var comparand: CellValue

        init(_ raw: CellValue) {
            guard case .text(let text) = raw else {
                symbol = "="
                comparand = raw
                return
            }
            let operators = ["<=", ">=", "<>", "<", ">", "="]
            if let found = operators.first(where: { text.hasPrefix($0) }) {
                symbol = found
                let remainder = String(text.dropFirst(found.count))
                comparand = Double(remainder).map(CellValue.number) ?? .text(remainder)
            } else {
                symbol = "="
                comparand = Double(text).map(CellValue.number) ?? .text(text)
            }
        }

        func matches(_ candidate: CellValue) -> Bool {
            if case .text(let pattern) = comparand, symbol == "=" || symbol == "<>" {
                let equal = candidate.stringValue.compare(pattern, options: .caseInsensitive) == .orderedSame
                return symbol == "=" ? equal : !equal
            }
            guard let a = candidate.numericValue, let b = comparand.numericValue else {
                let equal = candidate.stringValue == comparand.stringValue
                return symbol == "<>" ? !equal : (symbol == "=" && equal)
            }
            switch symbol {
            case "=": return a == b
            case "<>": return a != b
            case "<": return a < b
            case ">": return a > b
            case "<=": return a <= b
            default: return a >= b
            }
        }
    }

    private static func conditionalAggregate(_ call: CallFrame) -> FormulaValue {
        guard call.count >= 2 else { return .failure(.valueError) }
        let testRange = call.value(0).flattened
        let criterion = Criterion(call.scalar(1))

        if call.name == "COUNTIF" {
            return .number(Double(testRange.filter { criterion.matches($0) }.count))
        }

        // SUMIF/AVERAGEIF may total a parallel range instead of the tested one.
        let sumRange = call.count >= 3 ? call.value(2).flattened : testRange
        var collected: [Double] = []
        for (position, candidate) in testRange.enumerated() where criterion.matches(candidate) {
            guard position < sumRange.count, let number = sumRange[position].numericValue else { continue }
            collected.append(number)
        }
        if call.name == "SUMIF" { return .number(collected.reduce(0, +)) }
        guard !collected.isEmpty else { return .failure(.divideByZero) }
        return .number(collected.reduce(0, +) / Double(collected.count))
    }

    /// `SUMIFS`, `AVERAGEIFS` and `COUNTIFS`. Unlike `SUMIF`, the aggregated range
    /// comes first and every criteria pair must match for a position to count.
    private static func multiCriteriaAggregate(_ call: CallFrame) -> FormulaValue {
        let counting = call.name == "COUNTIFS"
        let firstPair = counting ? 0 : 1
        guard call.count >= firstPair + 2, (call.count - firstPair) % 2 == 0 else {
            return .failure(.valueError)
        }

        var tests: [(values: [CellValue], criterion: Criterion)] = []
        var index = firstPair
        while index + 1 < call.count {
            tests.append((call.value(index).flattened, Criterion(call.scalar(index + 1))))
            index += 2
        }
        // Excel requires every criteria range to have the same shape.
        guard let width = tests.first?.values.count,
              tests.allSatisfy({ $0.values.count == width }) else { return .failure(.valueError) }

        let aggregated = counting ? [] : call.value(0).flattened
        guard counting || aggregated.count == width else { return .failure(.valueError) }

        var matched = 0
        var collected: [Double] = []
        for position in 0..<width where tests.allSatisfy({ $0.criterion.matches($0.values[position]) }) {
            matched += 1
            guard !counting, !aggregated[position].isEmpty,
                  let number = aggregated[position].numericValue else { continue }
            collected.append(number)
        }

        switch call.name {
        case "COUNTIFS": return .number(Double(matched))
        case "SUMIFS": return .number(collected.reduce(0, +))
        default:
            guard !collected.isEmpty else { return .failure(.divideByZero) }
            return .number(collected.reduce(0, +) / Double(collected.count))
        }
    }

    // MARK: - Text assembly

    /// `TEXTJOIN(delimiter, ignore_empty, text1, …)`, expanding ranges in order.
    private static func textJoin(_ call: CallFrame) -> FormulaValue {
        guard call.count >= 2 else { return .failure(.valueError) }
        if let error = call.propagatedError { return .failure(error) }
        let delimiter = call.string(0)
        let skipsBlanks = call.boolean(1)
        var pieces: [String] = []
        for index in 2..<call.count {
            for value in call.value(index).flattened {
                let text = value.stringValue
                // A formula that produced "" reads as blank here, just as a blank cell does.
                if skipsBlanks, text.isEmpty { continue }
                pieces.append(text)
            }
        }
        return .text(pieces.joined(separator: delimiter))
    }

    // MARK: - Logic

    /// `SWITCH(expression, value1, result1, …, [default])`.
    private static func switchCase(_ call: CallFrame) -> FormulaValue {
        guard call.count >= 3 else { return .failure(.valueError) }
        let subject = call.scalar(0)
        if let error = subject.errorValue { return .failure(error) }

        var index = 1
        while index + 1 < call.count {
            if let error = call.scalar(index).errorValue { return .failure(error) }
            if sameValue(call.scalar(index), subject) { return call.value(index + 1) }
            index += 2
        }
        // A leftover trailing argument is the default result.
        let hasDefault = (call.count - 1) % 2 == 1
        return hasDefault ? call.value(call.count - 1) : .failure(.notAvailable)
    }

    // MARK: - Lookup

    /// Equality as the exact-match lookups define it: text comparison, ignoring case.
    private static func sameValue(_ lhs: CellValue, _ rhs: CellValue) -> Bool {
        lhs.stringValue.compare(rhs.stringValue, options: .caseInsensitive) == .orderedSame
    }

    /// `XLOOKUP(lookup_value, lookup_array, return_array, [if_not_found], [match_mode])`.
    /// Only exact matching (mode 0) is supported; other modes report `#VALUE!`
    /// rather than quietly returning a neighbouring row.
    private static func crossLookup(_ call: CallFrame) -> FormulaValue {
        guard call.count >= 3 else { return .failure(.valueError) }
        guard call.count < 5 || Int(call.number(4) ?? 0) == 0 else { return .failure(.valueError) }

        let needle = call.scalar(0)
        if let error = needle.errorValue { return .failure(error) }
        let keys = call.value(1).flattened
        let results = call.value(2).flattened
        guard keys.count == results.count else { return .failure(.valueError) }

        for (position, candidate) in keys.enumerated() where sameValue(candidate, needle) {
            return .scalar(results[position])
        }
        return call.count >= 4 ? call.value(3) : .failure(.notAvailable)
    }

    private static func match(_ call: CallFrame) -> FormulaValue {
        guard call.count >= 2 else { return .failure(.valueError) }
        let needle = call.scalar(0)
        let haystack = call.value(1).flattened
        let mode = call.count >= 3 ? Int(call.number(2) ?? 1) : 1

        if mode == 0 {
            for (position, candidate) in haystack.enumerated()
            where candidate.stringValue.compare(needle.stringValue, options: .caseInsensitive) == .orderedSame {
                return .number(Double(position + 1))
            }
            return .failure(.notAvailable)
        }

        guard let target = needle.numericValue else { return .failure(.notAvailable) }
        var best: Int?
        for (position, candidate) in haystack.enumerated() {
            guard let value = candidate.numericValue else { continue }
            if mode > 0, value <= target { best = position }
            if mode < 0, value >= target { best = position }
        }
        guard let best else { return .failure(.notAvailable) }
        return .number(Double(best + 1))
    }

    private static func lookup(_ call: CallFrame) -> FormulaValue {
        guard call.count >= 3, case .matrix(let rows) = call.value(1) else { return .failure(.valueError) }
        let needle = call.scalar(0)
        let offset = Int(call.number(2) ?? 1)
        let approximate = call.count >= 4 ? call.boolean(3) : true
        let isVertical = call.name == "VLOOKUP"

        // Normalize so the search always runs down `keys`.
        let keys: [CellValue] = isVertical ? rows.map { $0.first ?? .empty } : (rows.first ?? [])
        guard offset >= 1 else { return .failure(.valueError) }

        func result(at position: Int) -> FormulaValue {
            if isVertical {
                guard position < rows.count, offset <= rows[position].count else { return .failure(.referenceError) }
                return .scalar(rows[position][offset - 1])
            }
            guard offset <= rows.count, position < rows[offset - 1].count else { return .failure(.referenceError) }
            return .scalar(rows[offset - 1][position])
        }

        if !approximate {
            for (position, candidate) in keys.enumerated()
            where candidate.stringValue.compare(needle.stringValue, options: .caseInsensitive) == .orderedSame {
                return result(at: position)
            }
            return .failure(.notAvailable)
        }

        guard let target = needle.numericValue else {
            for (position, candidate) in keys.enumerated()
            where candidate.stringValue.compare(needle.stringValue, options: .caseInsensitive) == .orderedSame {
                return result(at: position)
            }
            return .failure(.notAvailable)
        }
        var best: Int?
        for (position, candidate) in keys.enumerated() {
            guard let value = candidate.numericValue else { continue }
            if value <= target { best = position } else { break }
        }
        guard let best else { return .failure(.notAvailable) }
        return result(at: best)
    }
}
