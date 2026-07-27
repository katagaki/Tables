import Foundation

enum FormulaToken: Hashable, Sendable {
    case number(Double)
    case string(String)
    /// A bare word: a function name, a cell reference, a sheet name, or a constant.
    case identifier(String)
    /// A quoted sheet name, as in `'Q1 Sales'!A1`.
    case quotedName(String)
    case op(String)
    case leftParenthesis
    case rightParenthesis
    case leftBrace
    case rightBrace
    case comma
    case semicolon
    case colon
    case bang
    case percent
}

struct FormulaLexError: Error, Sendable {
    var message: String
}

/// Splits a formula body (everything after the leading `=`) into tokens.
struct FormulaLexer {
    private let characters: [Character]
    private var index = 0

    init(_ source: String) {
        characters = Array(source)
    }

    static func tokenize(_ source: String) throws -> [FormulaToken] {
        var lexer = FormulaLexer(source)
        return try lexer.run()
    }

    private mutating func run() throws -> [FormulaToken] {
        var tokens: [FormulaToken] = []
        while let token = try next() { tokens.append(token) }
        return tokens
    }

    private var current: Character? { index < characters.count ? characters[index] : nil }

    private mutating func next() throws -> FormulaToken? {
        while let character = current, character.isWhitespace { index += 1 }
        guard let character = current else { return nil }

        if character.isNumber || (character == "." && peekIsNumber(at: index + 1)) {
            return readNumber()
        }
        if character == "\"" { return try readString() }
        if character == "'" { return try readQuotedName() }
        if character.isLetter || character == "_" || character == "$" || character == "\\" {
            return readIdentifier()
        }

        index += 1
        switch character {
        case "(": return .leftParenthesis
        case ")": return .rightParenthesis
        case "{": return .leftBrace
        case "}": return .rightBrace
        case ",": return .comma
        case ";": return .semicolon
        case ":": return .colon
        case "!": return .bang
        case "%": return .percent
        case "+", "-", "*", "/", "^", "&", "=": return .op(String(character))
        case "<":
            if current == "=" { index += 1; return .op("<=") }
            if current == ">" { index += 1; return .op("<>") }
            return .op("<")
        case ">":
            if current == "=" { index += 1; return .op(">=") }
            return .op(">")
        default:
            throw FormulaLexError(message: "Unexpected character “\(character)”")
        }
    }

    private func peekIsNumber(at position: Int) -> Bool {
        position < characters.count && characters[position].isNumber
    }

    private mutating func readNumber() -> FormulaToken {
        var text = ""
        while let character = current, character.isNumber || character == "." {
            text.append(character)
            index += 1
        }
        // Scientific notation, e.g. 1.2E-3.
        if let character = current, character == "e" || character == "E" {
            let save = index
            var candidate = String(character)
            index += 1
            if let sign = current, sign == "+" || sign == "-" {
                candidate.append(sign)
                index += 1
            }
            if let digit = current, digit.isNumber {
                while let digit = current, digit.isNumber {
                    candidate.append(digit)
                    index += 1
                }
                text += candidate
            } else {
                index = save
            }
        }
        return .number(Double(text) ?? 0)
    }

    private mutating func readString() throws -> FormulaToken {
        index += 1  // opening quote
        var text = ""
        while let character = current {
            index += 1
            if character == "\"" {
                if current == "\"" {  // escaped quote
                    text.append("\"")
                    index += 1
                    continue
                }
                return .string(text)
            }
            text.append(character)
        }
        throw FormulaLexError(message: "Unterminated text literal")
    }

    private mutating func readQuotedName() throws -> FormulaToken {
        index += 1
        var text = ""
        while let character = current {
            index += 1
            if character == "'" {
                if current == "'" {
                    text.append("'")
                    index += 1
                    continue
                }
                return .quotedName(text)
            }
            text.append(character)
        }
        throw FormulaLexError(message: "Unterminated sheet name")
    }

    private mutating func readIdentifier() -> FormulaToken {
        var text = ""
        while let character = current,
              character.isLetter || character.isNumber || character == "_" || character == "."
                || character == "$" {
            text.append(character)
            index += 1
        }
        return .identifier(text)
    }
}
