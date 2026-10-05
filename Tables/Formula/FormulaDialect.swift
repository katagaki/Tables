import Foundation

/// Converts formula text between how a person writes it and how Excel stores it.
///
/// Functions added after the 2007 file format carry an `_xlfn.` prefix in the
/// file (`_xlfn._xlws.` for a few), LET and LAMBDA names carry `_xlpm.`, and the
/// `@` and `#` operators are stored as `_xlfn.SINGLE(…)` and
/// `_xlfn.ANCHORARRAY(…)`. Without them Excel reads the formula as calling an
/// unknown add-in and shows `#NAME?`.
///
/// Both directions splice the original text rather than reprinting a parse
/// tree, so spacing, casing and anything unrecognised survive untouched. Text
/// that does not parse is passed through as it is.
enum FormulaDialect {
    /// Functions stored with `_xlfn.`, from Excel 2010 onwards.
    static let futureFunctions: Set<String> = [
        // Excel 2010
        "AGGREGATE", "BETA.DIST", "BETA.INV", "BINOM.DIST", "BINOM.INV", "CEILING.PRECISE", "CHISQ.DIST",
        "CHISQ.DIST.RT", "CHISQ.INV", "CHISQ.INV.RT", "CHISQ.TEST", "CONFIDENCE.NORM", "CONFIDENCE.T",
        "COVARIANCE.P", "COVARIANCE.S", "ERF.PRECISE", "ERFC.PRECISE", "EXPON.DIST", "F.DIST", "F.DIST.RT",
        "F.INV", "F.INV.RT", "F.TEST", "FLOOR.PRECISE", "GAMMA.DIST", "GAMMA.INV", "GAMMALN.PRECISE",
        "HYPGEOM.DIST", "ISO.CEILING", "LOGNORM.DIST", "LOGNORM.INV", "MODE.MULT", "MODE.SNGL", "NEGBINOM.DIST",
        "NETWORKDAYS.INTL", "NORM.DIST", "NORM.INV", "NORM.S.DIST", "NORM.S.INV", "PERCENTILE.EXC",
        "PERCENTILE.INC", "PERCENTRANK.EXC", "PERCENTRANK.INC", "POISSON.DIST", "QUARTILE.EXC", "QUARTILE.INC",
        "RANK.AVG", "RANK.EQ", "STDEV.P", "STDEV.S", "T.DIST", "T.DIST.2T", "T.DIST.RT", "T.INV", "T.INV.2T",
        "T.TEST", "VAR.P", "VAR.S", "WEIBULL.DIST", "WORKDAY.INTL", "Z.TEST",
        // Excel 2013
        "ACOT", "ACOTH", "ARABIC", "BASE", "BINOM.DIST.RANGE", "BITAND", "BITLSHIFT", "BITOR", "BITRSHIFT",
        "BITXOR", "CEILING.MATH", "COMBINA", "COT", "COTH", "CSC", "CSCH", "DAYS", "DECIMAL", "ENCODEURL",
        "FILTERXML", "FLOOR.MATH", "FORMULATEXT", "GAMMA", "GAUSS", "IFNA", "IMCOSH", "IMCOT", "IMCSC",
        "IMCSCH", "IMSEC", "IMSECH", "IMSINH", "IMTAN", "ISFORMULA", "ISOWEEKNUM", "MUNIT", "NUMBERVALUE",
        "PDURATION", "PERMUTATIONA", "PHI", "RRI", "SEC", "SECH", "SHEET", "SHEETS", "SKEW.P", "UNICHAR",
        "UNICODE", "WEBSERVICE", "XOR",
        // Excel 2016 and 2019
        "FORECAST.ETS", "FORECAST.ETS.CONFINT", "FORECAST.ETS.SEASONALITY", "FORECAST.ETS.STAT",
        "FORECAST.LINEAR", "CONCAT", "IFS", "MAXIFS", "MINIFS", "SWITCH", "TEXTJOIN",
        // Microsoft 365
        "ANCHORARRAY", "ARRAYTOTEXT", "BYCOL", "BYROW", "CHOOSECOLS", "CHOOSEROWS", "DETECTLANGUAGE", "DROP",
        "EXPAND", "FILTER", "GROUPBY", "HSTACK", "IMAGE", "ISOMITTED", "LAMBDA", "LET", "MAKEARRAY", "MAP",
        "PERCENTOF", "PIVOTBY", "RANDARRAY", "REDUCE", "REGEXEXTRACT", "REGEXREPLACE", "REGEXTEST", "SCAN",
        "SEQUENCE", "SINGLE", "SORT", "SORTBY", "STOCKHISTORY", "TAKE", "TEXTAFTER", "TEXTBEFORE", "TEXTSPLIT",
        "TOCOL", "TOROW", "TRANSLATE", "TRIMRANGE", "UNIQUE", "VALUETOTEXT", "VSTACK", "WRAPCOLS", "WRAPROWS",
        "XLOOKUP", "XMATCH",
    ]

    /// The handful that also carry `_xlws.`, after `_xlfn.`.
    static let worksheetFunctions: Set<String> = ["FILTER", "SORT"]

    // MARK: - Reading

    /// Rewrites a formula read from a file into the form a person types.
    static func fromFile(_ formula: String) -> String {
        guard formula.localizedCaseInsensitiveContains("_xl"),
              let syntax = try? FormulaParser.parseSyntax(formula) else { return formula }
        let characters = Array(formula)
        var edits: [Edit] = []
        collectReadEdits(syntax, characters: characters, into: &edits)
        return apply(edits, to: characters)
    }

    private static func collectReadEdits(_ syntax: FormulaSyntax, characters: [Character], into edits: inout [Edit]) {
        if syntax.isGroup {
            for child in syntax.children { collectReadEdits(child, characters: characters, into: &edits) }
            return
        }
        switch syntax.node {
        case .call:
            // Strip the prefixes off a function we know; one we do not know
            // keeps them, so it goes back to the file exactly as it came.
            let word = leadingWord(in: characters, at: syntax.range.lowerBound)
            let name = FormulaParser.strippingFilePrefixes(word).uppercased()
            if word.count != name.count, FormulaFunctions.isKnown(name) {
                edits.append(Edit(range: syntax.range.lowerBound..<(syntax.range.lowerBound + word.count - name.count),
                                  replacement: ""))
            }
        case .intersect, .spill:
            // `_xlfn.SINGLE(x)` becomes `@x` and `_xlfn.ANCHORARRAY(x)` becomes
            // `x#`; the written forms already read as `@` and `#` and need nothing.
            let word = leadingWord(in: characters, at: syntax.range.lowerBound)
            let name = FormulaParser.strippingFilePrefixes(word).uppercased()
            if name == "SINGLE" || name == "ANCHORARRAY", let operand = syntax.children.first {
                let inner = fromFile(String(characters[operand.range]))
                let wrapped = isSimpleOperand(operand) ? inner : "(" + inner + ")"
                edits.append(Edit(range: syntax.range, replacement: name == "SINGLE" ? "@" + wrapped : wrapped + "#"))
                return
            }
        case .definedName:
            let word = String(characters[syntax.range])
            if word.lowercased().hasPrefix("_xlpm.") {
                edits.append(Edit(range: syntax.range.lowerBound..<(syntax.range.lowerBound + 6), replacement: ""))
            }
        default:
            break
        }
        for child in syntax.children { collectReadEdits(child, characters: characters, into: &edits) }
    }

    // MARK: - Writing

    /// Rewrites a formula as Excel stores it.
    static func toFile(_ formula: String) -> String {
        guard let syntax = try? FormulaParser.parseSyntax(formula) else { return formula }
        let characters = Array(formula)
        var edits: [Edit] = []
        collectWriteEdits(syntax, characters: characters, parameters: [], into: &edits)
        return apply(edits, to: characters)
    }

    private static func collectWriteEdits(
        _ syntax: FormulaSyntax, characters: [Character], parameters: Set<String>, into edits: inout [Edit]
    ) {
        var parameters = parameters
        if syntax.isGroup {
            for child in syntax.children {
                collectWriteEdits(child, characters: characters, parameters: parameters, into: &edits)
            }
            return
        }
        switch syntax.node {
        case .call(let name, let arguments):
            let word = leadingWord(in: characters, at: syntax.range.lowerBound)
            // Only bare names gain a prefix; one already written keeps its own.
            if !word.hasPrefix("_"), futureFunctions.contains(name) {
                let prefix = "_xlfn." + (worksheetFunctions.contains(name) ? "_xlws." : "")
                edits.append(Edit(range: syntax.range.lowerBound..<syntax.range.lowerBound, replacement: prefix))
            }
            // LET names its variables in every other argument; LAMBDA's are all
            // but the last. Both are visible to the arguments after them.
            if name == "LET" {
                for (position, argument) in arguments.enumerated() where position % 2 == 0 && position < arguments.count - 1 {
                    if case .definedName(nil, let variable) = argument { parameters.insert(variable.lowercased()) }
                }
            } else if name == "LAMBDA" {
                for argument in arguments.dropLast() {
                    if case .definedName(nil, let variable) = argument { parameters.insert(variable.lowercased()) }
                }
            }
        case .intersect:
            if characters[syntax.range.lowerBound] == "@", let operand = syntax.children.first {
                edits.append(Edit(range: syntax.range,
                                  replacement: "_xlfn.SINGLE(" + toFile(String(characters[operand.range])) + ")"))
                return
            }
        case .spill:
            if characters[syntax.range.upperBound - 1] == "#", let operand = syntax.children.first {
                edits.append(Edit(range: syntax.range,
                                  replacement: "_xlfn.ANCHORARRAY(" + toFile(String(characters[operand.range])) + ")"))
                return
            }
        case .definedName(nil, let variable) where parameters.contains(variable.lowercased()):
            if !String(characters[syntax.range]).lowercased().hasPrefix("_xlpm.") {
                edits.append(Edit(range: syntax.range.lowerBound..<syntax.range.lowerBound, replacement: "_xlpm."))
            }
        default:
            break
        }
        for child in syntax.children {
            collectWriteEdits(child, characters: characters, parameters: parameters, into: &edits)
        }
    }

    /// Whether `@` or `#` can sit against an operand without parentheses.
    private static func isSimpleOperand(_ syntax: FormulaSyntax) -> Bool {
        if syntax.isGroup || syntax.children.isEmpty { return true }
        if case .call = syntax.node { return true }
        return false
    }

    // MARK: - Splicing

    private struct Edit {
        var range: Range<Int>
        var replacement: String
    }

    /// Applies non-overlapping edits, last first so earlier offsets stay valid.
    private static func apply(_ edits: [Edit], to characters: [Character]) -> String {
        var result = characters
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            result.replaceSubrange(edit.range, with: Array(edit.replacement))
        }
        return String(result)
    }

    /// The identifier starting at `offset`, prefixes and all.
    private static func leadingWord(in characters: [Character], at offset: Int) -> String {
        var end = offset
        while end < characters.count,
              characters[end].isLetter || characters[end].isNumber || characters[end] == "_" || characters[end] == "." {
            end += 1
        }
        return String(characters[offset..<end])
    }
}
