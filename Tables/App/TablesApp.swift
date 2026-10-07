import SwiftUI

@main
struct TablesApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: TablesDocument()) { configuration in
            WorkbookView(document: configuration.$document, fileURL: configuration.fileURL)
        }
        #if os(macOS)
        .defaultSize(width: 1080, height: 720)
        #endif

        DocumentGroupLaunchScene(Text(verbatim: "Tables")) {
            NewDocumentButton("Launch.NewWorkbook", contentType: .openXMLWorkbook)
        } background: {
            DocumentLaunchBackground()
        } backgroundAccessoryView: { geometry in
            DocumentLaunchFeatureWall(geometry: geometry)
        }
    }
}
