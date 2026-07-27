import Foundation

/// Reads and writes RFC 4180 style delimited text.
enum CSVCodec {
    /// Builds a single-sheet workbook from delimited text, sniffing the delimiter.
    static func workbook(from data: Data, sheetName: String) -> Workbook {
        let text = decodeText(data)
        let delimiter = sniffDelimiter(in: text)
        let rows = parse(text, delimiter: delimiter)

        var sheet = Worksheet(name: sheetName)
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, field) in row.enumerated() where !field.isEmpty {
                let address = CellAddress(row: rowIndex, column: columnIndex)
                sheet[address] = CellInputParser.cell(from: field, inheriting: .default)
            }
        }
        sheet.rowCount = max(Worksheet.defaultRowCount, min(rows.count, Worksheet.maximumRowCount))
        sheet.columnCount = max(
            Worksheet.defaultColumnCount,
            min(rows.map(\.count).max() ?? 0, Worksheet.maximumColumnCount)
        )

        var workbook = Workbook(sheets: [sheet])
        workbook.recalculate()
        return workbook
    }

    /// Serializes one sheet. CSV has no concept of multiple sheets, so callers
    /// choose which one to export.
    static func data(from sheet: Worksheet, delimiter: Character = ",") -> Data {
        var lines: [String] = []
        lines.reserveCapacity(sheet.rowCount)
        for row in 0..<sheet.rowCount where !sheet.hiddenRows.contains(row) {
            var fields: [String] = []
            for column in 0..<sheet.columnCount where !sheet.hiddenColumns.contains(column) {
                let cell = sheet[CellAddress(row: row, column: column)]
                fields.append(escape(CellFormatter.displayText(for: cell), delimiter: delimiter))
            }
            lines.append(fields.joined(separator: String(delimiter)))
        }
        // Trailing blank lines carry no information; drop them.
        while let last = lines.last, last.allSatisfy({ $0 == delimiter }) || last.isEmpty {
            lines.removeLast()
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    // MARK: - Decoding

    private static func decodeText(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return stripByteOrderMark(utf8) }
        if let latin = String(data: data, encoding: .isoLatin1) { return latin }
        return String(decoding: data, as: UTF8.self)
    }

    private static func stripByteOrderMark(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    private static func sniffDelimiter(in text: String) -> Character {
        let sample = text.prefix(4096)
        let candidates: [Character] = [",", ";", "\t", "|"]
        var best: Character = ","
        var bestCount = 0
        for candidate in candidates {
            let count = sample.filter { $0 == candidate }.count
            if count > bestCount {
                bestCount = count
                best = candidate
            }
        }
        return best
    }

    private static func parse(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() {
            row.append(field)
            field = ""
        }

        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"" where field.isEmpty:
                inQuotes = true
            case delimiter:
                endField()
            // A CRLF pair is one Swift Character, so match on the newline
            // property rather than on "\r" and "\n" separately.
            case let newline where newline.isNewline:
                endRow()
            default:
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    private static func escape(_ field: String, delimiter: Character) -> String {
        let needsQuoting = field.contains(delimiter) || field.contains("\"")
            || field.contains(where: \.isNewline)
        guard needsQuoting else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
