import Foundation

/// Rewrites A1-style references inside formula text when rows or columns are
/// inserted or removed. Operates on the raw text so `$` anchors, spacing and
/// unrecognized syntax survive untouched.
enum FormulaReferenceShifter {
    enum Axis { case row, column }

    enum Operation {
        /// `count` lines were inserted starting at zero-based `index`.
        case insert(index: Int, count: Int)
        /// The inclusive zero-based `range` of lines was deleted.
        case remove(range: ClosedRange<Int>)
        /// Every unanchored reference moves by `delta`, as when a formula is
        /// filled from one cell to another.
        case translate(delta: Int)
    }

    /// Rewrites a formula as if it had been filled from one cell to another:
    /// relative references move with it, `$`-anchored ones stay put.
    ///
    /// This is what expands the shared formulas Excel writes for a filled-down
    /// column, where only the first cell carries the text.
    static func translated(
        _ formula: String, rowDelta: Int, columnDelta: Int
    ) -> String {
        var result = formula
        if rowDelta != 0 {
            result = rewrite(result, operation: .translate(delta: rowDelta), axis: .row)
        }
        if columnDelta != 0 {
            result = rewrite(result, operation: .translate(delta: columnDelta), axis: .column)
        }
        return result
    }

    /// Applies an operation to every formula in a cell table.
    static func apply(_ operation: Operation, axis: Axis, to cells: inout [CellAddress: Cell]) {
        for (address, cell) in cells {
            guard let formula = cell.formula else { continue }
            let rewritten = rewrite(formula, operation: operation, axis: axis)
            guard rewritten != formula else { continue }
            var updated = cell
            updated.formula = rewritten
            cells[address] = updated
        }
    }

    static func rewrite(_ formula: String, operation: Operation, axis: Axis) -> String {
        let characters = Array(formula)
        var result = ""
        var index = 0
        var quote: Character?

        while index < characters.count {
            let character = characters[index]

            if let open = quote {
                result.append(character)
                if character == open { quote = nil }
                index += 1
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                result.append(character)
                index += 1
                continue
            }

            if let token = scanReference(characters, from: index) {
                // A word immediately followed by "(" is a function name, not a reference.
                var lookahead = token.end
                while lookahead < characters.count, characters[lookahead] == " " { lookahead += 1 }
                let isFunctionName = lookahead < characters.count && characters[lookahead] == "("
                // A reference must not be glued to a preceding identifier character.
                let previous = index > 0 ? characters[index - 1] : " "
                let isSuffixOfWord = previous.isLetter || previous.isNumber || previous == "_"

                if !isFunctionName, !isSuffixOfWord {
                    result += transform(token, operation: operation, axis: axis)
                    index = token.end
                    continue
                }
                result += String(characters[index..<token.end])
                index = token.end
                continue
            }

            result.append(character)
            index += 1
        }
        return result
    }

    // MARK: - Reference scanning

    private struct ReferenceToken {
        var columnAnchored: Bool
        var columnLetters: String
        var rowAnchored: Bool
        var rowDigits: String
        var end: Int
    }

    private static func scanReference(_ characters: [Character], from start: Int) -> ReferenceToken? {
        var index = start
        var columnAnchored = false
        if index < characters.count, characters[index] == "$" {
            columnAnchored = true
            index += 1
        }
        var letters = ""
        while index < characters.count, characters[index].isLetter {
            letters.append(characters[index])
            index += 1
        }
        guard !letters.isEmpty, letters.count <= 3, CellAddress.columnIndex(letters) != nil else { return nil }

        var rowAnchored = false
        if index < characters.count, characters[index] == "$" {
            rowAnchored = true
            index += 1
        }
        var digits = ""
        while index < characters.count, characters[index].isNumber {
            digits.append(characters[index])
            index += 1
        }
        guard !digits.isEmpty, Int(digits) != nil else { return nil }
        // Anything glued on after the digits means this wasn't a plain reference.
        if index < characters.count, characters[index].isLetter || characters[index] == "_" { return nil }

        return ReferenceToken(
            columnAnchored: columnAnchored, columnLetters: letters,
            rowAnchored: rowAnchored, rowDigits: digits, end: index
        )
    }

    private static func transform(_ token: ReferenceToken, operation: Operation, axis: Axis) -> String {
        guard let column = CellAddress.columnIndex(token.columnLetters),
              let rowNumber = Int(token.rowDigits) else {
            return render(token)
        }
        let row = rowNumber - 1
        let subject = axis == .row ? row : column

        // Filling a formula leaves anchored references where they are. Inserting
        // and deleting lines moves them regardless, so only translation cares.
        if case .translate = operation {
            let isAnchored = axis == .row ? token.rowAnchored : token.columnAnchored
            if isAnchored { return render(token) }
        }

        switch shift(subject, operation: operation) {
        case .broken:
            return CellError.referenceError.rawValue
        case .same:
            return render(token)
        case .moved(let updated):
            var token = token
            if axis == .row {
                token.rowDigits = String(updated + 1)
            } else {
                token.columnLetters = CellAddress.columnName(updated)
            }
            return render(token)
        }
    }

    private enum ShiftOutcome {
        case same
        case moved(Int)
        case broken
    }

    private static func shift(_ line: Int, operation: Operation) -> ShiftOutcome {
        switch operation {
        case .insert(let index, let count):
            return line >= index ? .moved(line + count) : .same
        case .remove(let range):
            if range.contains(line) { return .broken }
            return line > range.upperBound ? .moved(line - range.count) : .same
        case .translate(let delta):
            let moved = line + delta
            // Falling off the top or left edge is a genuine broken reference.
            return moved < 0 ? .broken : .moved(moved)
        }
    }

    private static func render(_ token: ReferenceToken) -> String {
        (token.columnAnchored ? "$" : "") + token.columnLetters
            + (token.rowAnchored ? "$" : "") + token.rowDigits
    }
}
