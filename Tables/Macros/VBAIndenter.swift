import Foundation

/// What pressing Return does in macro code: the line being finished snaps
/// to its block's indentation if it closes one — `End Sub` under `Sub`,
/// `Next` under `For`, `Else` under `If` — and the new line starts one step
/// in from a line that opens a block, level with anything else.
enum VBAIndenter {
    static let step = "    "

    struct Edit: Hashable, Sendable {
        /// The range to replace, in UTF-16 offsets.
        var range: NSRange
        var replacement: String
        /// Where the cursor goes afterwards.
        var cursor: Int
    }

    enum LineKind: Hashable, Sendable {
        case opener, middle, closer, other
    }

    static func returnEdit(in text: String, selection: NSRange) -> Edit {
        let source = text as NSString
        let lineStart = source.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let head = source.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
        // The rest of the line moves down, without the spaces that led it.
        var tailEnd = NSMaxRange(selection)
        while tailEnd < source.length, [0x20, 0x09].contains(source.character(at: tailEnd)) { tailEnd += 1 }

        let indent = leadingWhitespace(head)
        let content = String(head.dropFirst(indent.count))
        let kind = classify(content)
        var lineIndent = indent
        if kind == .closer || kind == .middle,
           let opener = enclosingOpener(before: lineStart, in: source) {
            lineIndent = opener.indent
            // `Case` sits a step inside its `Select`; the statements under it a step further.
            if kind == .middle, firstWord(opener.content) == "select", firstWord(content) == "case" {
                lineIndent += step
            }
        }
        let nextIndent = kind == .opener || kind == .middle ? lineIndent + step : lineIndent
        let replacement = lineIndent + content + "\n" + nextIndent
        return Edit(range: NSRange(location: lineStart, length: tailEnd - lineStart), replacement: replacement,
                    cursor: lineStart + replacement.utf16.count)
    }

    /// The nearest line above `location` that opens the block it is in.
    private static func enclosingOpener(before location: Int, in source: NSString) -> (indent: String, content: String)? {
        var depth = 0
        var end = location
        while end > 0 {
            let range = source.lineRange(for: NSRange(location: end - 1, length: 0))
            let line = source.substring(with: range).trimmingCharacters(in: .newlines)
            end = range.location
            let indent = leadingWhitespace(line)
            let content = String(line.dropFirst(indent.count))
            switch classify(content) {
            case .closer:
                depth += 1
            case .opener:
                if depth == 0 { return (indent, content) }
                depth -= 1
            case .middle, .other:
                continue
            }
        }
        return nil
    }

    static func classify(_ line: String) -> LineKind {
        let code = stripComment(line).trimmingCharacters(in: .whitespaces).lowercased()
        guard !code.isEmpty else { return .other }
        let words = code.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "(" || $0 == ":" }).map(String.init)
        guard let first = words.first else { return .other }
        let second = words.count > 1 ? words[1] : ""
        switch first {
        case "end":
            return ["sub", "function", "property", "if", "with", "select", "type", "enum"].contains(second) ? .closer : .other
        case "next", "loop", "wend":
            return .closer
        case "else", "elseif", "case":
            return .middle
        case "if", "#if":
            // Only the block form: `Then` with nothing after it.
            return code.hasSuffix(" then") || code == "if" ? .opener : .other
        case "for", "do", "while", "with":
            return .opener
        case "select":
            return second == "case" ? .opener : .other
        case "sub", "function", "property", "type", "enum":
            return .opener
        case "public", "private", "friend", "static", "global":
            let rest = words.dropFirst().drop { ["static", "public", "private", "friend"].contains($0) }
            guard let keyword = rest.first else { return .other }
            return ["sub", "function", "property", "type", "enum"].contains(keyword) ? .opener : .other
        default:
            return .other
        }
    }

    private static func firstWord(_ line: String) -> String {
        String(line.lowercased().prefix { $0.isLetter })
    }

    private static func leadingWhitespace(_ line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    /// The line without its `'` comment, quotes inside strings excepted.
    private static func stripComment(_ line: String) -> String {
        var inString = false
        for index in line.indices {
            switch line[index] {
            case "\"": inString.toggle()
            case "'" where !inString: return String(line[..<index])
            default: continue
            }
        }
        return line
    }
}
