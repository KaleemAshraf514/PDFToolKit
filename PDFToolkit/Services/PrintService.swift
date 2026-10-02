import AppKit
import PDFKit

@MainActor
enum PrintService {
    static func printFile(at url: URL) {
        if url.pathExtension.lowercased() == "pdf" {
            printPDF(at: url)
            return
        }

        guard let image = NSImage(contentsOf: url) else {
            showPrintError()
            return
        }

        let printableRect = NSRect(x: 0, y: 0, width: max(1, image.size.width), height: max(1, image.size.height))
        let imageView = NSImageView(frame: printableRect)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let operation = NSPrintOperation(view: imageView, printInfo: NSPrintInfo.shared)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }

    static func printPDF(at url: URL) {
        guard let document = PDFDocument(url: url), !document.isLocked else {
            showPrintError()
            return
        }
        print(document: document)
    }

    static func print(document: PDFDocument) {
        guard let operation = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true) else {
            showPrintError()
            return
        }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }

    private static func showPrintError() {
        let alert = NSAlert()
        alert.messageText = "Unable to Print"
        alert.informativeText = "The selected file cannot be opened for printing."
        alert.runModal()
    }
}
