import PDFKit
import SwiftUI

struct PDFKitRepresentable: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPageIndex: $currentPageIndex)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = NSColor.underPageBackgroundColor
        context.coordinator.pdfView = view
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: Notification.Name.PDFViewPageChanged,
            object: view
        )
        return view
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        if let currentPage = pdfView.currentPage,
           document.index(for: currentPage) != currentPageIndex,
           let target = document.page(at: currentPageIndex) {
            pdfView.go(to: target)
        }
        pdfView.layoutDocumentView()
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    final class Coordinator: NSObject {
        @Binding var currentPageIndex: Int
        weak var pdfView: PDFView?

        init(currentPageIndex: Binding<Int>) {
            self._currentPageIndex = currentPageIndex
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView,
                  let page = pdfView.currentPage,
                  let document = pdfView.document else { return }
            currentPageIndex = document.index(for: page)
        }
    }
}
