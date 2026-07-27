import Foundation

/// One cell's stored content: either a literal value or a formula plus its cached result.
struct Cell: Hashable, Sendable {
    var value: CellValue = .empty
    var formula: String?
    var style: CellStyle = .default

    var isBlank: Bool { value.isEmpty && formula == nil }
    var isEmptyEntirely: Bool { isBlank && style.isDefault }

    /// What the formula bar shows and what the user edits.
    var editableText: String {
        if let formula { return "=" + formula }
        switch value {
        case .empty: return ""
        case .number(let number): return CellValue.plainNumberString(number)
        case .text(let text): return text
        case .boolean(let flag): return flag ? "TRUE" : "FALSE"
        case .error(let error): return error.rawValue
        }
    }
}

/// A single sheet of a workbook. Row and column counts are explicit, Numbers-style:
/// the grid never grows on its own, the user adds and removes rows and columns.
struct Worksheet: Identifiable, Hashable, Sendable {
    static let defaultRowCount = 20
    static let defaultColumnCount = 5
    static let defaultColumnWidth: Double = 104
    static let defaultRowHeight: Double = 30
    static let minimumColumnWidth: Double = 40
    static let minimumRowHeight: Double = 20
    static let maximumRowCount = 100_000
    static let maximumColumnCount = 4_096

    /// Characters Excel forbids in a sheet name. A workbook containing one is
    /// not merely odd — conforming readers reject the whole file.
    static let forbiddenNameCharacters = CharacterSet(charactersIn: "\\/?*[]:")
    static let maximumNameLength = 31
    /// Reserved by Excel for the change-tracking sheet.
    static let reservedName = "History"

    /// Coerces any string into a name Excel will accept.
    static func sanitizedName(_ candidate: String) -> String {
        var cleaned = candidate
            .components(separatedBy: forbiddenNameCharacters)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Leading and trailing apostrophes break quoted sheet references.
        while cleaned.hasPrefix("'") { cleaned.removeFirst() }
        while cleaned.hasSuffix("'") { cleaned.removeLast() }

        if cleaned.count > maximumNameLength {
            cleaned = String(cleaned.prefix(maximumNameLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.isEmpty || cleaned.compare(reservedName, options: .caseInsensitive) == .orderedSame {
            return "Sheet"
        }
        return cleaned
    }

    var id = UUID()
    var name: String
    var cells: [CellAddress: Cell] = [:]
    var rowCount: Int = Worksheet.defaultRowCount
    var columnCount: Int = Worksheet.defaultColumnCount
    var columnWidths: [Int: Double] = [:]
    var rowHeights: [Int: Double] = [:]
    var hiddenRows: Set<Int> = []
    var hiddenColumns: Set<Int> = []
    var tabColorHex: String?

    init(name: String) {
        self.name = Self.sanitizedName(name)
    }

    // MARK: - Cell access

    subscript(address: CellAddress) -> Cell {
        get { cells[address] ?? Cell() }
        set {
            if newValue.isEmptyEntirely {
                cells.removeValue(forKey: address)
            } else {
                cells[address] = newValue
            }
        }
    }

    func contains(_ address: CellAddress) -> Bool {
        address.row >= 0 && address.row < rowCount
            && address.column >= 0 && address.column < columnCount
    }

    // MARK: - Geometry

    func width(ofColumn column: Int) -> Double {
        hiddenColumns.contains(column) ? 0 : (columnWidths[column] ?? Self.defaultColumnWidth)
    }

    func height(ofRow row: Int) -> Double {
        hiddenRows.contains(row) ? 0 : (rowHeights[row] ?? Self.defaultRowHeight)
    }

    var totalWidth: Double { (0..<columnCount).reduce(0) { $0 + width(ofColumn: $1) } }
    var totalHeight: Double { (0..<rowCount).reduce(0) { $0 + height(ofRow: $1) } }

    /// Running x-offsets for every column, plus a final entry equal to `totalWidth`.
    var columnOffsets: [Double] {
        var offsets: [Double] = [0]
        offsets.reserveCapacity(columnCount + 1)
        for column in 0..<columnCount { offsets.append(offsets[column] + width(ofColumn: column)) }
        return offsets
    }

    /// Running y-offsets for every row, plus a final entry equal to `totalHeight`.
    var rowOffsets: [Double] {
        var offsets: [Double] = [0]
        offsets.reserveCapacity(rowCount + 1)
        for row in 0..<rowCount { offsets.append(offsets[row] + height(ofRow: row)) }
        return offsets
    }

    // MARK: - Structure editing

    mutating func addRows(_ count: Int) {
        rowCount = min(Self.maximumRowCount, rowCount + max(1, count))
    }

    mutating func addColumns(_ count: Int) {
        columnCount = min(Self.maximumColumnCount, columnCount + max(1, count))
    }

    mutating func insertRows(_ count: Int, at index: Int) {
        let count = max(1, count)
        guard rowCount + count <= Self.maximumRowCount else { return }
        FormulaReferenceShifter.apply(.insert(index: index, count: count), axis: .row, to: &cells)
        remapCells { $0.row >= index ? CellAddress(row: $0.row + count, column: $0.column) : $0 }
        rowHeights = Self.shift(rowHeights, from: index, by: count)
        hiddenRows = Self.shift(hiddenRows, from: index, by: count)
        rowCount += count
    }

    mutating func insertColumns(_ count: Int, at index: Int) {
        let count = max(1, count)
        guard columnCount + count <= Self.maximumColumnCount else { return }
        FormulaReferenceShifter.apply(.insert(index: index, count: count), axis: .column, to: &cells)
        remapCells { $0.column >= index ? CellAddress(row: $0.row, column: $0.column + count) : $0 }
        columnWidths = Self.shift(columnWidths, from: index, by: count)
        hiddenColumns = Self.shift(hiddenColumns, from: index, by: count)
        columnCount += count
    }

    mutating func removeRows(_ range: ClosedRange<Int>) {
        let count = range.count
        guard rowCount - count >= 1 else { return }
        FormulaReferenceShifter.apply(.remove(range: range), axis: .row, to: &cells)
        cells = cells.filter { !range.contains($0.key.row) }
        remapCells { $0.row > range.upperBound ? CellAddress(row: $0.row - count, column: $0.column) : $0 }
        rowHeights = Self.shift(rowHeights.filter { !range.contains($0.key) }, from: range.upperBound + 1, by: -count)
        hiddenRows = Self.shift(hiddenRows.filter { !range.contains($0) }, from: range.upperBound + 1, by: -count)
        rowCount -= count
    }

    mutating func removeColumns(_ range: ClosedRange<Int>) {
        let count = range.count
        guard columnCount - count >= 1 else { return }
        FormulaReferenceShifter.apply(.remove(range: range), axis: .column, to: &cells)
        cells = cells.filter { !range.contains($0.key.column) }
        remapCells { $0.column > range.upperBound ? CellAddress(row: $0.row, column: $0.column - count) : $0 }
        columnWidths = Self.shift(columnWidths.filter { !range.contains($0.key) }, from: range.upperBound + 1, by: -count)
        hiddenColumns = Self.shift(hiddenColumns.filter { !range.contains($0) }, from: range.upperBound + 1, by: -count)
        columnCount -= count
    }

    mutating func setRows(_ range: ClosedRange<Int>, hidden: Bool) {
        if hidden {
            hiddenRows.formUnion(range)
        } else {
            hiddenRows.subtract(range)
        }
    }

    mutating func setColumns(_ range: ClosedRange<Int>, hidden: Bool) {
        if hidden {
            hiddenColumns.formUnion(range)
        } else {
            hiddenColumns.subtract(range)
        }
    }

    /// Reveals every hidden row and column.
    mutating func unhideAll() {
        hiddenRows.removeAll()
        hiddenColumns.removeAll()
    }

    private mutating func remapCells(_ transform: (CellAddress) -> CellAddress) {
        var moved: [CellAddress: Cell] = [:]
        moved.reserveCapacity(cells.count)
        for (address, cell) in cells { moved[transform(address)] = cell }
        cells = moved
    }

    private static func shift(_ values: [Int: Double], from index: Int, by delta: Int) -> [Int: Double] {
        var result: [Int: Double] = [:]
        for (key, value) in values { result[key >= index ? key + delta : key] = value }
        return result
    }

    private static func shift(_ values: Set<Int>, from index: Int, by delta: Int) -> Set<Int> {
        Set(values.map { $0 >= index ? $0 + delta : $0 })
    }
}
