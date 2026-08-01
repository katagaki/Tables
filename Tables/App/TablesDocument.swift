import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The Office Open XML workbook type, declared by the system.
    static let openXMLWorkbook = UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data
}

/// The app's document: an entire workbook, loaded from `.xlsx` or `.csv`.
struct TablesDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.openXMLWorkbook, .commaSeparatedText, .tabSeparatedText]
    static let writableContentTypes: [UTType] = [
        .openXMLWorkbook, .commaSeparatedText, .tabSeparatedText
    ]

    var workbook: Workbook
    /// CSV holds a single sheet, so exporting picks one. Tracks the user's choice.
    var csvExportSheetIndex = 0

    /// What the opened file used that Tables cannot edit. Empty for anything we
    /// authored ourselves and for CSV, which has no such features to begin with.
    var unsupportedFeatures: UnsupportedFeatureReport { workbook.unsupportedFeatures }

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
        } ?? Workbook.defaultSheetName(1)

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
        // Tab separated text does not conform to the comma separated type, so
        // ask about it in its own right rather than relying on the order here.
        if configuration.contentType.conforms(to: .tabSeparatedText) {
            data = CSVCodec.data(from: exportSheet, delimiter: "\t")
        } else if configuration.contentType.conforms(to: .commaSeparatedText) {
            data = CSVCodec.data(from: exportSheet)
        } else {
            data = try XLSXWriter.data(from: workbook)
        }
        return FileWrapper(regularFileWithContents: data)
    }

    /// Saving as delimited text writes whichever sheet the user picked.
    private var exportSheet: Worksheet {
        workbook.sheet(at: csvExportSheetIndex)
    }
}
