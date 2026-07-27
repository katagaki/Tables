import Foundation

indirect enum FormulaNode: Hashable, Sendable {
    case number(Double)
    case text(String)
    case boolean(Bool)
    case errorLiteral(CellError)
    case reference(sheet: String?, address: CellAddress)
    case range(sheet: String?, start: CellAddress, end: CellAddress)
    case unary(String, FormulaNode)
    case binary(String, FormulaNode, FormulaNode)
    case postfixPercent(FormulaNode)
    case call(String, [FormulaNode])
    case array([[FormulaNode]])
}

struct FormulaParseError: Error, Sendable {
    var message: String
}

/// A precedence-climbing parser for the spreadsheet expression grammar.
struct FormulaParser {
    private let tokens: [FormulaToken]
    private var index = 0

    init(tokens: [FormulaToken]) {
        self.tokens = tokens
    }

    static func parse(_ formulaBody: String) throws -> FormulaNode {
        let tokens = try FormulaLexer.tokenize(formulaBody)
        guard !tokens.isEmpty else { throw FormulaParseError(message: "Empty formula") }
        var parser = FormulaParser(tokens: tokens)
        let node = try parser.parseExpression(minimumPrecedence: 0)
        guard parser.index == tokens.count else {
            throw FormulaParseError(message: "Unexpected trailing input")
        }
        return node
    }

    // MARK: - Token helpers

    private var current: FormulaToken? { index < tokens.count ? tokens[index] : nil }

    private mutating func advance() -> FormulaToken? {
        defer { index += 1 }
        return current
    }

    private mutating func expect(_ token: FormulaToken, _ description: String) throws {
        guard current == token else { throw FormulaParseError(message: "Expected \(description)") }
        index += 1
    }

    private static let precedences: [String: Int] = [
        "<": 1, ">": 1, "=": 1, "<=": 1, ">=": 1, "<>": 1,
        "&": 2,
        "+": 3, "-": 3,
        "*": 4, "/": 4,
        "^": 5,
    ]

    // MARK: - Expressions

    private mutating func parseExpression(minimumPrecedence: Int) throws -> FormulaNode {
        var left = try parseUnary()
        while case .op(let symbol)? = current,
              let precedence = Self.precedences[symbol], precedence >= minimumPrecedence {
            index += 1
            // `^` is right-associative; everything else is left-associative.
            let nextMinimum = symbol == "^" ? precedence : precedence + 1
            let right = try parseExpression(minimumPrecedence: nextMinimum)
            left = .binary(symbol, left, right)
        }
        return left
    }

    private mutating func parseUnary() throws -> FormulaNode {
        if case .op(let symbol)? = current, symbol == "-" || symbol == "+" {
            index += 1
            let operand = try parseUnary()
            return symbol == "-" ? .unary("-", operand) : operand
        }
        return try parsePostfix()
    }

    private mutating func parsePostfix() throws -> FormulaNode {
        var node = try parsePrimary()
        while current == .percent {
            index += 1
            node = .postfixPercent(node)
        }
        return node
    }

    private mutating func parsePrimary() throws -> FormulaNode {
        guard let token = advance() else { throw FormulaParseError(message: "Unexpected end of formula") }
        switch token {
        case .number(let value):
            return .number(value)
        case .string(let value):
            return .text(value)
        case .leftParenthesis:
            let inner = try parseExpression(minimumPrecedence: 0)
            try expect(.rightParenthesis, "“)”")
            return inner
        case .leftBrace:
            return try parseArrayLiteral()
        case .quotedName(let sheetName):
            try expect(.bang, "“!” after a sheet name")
            return try parseReference(sheet: sheetName)
        case .identifier(let word):
            return try parseIdentifier(word)
        case .op(let symbol) where symbol == "-":
            return .unary("-", try parseUnary())
        default:
            throw FormulaParseError(message: "Unexpected token in formula")
        }
    }

    private mutating func parseArrayLiteral() throws -> FormulaNode {
        var rows: [[FormulaNode]] = []
        var row: [FormulaNode] = []
        while current != .rightBrace {
            row.append(try parseExpression(minimumPrecedence: 0))
            if current == .comma {
                index += 1
            } else if current == .semicolon {
                index += 1
                rows.append(row)
                row = []
            } else {
                break
            }
        }
        try expect(.rightBrace, "“}”")
        if !row.isEmpty { rows.append(row) }
        return .array(rows)
    }

    private mutating func parseIdentifier(_ word: String) throws -> FormulaNode {
        // A sheet-qualified reference: Sheet1!A1
        if current == .bang {
            index += 1
            return try parseReference(sheet: word)
        }
        // A function call.
        if current == .leftParenthesis {
            index += 1
            var arguments: [FormulaNode] = []
            if current != .rightParenthesis {
                while true {
                    arguments.append(try parseExpression(minimumPrecedence: 0))
                    if current == .comma || current == .semicolon {
                        index += 1
                        continue
                    }
                    break
                }
            }
            try expect(.rightParenthesis, "“)” closing \(word.uppercased())")
            return .call(word.uppercased(), arguments)
        }
        return try makeValueOrReference(word, sheet: nil)
    }

    /// Parses the address portion of a reference once the sheet name is known.
    private mutating func parseReference(sheet: String?) throws -> FormulaNode {
        guard case .identifier(let word)? = advance() else {
            throw FormulaParseError(message: "Expected a cell reference after “!”")
        }
        return try makeValueOrReference(word, sheet: sheet)
    }

    private mutating func makeValueOrReference(_ word: String, sheet: String?) throws -> FormulaNode {
        let upper = word.uppercased()
        if sheet == nil {
            switch upper {
            case "TRUE": return .boolean(true)
            case "FALSE": return .boolean(false)
            default: break
            }
            if let error = CellError.allCases.first(where: { $0.rawValue == upper }) {
                return .errorLiteral(error)
            }
        }

        guard let start = CellAddress(a1: word) else {
            throw FormulaParseError(message: "Unknown name “\(word)”")
        }
        if current == .colon {
            index += 1
            guard case .identifier(let endWord)? = advance(), let end = CellAddress(a1: endWord) else {
                throw FormulaParseError(message: "Malformed range starting at \(word)")
            }
            return .range(sheet: sheet, start: start, end: end)
        }
        return .reference(sheet: sheet, address: start)
    }
}
