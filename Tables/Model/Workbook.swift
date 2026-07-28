import Foundation

/// A name a workbook binds to a formula, as `<definedNames>` declares it.
///
/// The definition is an arbitrary formula — most often an absolute range such
/// as `Sheet1!$A$2:$A$10`, but a constant or a whole expression is just as
/// legal, so it is stored as text and parsed only when something asks for it.
struct DefinedName: Hashable, Sendable {
    /// Excel matches names case-insensitively. The original spelling is kept
    /// anyway: it is what the file and the formula bar show.
    var name: String
    /// The definition, stored without a leading `=`, like a cell's formula.
    var formula: String
    /// The sheet the name is scoped to. `nil` is workbook scope, which is what
    /// a `<definedName>` without a `localSheetId` means. The file identifies
    /// the sheet by position, but positions move when sheets are added,
    /// deleted or dragged, and a scope that drifts would quietly answer the
    /// wrong sheet's formulas — so the binding is to the sheet itself.
    var scope: Worksheet.ID?

    /// Excel keeps its own entries — print areas, filter ranges — in the same
    /// list under a reserved prefix. They are never usable inside a formula.
    var isBuiltIn: Bool { name.lowercased().hasPrefix(Self.builtInPrefix) }

    static let builtInPrefix = "_xlnm."
}

/// Something a workbook carries that Tables can show but not edit.
///
/// The distinction the user cares about is not which OOXML part it lives in
/// but whether saving keeps it, so these name features, not file structure.
enum UnsupportedFeature: String, CaseIterable, Hashable, Sendable, Comparable {
    case conditionalFormatting
    case dataValidation
    case autoFilter
    case frozenPanes
    case sheetProtection
    case printSetup
    case comments
    case hyperlinks
    case tables
    case chartsAndImages
    case pivotTables
    case documentProperties

    var label: String {
        switch self {
        case .conditionalFormatting: return "Conditional formatting"
        case .dataValidation: return "Data validation"
        case .autoFilter: return "Filters"
        case .frozenPanes: return "Frozen rows and columns"
        case .sheetProtection: return "Sheet protection"
        case .printSetup: return "Print setup"
        case .comments: return "Comments"
        case .hyperlinks: return "Links"
        case .tables: return "Tables"
        case .chartsAndImages: return "Charts and images"
        case .pivotTables: return "PivotTables"
        case .documentProperties: return "Document properties"
        }
    }

    /// Ordered by declaration so a notice always lists features the same way.
    static func < (lhs: UnsupportedFeature, rhs: UnsupportedFeature) -> Bool {
        guard let left = allCases.firstIndex(of: lhs), let right = allCases.firstIndex(of: rhs) else {
            return lhs.rawValue < rhs.rawValue
        }
        return left < right
    }
}

/// What a file was found to contain that Tables cannot edit, split by whether
/// saving will keep it.
struct UnsupportedFeatureReport: Hashable, Sendable {
    /// Written back byte-for-byte exactly as the file had it.
    private(set) var preserved: Set<UnsupportedFeature> = []
    /// Found, but gone the moment the user saves.
    private(set) var lost: Set<UnsupportedFeature> = []

    var isEmpty: Bool { preserved.isEmpty && lost.isEmpty }

    /// Records a sighting. A feature that is lost anywhere is reported as lost:
    /// telling someone their comments are safe when one sheet's are not is
    /// worse than saying nothing.
    mutating func record(_ feature: UnsupportedFeature, isPreserved: Bool) {
        guard isPreserved else {
            preserved.remove(feature)
            lost.insert(feature)
            return
        }
        guard !lost.contains(feature) else { return }
        preserved.insert(feature)
    }

    /// Plain wording for the notice shown when such a document opens.
    var noticeMessage: String {
        var lines: [String] = []
        if !preserved.isEmpty {
            lines.append(
                "Kept exactly as they are, but not editable here: "
                + preserved.sorted().map(\.label).joined(separator: ", ") + "."
            )
        }
        if !lost.isEmpty {
            lines.append(
                "Won’t survive saving: "
                + lost.sorted().map(\.label).joined(separator: ", ") + "."
            )
        }
        return lines.joined(separator: "\n\n")
    }
}

/// The raw XML of an element Tables does not model, kept so that opening and
/// saving a file does not delete it.
///
/// Both the parts this appears in — `<worksheet>` and `<styleSheet>` — fix the
/// order of their children by schema, so the name is what decides where the
/// fragment goes back in.
struct PreservedElement: Hashable, Sendable {
    var name: String
    /// The fragment itself, namespace declarations and all.
    var xml: String

    /// Worksheet children that name a relationship id rather than carrying
    /// their target inline. They are only meaningful while the sheet's own
    /// `_rels` part survives alongside them, and a dangling id is what makes
    /// Excel offer to repair a file.
    static let relationshipDependentNames: Set<String> = [
        "hyperlinks", "legacyDrawing", "tableParts", "drawing",
    ]

    var needsSheetRelationships: Bool { Self.relationshipDependentNames.contains(name) }
}

/// One entry of a `_rels` part, kept as the file wrote it.
///
/// The identifier is deliberately absent: relationship ids are only meaningful
/// within one part, and the ones we re-emit are renumbered around our own.
struct PreservedRelationship: Hashable, Sendable {
    var type: String
    var target: String
    /// `"External"` for a target outside the package, absent otherwise.
    var targetMode: String?
}

/// The pieces of an opened package that Tables does not generate and carries
/// through a save untouched.
struct PreservedPackage: Hashable, Sendable {
    /// Retained ZIP entries, keyed by their path in the package.
    var parts: [String: Data] = [:]
    /// `<Default>` content types, keyed by extension, that retained parts need.
    var contentTypeDefaults: [String: String] = [:]
    /// `<Override>` content types, keyed by the absolute part name.
    var contentTypeOverrides: [String: String] = [:]
    /// Entries to re-emit in `_rels/.rels` beside the one we generate.
    var rootRelationships: [PreservedRelationship] = []
    /// Entries to re-emit in `xl/_rels/workbook.xml.rels`.
    var workbookRelationships: [PreservedRelationship] = []
    /// Whole `_rels` parts for individual sheets, kept verbatim because the
    /// sheet XML we also preserve refers to their ids by name. Keyed by sheet
    /// rather than by path: a sheet's position, and so its file name, moves.
    var sheetRelationshipParts: [Worksheet.ID: Data] = [:]
    /// Children of `xl/styles.xml` we regenerate around rather than rewrite.
    /// Differential formats especially: preserved conditional formatting names
    /// them by position, so dropping them would leave every rule pointing at a
    /// table that is no longer there.
    var styleSheetElements: [PreservedElement] = []

    var isEmpty: Bool { parts.isEmpty && sheetRelationshipParts.isEmpty && styleSheetElements.isEmpty }
}

/// A collection of worksheets — the whole document.
struct Workbook: Hashable, Sendable {
    var sheets: [Worksheet]
    var definedNames: [DefinedName]
    /// Package parts carried through from the file this workbook was read from.
    var preservedPackage = PreservedPackage()
    /// What that file used that we cannot edit, for the notice shown on open.
    var unsupportedFeatures = UnsupportedFeatureReport()

    init(sheets: [Worksheet], definedNames: [DefinedName] = []) {
        self.sheets = sheets.isEmpty ? [Worksheet(name: "Sheet 1")] : sheets
        self.definedNames = definedNames
    }

    init() {
        self.init(sheets: [Worksheet(name: "Sheet 1")])
    }

    /// The definition a formula living on `sheetID` sees for `name`.
    ///
    /// A name scoped to that sheet wins over a workbook-scoped one spelled the
    /// same way, and a name scoped to any *other* sheet is invisible: matching
    /// it would let one sheet's private definition answer another sheet's
    /// formula. Excel's own `_xlnm.` entries never resolve.
    func definedName(_ name: String, visibleFrom sheetID: Worksheet.ID?) -> DefinedName? {
        let matches = definedNames.filter {
            !$0.isBuiltIn && $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }
        if let sheetID, let scoped = matches.first(where: { $0.scope == sheetID }) {
            return scoped
        }
        return matches.first { $0.scope == nil }
    }

    subscript(sheetID: Worksheet.ID) -> Worksheet? {
        get { sheets.first { $0.id == sheetID } }
        set {
            guard let newValue, let index = sheets.firstIndex(where: { $0.id == sheetID }) else { return }
            sheets[index] = newValue
        }
    }

    /// The sheets a user can actually reach — what the tab strip shows.
    var visibleSheets: [Worksheet] { sheets.filter { !$0.isHidden } }

    /// Hides or reveals a sheet. Hiding the last visible one fails: Excel
    /// requires at least one, and a workbook without it opens to nothing.
    @discardableResult
    mutating func setSheet(_ sheetID: Worksheet.ID, hidden: Bool) -> Bool {
        guard let index = index(of: sheetID) else { return false }
        guard sheets[index].isHidden != hidden else { return true }
        if hidden, visibleSheets.count <= 1 { return false }
        sheets[index].isHidden = hidden
        return true
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
        // Deleting the only visible sheet would leave the strip empty.
        if visibleSheets.isEmpty { sheets[0].isHidden = false }
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
