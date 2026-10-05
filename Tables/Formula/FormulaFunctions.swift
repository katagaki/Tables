import Foundation

/// The built-in function library.
///
/// Each function is a `FunctionSpec` in one of the category tables, which
/// `registry` merges. A function receives its arguments unevaluated, through a
/// `FunctionCall`, so that `IF`, `IFERROR` and friends can decide what to
/// evaluate, and so that functions such as `ROWS` and `OFFSET` can see the
/// reference an argument names rather than only its values.
enum FormulaFunctions {
    static let registry: [String: FunctionSpec] = {
        var all: [String: FunctionSpec] = [:]
        for table in [
            mathFunctions, trigonometryFunctions, arithmeticFunctions, statisticalFunctions, descriptiveFunctions, distributionFunctions, subtotalFunctions, logicalFunctions, informationFunctions, textFunctions, textExtendedFunctions,
            dateFunctions, lookupFunctions,
        ] {
            all.merge(table) { existing, _ in existing }
        }
        return all
    }()

    /// Every function name, sorted, for the function picker.
    static let names: [String] = registry.keys.sorted()

    /// Whether a function name is one the library evaluates.
    static func isKnown(_ name: String) -> Bool { registry[name.uppercased()] != nil }

    // MARK: - Dispatch

    static func call(_ name: String, arguments: [FormulaNode], evaluator: FormulaEvaluator) -> FormulaValue {
        guard let spec = registry[name] else { return .failure(.nameError) }
        guard spec.arity.contains(arguments.count) else { return .failure(.valueError) }
        let call = FunctionCall(name: name, nodes: arguments, evaluator: evaluator)

        // Arguments a function reads as single values are spread over arrays:
        // `LEN(A1:A3)` is three lengths.
        let lifted = arguments.indices.filter { spec.lifts.contains($0) && arguments[$0] != .missing }
        let arrays = lifted.filter { call.value($0).isArray }
        guard !arrays.isEmpty else { return run(spec, call) }

        let blocks = Dictionary(uniqueKeysWithValues: arrays.map { ($0, call.value($0).rows) })
        let height = blocks.values.map(\.count).max() ?? 1
        let width = blocks.values.map { $0.first?.count ?? 0 }.max() ?? 1
        var rows: [[CellValue]] = []
        for row in 0..<height {
            var line: [CellValue] = []
            for column in 0..<width {
                let element = call.copy()
                var outside = false
                for (index, block) in blocks {
                    let r = block.count == 1 ? 0 : row
                    let c = (block.first?.count ?? 0) == 1 ? 0 : column
                    guard r < block.count, c < (block.first?.count ?? 0) else { outside = true; break }
                    element.preset(index, .scalar(block[r][c]))
                }
                line.append(outside ? .error(.notAvailable) : run(spec, element).single)
            }
            rows.append(line)
        }
        return .block(rows)
    }

    private static func run(_ spec: FunctionSpec, _ call: FunctionCall) -> FormulaValue {
        do {
            return try spec.body(call)
        } catch {
            return .failure(error)
        }
    }

    /// The reference a call returns, for the functions that return references.
    static func reference(_ name: String, arguments: [FormulaNode], evaluator: FormulaEvaluator) -> FormulaReference? {
        guard let spec = registry[name], let referenceBody = spec.referenceBody,
              spec.arity.contains(arguments.count) else { return nil }
        return try? referenceBody(FunctionCall(name: name, nodes: arguments, evaluator: evaluator))
    }
}

// MARK: - Specs

/// Which argument positions a function reads as single values, and so spreads
/// over when given an array.
enum Lifting: Sendable {
    case none
    case all
    case only(Set<Int>)
    case allExcept(Set<Int>)
    /// Every position satisfying a rule, such as the criteria of `SUMIFS`.
    case matching(@Sendable (Int) -> Bool)

    func contains(_ index: Int) -> Bool {
        switch self {
        case .none: return false
        case .all: return true
        case .only(let set): return set.contains(index)
        case .allExcept(let set): return !set.contains(index)
        case .matching(let rule): return rule(index)
        }
    }
}

struct FunctionSpec: Sendable {
    typealias Body = @Sendable (FunctionCall) throws(CellError) -> FormulaValue
    typealias ReferenceBody = @Sendable (FunctionCall) throws(CellError) -> FormulaReference

    var arity: ClosedRange<Int>
    var lifts: Lifting
    var body: Body
    /// Set for functions that can answer with a reference, such as `OFFSET`,
    /// so that `ROWS(OFFSET(…))` and `A1:INDEX(…)` see cells, not values.
    var referenceBody: ReferenceBody?

    init(_ arity: ClosedRange<Int>, lifts: Lifting = .all, _ body: @escaping Body) {
        self.arity = arity
        self.lifts = lifts
        self.body = body
    }

    /// A function that always answers with a reference; its value is read out of it.
    init(_ arity: ClosedRange<Int>, lifts: Lifting = .none, reference: @escaping ReferenceBody) {
        self.arity = arity
        self.lifts = lifts
        self.body = { call throws(CellError) in call.evaluator.materialize(try reference(call)) }
        self.referenceBody = reference
    }

    /// A function that answers with a reference when its arguments allow and a
    /// value otherwise, as `INDEX` does for a range and for an array.
    init(_ arity: ClosedRange<Int>, lifts: Lifting = .none, reference: @escaping ReferenceBody,
         value: @escaping Body) {
        self.arity = arity
        self.lifts = lifts
        self.body = value
        self.referenceBody = reference
    }

    /// A function of one number.
    static func unary(_ transform: @escaping @Sendable (Double) throws(CellError) -> Double) -> FunctionSpec {
        FunctionSpec(1...1) { call throws(CellError) in .number(try transform(try call.number(0))) }
    }

    /// A function of two numbers.
    static func binary(_ transform: @escaping @Sendable (Double, Double) throws(CellError) -> Double) -> FunctionSpec {
        FunctionSpec(2...2) { call throws(CellError) in .number(try transform(try call.number(0), try call.number(1))) }
    }

    /// A function with no arguments.
    static func constant(_ value: @escaping @Sendable () -> FormulaValue) -> FunctionSpec {
        FunctionSpec(0...0) { _ throws(CellError) in value() }
    }
}

extension FormulaValue {
    /// More than one cell.
    var isArray: Bool {
        if case .matrix(let rows) = self { return rows.count > 1 || (rows.first?.count ?? 0) > 1 }
        return false
    }

    /// An array of any size, a 1×1 one from `{5}` included.
    var isMatrix: Bool {
        if case .matrix = self { return true }
        return false
    }
}

// MARK: - Calls

/// One invocation of a function: its argument nodes, evaluated on demand and
/// at most once each.
final class FunctionCall {
    let name: String
    let nodes: [FormulaNode]
    let evaluator: FormulaEvaluator
    private var values: [Int: FormulaValue] = [:]
    private var references: [Int: FormulaReference?] = [:]

    init(name: String, nodes: [FormulaNode], evaluator: FormulaEvaluator) {
        self.name = name
        self.nodes = nodes
        self.evaluator = evaluator
    }

    /// A call sharing what has been evaluated so far, for one element of a
    /// lifted call.
    func copy() -> FunctionCall {
        let copy = FunctionCall(name: name, nodes: nodes, evaluator: evaluator)
        copy.values = values
        copy.references = references
        return copy
    }

    /// Replaces an argument's value, as lifting does with each element.
    func preset(_ index: Int, _ value: FormulaValue) {
        values[index] = value
        references[index] = .some(nil)
    }

    var count: Int { nodes.count }

    var context: any FormulaContext { evaluator.context }

    /// Whether an argument was left out, either past the end or empty.
    func isMissing(_ index: Int) -> Bool {
        index >= nodes.count || nodes[index] == .missing
    }

    func value(_ index: Int) -> FormulaValue {
        guard index < nodes.count else { return .scalar(.empty) }
        if let cached = values[index] { return cached }
        let value: FormulaValue
        if let reference = reference(index) {
            value = evaluator.materialize(reference)
        } else {
            value = evaluator.evaluate(nodes[index])
        }
        values[index] = value
        return value
    }

    /// The reference an argument names, when it names one.
    func reference(_ index: Int) -> FormulaReference? {
        guard index < nodes.count else { return nil }
        if let cached = references[index] { return cached }
        let reference = evaluator.reference(nodes[index])
        references[index] = .some(reference)
        return reference
    }

    /// Whether an argument names cells rather than computing a value. Excel
    /// treats the text and booleans in a referenced range differently from the
    /// same values typed straight into the call.
    func isReference(_ index: Int) -> Bool {
        if reference(index) != nil { return true }
        if index < nodes.count, case .sheetSpan = nodes[index] { return true }
        return false
    }

    /// One value. A multi-cell reference gives the cell in line with the
    /// formula, the way a range collapses wherever one value is wanted.
    func scalar(_ index: Int) -> CellValue {
        let value = value(index)
        guard value.isArray else { return value.single }
        if let reference = reference(index), let cell = evaluator.intersection(of: reference) {
            return evaluator.materialize(cell).single
        }
        return value.single
    }

    func number(_ index: Int) throws(CellError) -> Double {
        let number = try scalar(index).coercedNumber()
        guard number.isFinite else { throw .numberError }
        return number
    }

    func number(_ index: Int, default fallback: Double) throws(CellError) -> Double {
        isMissing(index) ? fallback : try number(index)
    }

    /// A whole number, truncated toward zero as Excel truncates count and
    /// position arguments.
    func integer(_ index: Int) throws(CellError) -> Int {
        let value = try number(index).rounded(.towardZero)
        guard abs(value) < 1e15 else { throw .numberError }
        return Int(value)
    }

    func integer(_ index: Int, default fallback: Int) throws(CellError) -> Int {
        isMissing(index) ? fallback : try integer(index)
    }

    func text(_ index: Int) throws(CellError) -> String {
        try scalar(index).coercedText()
    }

    func text(_ index: Int, default fallback: String) throws(CellError) -> String {
        isMissing(index) ? fallback : try text(index)
    }

    func boolean(_ index: Int) throws(CellError) -> Bool {
        try scalar(index).coercedBoolean()
    }

    func boolean(_ index: Int, default fallback: Bool) throws(CellError) -> Bool {
        isMissing(index) ? fallback : try boolean(index)
    }

    /// An argument as rows of cells; a single value is a 1×1 block.
    func matrix(_ index: Int) throws(CellError) -> [[CellValue]] {
        let value = value(index)
        if case .lambda = value { throw .valueError }
        if case .scalar(.error(let error)) = value { throw error }
        return value.rows
    }

    func lambda(_ index: Int) throws(CellError) -> FormulaLambda {
        guard case .lambda(let lambda) = value(index) else { throw .valueError }
        return lambda
    }
}

// MARK: - Collecting numbers

/// How aggregates read their arguments.
enum NumberCollection {
    /// `SUM`, `AVERAGE`, `MAX` and most others: in ranges and arrays only
    /// numbers count; values typed into the call are converted.
    case numbersOnly
    /// The `…A` variants: in ranges, TRUE is 1 and text and FALSE are 0.
    case valuesAsNumbers
}

extension FunctionCall {
    /// The numbers an aggregate works on, from the arguments at `indices`.
    /// Errors stop the collection unless `skippingErrors`.
    func numbers(
        _ indices: some Sequence<Int>, mode: NumberCollection = .numbersOnly, skippingErrors: Bool = false
    ) throws(CellError) -> [Double] {
        var result: [Double] = []
        for index in indices {
            if isMissing(index) {
                if index < count { result.append(0) }
                continue
            }
            let value = value(index)
            if case .lambda = value { throw .valueError }
            if isReference(index) || value.isMatrix {
                for cell in value.flattened {
                    switch cell {
                    case .number(let number): result.append(number)
                    case .error(let error): if !skippingErrors { throw error }
                    case .boolean(let flag): if mode == .valuesAsNumbers { result.append(flag ? 1 : 0) }
                    case .text: if mode == .valuesAsNumbers { result.append(0) }
                    case .empty: break
                    }
                }
            } else {
                let cell = value.single
                if case .error(let error) = cell {
                    if skippingErrors { continue }
                    throw error
                }
                result.append(try cell.coercedNumber())
            }
        }
        return result
    }

    /// Every argument's numbers.
    func allNumbers(mode: NumberCollection = .numbersOnly, skippingErrors: Bool = false) throws(CellError) -> [Double] {
        try numbers(0..<count, mode: mode, skippingErrors: skippingErrors)
    }

    /// The cells of every argument from `start` on, ranges expanded in order.
    func cells(from start: Int = 0) throws(CellError) -> [CellValue] {
        var result: [CellValue] = []
        for index in start..<max(start, count) {
            result += try matrix(index).flatMap { $0 }
        }
        return result
    }
}

// MARK: - Criteria

/// A `COUNTIF`-style condition: `">=10"`, `"<>x"`, `"app*"`, `5`, `TRUE`.
struct FormulaCriterion {
    private enum Comparand {
        case number(Double)
        case text(String)
        case boolean(Bool)
        case error(CellError)
        case blank
    }

    private let symbol: String
    private let comparand: Comparand
    /// A bare `""` matches blank cells and empty text alike; `"="` matches
    /// only the blank ones.
    private let matchesEmptyText: Bool

    init(_ raw: CellValue) {
        guard case .text(let text) = raw else {
            symbol = "="
            matchesEmptyText = false
            switch raw {
            case .number(let number): comparand = .number(number)
            case .boolean(let flag): comparand = .boolean(flag)
            case .error(let error): comparand = .error(error)
            default: comparand = .number(0)
            }
            return
        }
        let operators = ["<=", ">=", "<>", "<", ">", "="]
        let found = operators.first(where: { text.hasPrefix($0) })
        symbol = found ?? "="
        let rest = String(text.dropFirst(found?.count ?? 0))
        matchesEmptyText = found == nil && rest.isEmpty
        if rest.isEmpty {
            comparand = .blank
        } else if let number = FormulaValueParser.number(from: rest) {
            comparand = .number(number)
        } else if rest.caseInsensitiveCompare("TRUE") == .orderedSame {
            comparand = .boolean(true)
        } else if rest.caseInsensitiveCompare("FALSE") == .orderedSame {
            comparand = .boolean(false)
        } else if let error = CellError.allCases.first(where: { $0.rawValue == rest.uppercased() }) {
            comparand = .error(error)
        } else {
            comparand = .text(rest)
        }
    }

    func matches(_ candidate: CellValue) -> Bool {
        switch comparand {
        case .blank:
            let equal: Bool
            switch candidate {
            case .empty: equal = true
            case .text(let text): equal = matchesEmptyText && text.isEmpty
            default: equal = false
            }
            return symbol == "<>" ? !equal : (symbol == "=" && equal)

        case .number(let target):
            let actual: Double?
            switch candidate {
            case .number(let number): actual = number
            // Text that reads as the number counts as equal, not as ordered.
            case .text(let text) where symbol == "=" || symbol == "<>":
                actual = Double(text.trimmingCharacters(in: .whitespaces))
            default: actual = nil
            }
            guard let actual else { return symbol == "<>" }
            return Self.ordered(FormulaComparison.compareNumbers(actual, target), symbol)

        case .boolean(let target):
            guard case .boolean(let actual) = candidate else { return symbol == "<>" }
            return Self.ordered(FormulaComparison.compareNumbers(actual ? 1 : 0, target ? 1 : 0), symbol)

        case .error(let target):
            let equal = candidate.errorValue == target
            return symbol == "<>" ? !equal : (symbol == "=" && equal)

        case .text(let pattern):
            if symbol == "=" || symbol == "<>" {
                var equal = false
                if case .text(let text) = candidate { equal = FormulaWildcard.matches(text, pattern: pattern) }
                return symbol == "=" ? equal : !equal
            }
            guard case .text(let text) = candidate else { return false }
            return Self.ordered(FormulaComparison.compareText(text, pattern), symbol)
        }
    }

    private static func ordered(_ ordering: ComparisonResult, _ symbol: String) -> Bool {
        switch symbol {
        case "=": return ordering == .orderedSame
        case "<>": return ordering != .orderedSame
        case "<": return ordering == .orderedAscending
        case ">": return ordering == .orderedDescending
        case "<=": return ordering != .orderedDescending
        default: return ordering != .orderedAscending
        }
    }
}

// MARK: - Wildcards

/// Excel's wildcard patterns: `*` for any run of characters, `?` for any one,
/// and `~` to take the next character literally. Matching ignores case.
enum FormulaWildcard {
    static func matches(_ text: String, pattern: String) -> Bool {
        let candidate = Array(text.lowercased())
        var tokens: [(character: Character, isWildcard: Bool)] = []
        var escaping = false
        for character in pattern.lowercased() {
            if escaping {
                tokens.append((character, false))
                escaping = false
            } else if character == "~" {
                escaping = true
            } else {
                tokens.append((character, character == "*" || character == "?"))
            }
        }
        if escaping { tokens.append(("~", false)) }

        // Greedy matching that backtracks to the last `*`.
        var t = 0
        var p = 0
        var star: Int?
        var mark = 0
        while t < candidate.count {
            if p < tokens.count, tokens[p].isWildcard, tokens[p].character == "*" {
                star = p
                mark = t
                p += 1
            } else if p < tokens.count,
                      (tokens[p].isWildcard && tokens[p].character == "?") || tokens[p].character == candidate[t] {
                t += 1
                p += 1
            } else if let star {
                p = star + 1
                mark += 1
                t = mark
            } else {
                return false
            }
        }
        while p < tokens.count, tokens[p].isWildcard, tokens[p].character == "*" { p += 1 }
        return p == tokens.count
    }

    /// Whether a pattern uses any wildcard at all.
    static func hasWildcards(_ pattern: String) -> Bool {
        pattern.contains("*") || pattern.contains("?") || pattern.contains("~")
    }
}
