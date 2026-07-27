import Foundation

/// A zero-based cell coordinate. `CellAddress(row: 0, column: 0)` is A1.
struct CellAddress: Hashable, Comparable, Sendable, Codable {
    var row: Int
    var column: Int

    init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    static func < (lhs: CellAddress, rhs: CellAddress) -> Bool {
        lhs.row == rhs.row ? lhs.column < rhs.column : lhs.row < rhs.row
    }

    /// "A1"-style reference for this address.
    var a1: String { "\(Self.columnName(column))\(row + 1)" }

    /// "A", "B", … "Z", "AA", … for a zero-based column index.
    static func columnName(_ column: Int) -> String {
        var result = ""
        var value = column
        repeat {
            result = String(UnicodeScalar(UInt8(65 + value % 26))) + result
            value = value / 26 - 1
        } while value >= 0
        return result
    }

    /// Zero-based column index for "A", "AB", … Returns nil for non-letters.
    static func columnIndex(_ name: String) -> Int? {
        guard !name.isEmpty else { return nil }
        var value = 0
        for scalar in name.uppercased().unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { return nil }
            value = value * 26 + Int(scalar.value - 64)
        }
        return value - 1
    }

    /// Parses "A1", "$B$7" and similar into an address. Dollar anchors are ignored.
    init?(a1 reference: String) {
        var letters = ""
        var digits = ""
        for character in reference {
            if character == "$" { continue }
            if character.isLetter {
                guard digits.isEmpty else { return nil }
                letters.append(character)
            } else if character.isNumber {
                digits.append(character)
            } else {
                return nil
            }
        }
        guard let column = Self.columnIndex(letters),
              let rowNumber = Int(digits), rowNumber > 0 else { return nil }
        self.init(row: rowNumber - 1, column: column)
    }
}

/// An inclusive rectangular span of cells.
struct CellRange: Hashable, Sendable {
    var start: CellAddress
    var end: CellAddress

    init(start: CellAddress, end: CellAddress) {
        self.start = start
        self.end = end
    }

    init(_ single: CellAddress) {
        self.init(start: single, end: single)
    }

    var normalized: CellRange {
        CellRange(
            start: CellAddress(row: min(start.row, end.row), column: min(start.column, end.column)),
            end: CellAddress(row: max(start.row, end.row), column: max(start.column, end.column))
        )
    }

    var rowRange: ClosedRange<Int> { normalized.start.row...normalized.end.row }
    var columnRange: ClosedRange<Int> { normalized.start.column...normalized.end.column }
    var isSingleCell: Bool { start == end }

    func contains(_ address: CellAddress) -> Bool {
        let box = normalized
        return address.row >= box.start.row && address.row <= box.end.row
            && address.column >= box.start.column && address.column <= box.end.column
    }

    var addresses: [CellAddress] {
        let box = normalized
        var result: [CellAddress] = []
        for row in box.rowRange {
            for column in box.columnRange {
                result.append(CellAddress(row: row, column: column))
            }
        }
        return result
    }

    var a1: String {
        isSingleCell ? start.a1 : "\(normalized.start.a1):\(normalized.end.a1)"
    }
}
