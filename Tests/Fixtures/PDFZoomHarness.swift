// Only the disposable --zoom-only validation app uses this entry point.
import SwiftUI

@main struct PDFZoomValidationApp: App {
    var body: some Scene {
        WindowGroup {
            LecturePDFView(destination: LecturePDFDestination(
                url: Bundle.main.url(forResource: "programmingLanguages", withExtension: "pdf")!,
                page: ProcessInfo.processInfo.arguments.contains("--second-page") ? 2 : 1,
                title: "PDF zoom validation"))
        }
    }
}
