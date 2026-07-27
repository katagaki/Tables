import Foundation

/// A collection of worksheets — the whole document.
struct Workbook: Hashable, Sendable {
    var sheets: [Worksheet]

    init(sheets: [Worksheet]) {
        self.sheets = sheets.isEmpty ? [Worksheet(name: "Sheet 1")] : sheets
    }

    init() {
        self.init(sheets: [Worksheet(name: "Sheet 1")])
    }

    subscript(sheetID: Worksheet.ID) -> Worksheet? {
        get { sheets.first { $0.id == sheetID } }
        set {
            guard let newValue, let index = sheets.firstIndex(where: { $0.id == sheetID }) else { return }
            sheets[index] = newValue
        }
    }

    func index(of sheetID: Worksheet.ID) -> Int? {
        sheets.firstIndex { $0.id == sheetID }
    }

    func sheet(named name: String) -> Worksheet? {
        sheets.first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    }

    /// A sheet name Excel accepts that doesn't collide with any existing sheet.
    func uniqueSheetName(basedOn candidate: String) -> String {
        let base = Worksheet.sanitizedName(candidate)
        guard sheet(named: base) != nil else { return base }

        var suffix = 2
        while true {
            // The suffix has to fit inside the length limit too, so trim the
            // stem rather than overrun it.
            let tail = " \(suffix)"
            let stem = String(base.prefix(Worksheet.maximumNameLength - tail.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = stem + tail
            if sheet(named: candidate) == nil { return candidate }
            suffix += 1
        }
    }

    mutating func addSheet(named name: String? = nil, at index: Int? = nil) -> Worksheet.ID {
        let resolved = uniqueSheetName(basedOn: name ?? "Sheet \(sheets.count + 1)")
        let sheet = Worksheet(name: resolved)
        sheets.insert(sheet, at: min(max(0, index ?? sheets.count), sheets.count))
        return sheet.id
    }

    mutating func duplicateSheet(_ sheetID: Worksheet.ID) -> Worksheet.ID? {
        guard let index = index(of: sheetID) else { return nil }
        var copy = sheets[index]
        copy.id = UUID()
        copy.name = uniqueSheetName(basedOn: sheets[index].name + " Copy")
        sheets.insert(copy, at: index + 1)
        return copy.id
    }

    /// Removes a sheet unless it is the only one left.
    @discardableResult
    mutating func removeSheet(_ sheetID: Worksheet.ID) -> Bool {
        guard sheets.count > 1, let index = index(of: sheetID) else { return false }
        sheets.remove(at: index)
        return true
    }

    mutating func moveSheet(_ sheetID: Worksheet.ID, to destination: Int) {
        guard let index = index(of: sheetID) else { return }
        let sheet = sheets.remove(at: index)
        sheets.insert(sheet, at: min(max(0, destination), sheets.count))
    }

    mutating func renameSheet(_ sheetID: Worksheet.ID, to name: String) {
        guard let index = index(of: sheetID) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != sheets[index].name else { return }
        var candidate = self
        candidate.sheets.remove(at: index)
        sheets[index].name = candidate.uniqueSheetName(basedOn: trimmed)
    }
}
