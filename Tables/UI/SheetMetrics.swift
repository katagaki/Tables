import Foundation

/// Precomputed row and column offsets for a sheet, so scrolling and hit-testing
/// never walk the whole grid.
struct SheetMetrics: Equatable {
    private(set) var columnOffsets: [Double] = [0]
    private(set) var rowOffsets: [Double] = [0]
    private(set) var columnCount = 0
    private(set) var rowCount = 0

    var totalWidth: Double { columnOffsets.last ?? 0 }
    var totalHeight: Double { rowOffsets.last ?? 0 }

    /// The pinch-zoom factor already baked into these offsets.
    private(set) var zoom: Double = 1

    init() {}

    init(sheet: Worksheet, zoom: Double = 1) {
        self.zoom = zoom
        columnCount = sheet.columnCount
        rowCount = sheet.rowCount
        columnOffsets = sheet.columnOffsets.map { $0 * zoom }
        rowOffsets = sheet.rowOffsets.map { $0 * zoom }
    }

    func x(ofColumn column: Int) -> Double {
        columnOffsets[min(max(0, column), columnOffsets.count - 1)]
    }

    func y(ofRow row: Int) -> Double {
        rowOffsets[min(max(0, row), rowOffsets.count - 1)]
    }

    func width(ofColumn column: Int) -> Double {
        guard column >= 0, column + 1 < columnOffsets.count else { return 0 }
        return columnOffsets[column + 1] - columnOffsets[column]
    }

    func height(ofRow row: Int) -> Double {
        guard row >= 0, row + 1 < rowOffsets.count else { return 0 }
        return rowOffsets[row + 1] - rowOffsets[row]
    }

    func frame(for address: CellAddress) -> CGRect {
        CGRect(
            x: x(ofColumn: address.column), y: y(ofRow: address.row),
            width: width(ofColumn: address.column), height: height(ofRow: address.row)
        )
    }

    func frame(for range: CellRange) -> CGRect {
        let box = range.normalized
        let origin = CGPoint(x: x(ofColumn: box.start.column), y: y(ofRow: box.start.row))
        let corner = CGPoint(x: x(ofColumn: box.end.column) + width(ofColumn: box.end.column),
                             y: y(ofRow: box.end.row) + height(ofRow: box.end.row))
        return CGRect(x: origin.x, y: origin.y, width: corner.x - origin.x, height: corner.y - origin.y)
    }

    /// Columns intersecting a horizontal span, with a little overscan.
    func columns(in span: ClosedRange<Double>, overscan: Int = 2) -> Range<Int> {
        guard columnCount > 0 else { return 0..<0 }
        let first = max(0, index(in: columnOffsets, at: span.lowerBound) - overscan)
        let last = min(columnCount - 1, index(in: columnOffsets, at: span.upperBound) + overscan)
        return first <= last ? first..<(last + 1) : 0..<0
    }

    /// Rows intersecting a vertical span, with a little overscan.
    func rows(in span: ClosedRange<Double>, overscan: Int = 2) -> Range<Int> {
        guard rowCount > 0 else { return 0..<0 }
        let first = max(0, index(in: rowOffsets, at: span.lowerBound) - overscan)
        let last = min(rowCount - 1, index(in: rowOffsets, at: span.upperBound) + overscan)
        return first <= last ? first..<(last + 1) : 0..<0
    }

    func column(atX position: Double) -> Int {
        min(max(0, index(in: columnOffsets, at: position)), max(0, columnCount - 1))
    }

    func row(atY position: Double) -> Int {
        min(max(0, index(in: rowOffsets, at: position)), max(0, rowCount - 1))
    }

    /// Index of the last offset less than or equal to `position`.
    private func index(in offsets: [Double], at position: Double) -> Int {
        var low = 0
        var high = offsets.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if offsets[middle] <= position { low = middle } else { high = middle - 1 }
        }
        return low
    }
}
