import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The Office Open XML workbook type, declared by the system.
    static let openXMLWorkbook = UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data
}

/// The app's document: an entire workbook, loaded from `.xlsx` or `.csv`.
struct TablesDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.openXMLWorkbook, .commaSeparatedText, .tabSeparatedText]
    static let writableContentTypes: [UTType] = [.openXMLWorkbook, .commaSeparatedText]

    var workbook: Workbook
    /// CSV holds a single sheet, so exporting picks one. Tracks the user's choice.
    var csvExportSheetIndex = 0

    init() {
        workbook = Workbook()
    }

    init(workbook: Workbook) {
        self.workbook = workbook
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let name = configuration.file.preferredFilename.map {
            ($0 as NSString).deletingPathExtension
        } ?? "Sheet 1"

        if configuration.contentType.conforms(to: .openXMLWorkbook) {
            workbook = try XLSXReader.workbook(from: data)
        } else if configuration.contentType.conforms(to: .commaSeparatedText)
                    || configuration.contentType.conforms(to: .tabSeparatedText)
                    || configuration.contentType.conforms(to: .text) {
            workbook = CSVCodec.workbook(from: data, sheetName: name)
        } else {
            // Fall back on content sniffing: ZIP packages start with "PK".
            if data.starts(with: [0x50, 0x4B]) {
                workbook = try XLSXReader.workbook(from: data)
            } else {
                workbook = CSVCodec.workbook(from: data, sheetName: name)
            }
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data: Data
        if configuration.contentType.conforms(to: .commaSeparatedText) {
            let index = min(max(0, csvExportSheetIndex), workbook.sheets.count - 1)
            data = CSVCodec.data(from: workbook.sheets[index])
        } else {
            data = try XLSXWriter.data(from: workbook)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
