import AppKit
import PDFKit
import SwiftUI

struct PDFURLPreview: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.pageBreakMargins = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.backgroundColor = .underPageBackgroundColor
        load(url, into: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        load(url, into: view, coordinator: context.coordinator)
    }

    private func load(_ url: URL, into view: PDFView, coordinator: Coordinator) {
        view.document = PDFDocument(url: url)
        coordinator.loadedURL = url
        DispatchQueue.main.async {
            view.autoScales = true
        }
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}

struct DocumentPreview: View {
    let url: URL

    var body: some View {
        Group {
            if url.pathExtension.lowercased() == "pdf" {
                if let document = PDFDocument(url: url), document.isLocked {
                    lockedPDF
                } else {
                    PDFURLPreview(url: url)
                }
            } else if let image = NSImage(contentsOf: url) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(28)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(AppTheme.canvasBackground)
            } else {
                unavailable
            }
        }
    }

    private var lockedPDF: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .thin))
            Text("Protected PDF")
                .font(.system(size: 14, weight: .semibold))
            Text("The document is password-protected, so its pages cannot be previewed until it is unlocked.")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .foregroundStyle(AppTheme.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.canvasBackground)
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 34, weight: .thin))
            Text("Preview unavailable")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(AppTheme.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.canvasBackground)
    }
}

struct PDFSummaryPreview: View {
    let url: URL

    private var document: PDFDocument? { PDFDocument(url: url) }

    var body: some View {
        VStack(spacing: 8) {
            if let document, let page = document.page(at: 0) {
                Image(nsImage: page.thumbnail(of: NSSize(width: 145, height: 185), for: .mediaBox))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 145, height: 185)
                    .background(Color.white)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

                Text("\(document.pageCount) \(document.pageCount == 1 ? "Page" : "Pages")")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppTheme.muted)
            } else {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 60, weight: .thin))
                    .foregroundStyle(AppTheme.muted)
                    .frame(width: 145, height: 185)
            }
        }
    }
}
