import Foundation

/// Where each workbook's macros keep their files: a folder of its own under
/// `Macro Files` in the app's Documents, which on iOS the Files app shows
/// under Tables, and which no macro can see outside of.
enum MacroFiles {
    /// Not translated: a folder's name is part of the paths macros build.
    static let containerName = "Macro Files"

    static var container: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(containerName, isDirectory: true)
    }

    /// The folder for a workbook, named after its file. It is created the
    /// first time a macro runs, not merely by asking.
    static func folder(forWorkbookNamed fileName: String?) -> URL {
        container.appendingPathComponent(folderName(for: fileName), isDirectory: true)
    }

    static func folderName(for fileName: String?) -> String {
        let stem = ((fileName ?? "") as NSString).deletingPathExtension
        // Characters a folder name cannot hold, and leading dots, which would
        // hide it or step outside the container.
        let cleaned = stem.components(separatedBy: CharacterSet(charactersIn: "/:\\\u{0}")).joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        return cleaned.isEmpty ? "Workbook" : cleaned
    }

}
