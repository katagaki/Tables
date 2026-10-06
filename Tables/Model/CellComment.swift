import Foundation

/// A comment attached to a cell.
///
/// Excel has two kinds. A note is a single block of text with an author,
/// drawn as a sticky note beside the cell. A threaded comment is a
/// conversation: the first entry and the replies under it, each with an
/// author and a time, which can be marked resolved.
struct CellComment: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case note
        case thread
    }

    struct Entry: Hashable, Sendable, Identifiable {
        /// A GUID in braces, as Excel writes them, so replies can name their parent.
        var id: String
        var author: String
        var text: String
        var date: Date?

        init(id: String = CellComment.newIdentifier(), author: String, text: String, date: Date? = nil) {
            self.id = id
            self.author = author
            self.text = text
            self.date = date
        }
    }

    var kind: Kind
    /// The comment itself, then any replies, oldest first. A note has one.
    var entries: [Entry]
    var isResolved = false
    /// Whether a note stays on show rather than appearing on hover.
    var isAlwaysVisible = false

    init(kind: Kind, entries: [Entry], isResolved: Bool = false, isAlwaysVisible: Bool = false) {
        self.kind = kind
        self.entries = entries
        self.isResolved = isResolved
        self.isAlwaysVisible = isAlwaysVisible
    }

    /// A new note.
    static func note(author: String, text: String) -> CellComment {
        CellComment(kind: .note, entries: [Entry(author: author, text: text, date: Date())])
    }

    /// A new conversation.
    static func thread(author: String, text: String) -> CellComment {
        CellComment(kind: .thread, entries: [Entry(author: author, text: text, date: Date())])
    }

    var author: String { entries.first?.author ?? "" }
    var text: String { entries.first?.text ?? "" }

    static func newIdentifier() -> String {
        "{" + UUID().uuidString + "}"
    }
}
