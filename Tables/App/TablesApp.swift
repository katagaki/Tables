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

        // An empty system title: it cannot be styled, so `DocumentLaunchTitle`
        // draws the app's name itself, centred on glass.
        DocumentGroupLaunchScene(Text(verbatim: "")) {
            NewDocumentButton("Launch.NewWorkbook", contentType: .openXMLWorkbook)
        } background: {
            DocumentLaunchBackground()
        } backgroundAccessoryView: { geometry in
            DocumentLaunchFeatureWall(geometry: geometry)
        } overlayAccessoryView: { geometry in
            DocumentLaunchTitle(geometry: geometry)
        }
    }
}
