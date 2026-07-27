import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Wraps a workbook so it can be handed to `ShareLink`. The `.xlsx` is written
/// lazily, only when the user actually picks a share destination.
struct WorkbookExport: Transferable, Sendable {
    var workbook: Workbook
    var name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .openXMLWorkbook) { export in
            SentTransferredFile(try export.write(extension: "xlsx") { workbook in
                try XLSXWriter.data(from: workbook)
            })
        }
        .suggestedFileName { $0.name + ".xlsx" }

        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            SentTransferredFile(try export.write(extension: "csv") { workbook in
                CSVCodec.data(from: workbook.sheets[0])
            })
        }
        .suggestedFileName { $0.name + ".csv" }
    }

    private func write(
        extension pathExtension: String, encode: (Workbook) throws -> Data
    ) throws -> URL {
        // A per-export directory keeps concurrent shares from colliding on name.
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Share-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appending(path: "\(sanitizedName).\(pathExtension)")
        try encode(workbook).write(to: url, options: .atomic)
        return url
    }

    private var sanitizedName: String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Workbook" : cleaned
    }
}
