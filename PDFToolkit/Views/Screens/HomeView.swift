import PDFKit
import SwiftUI
import UniformTypeIdentifiers

private struct SelectedDocument: Identifiable {
    let id = UUID()
    let url: URL
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var entitlements: EntitlementManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedDocument: SelectedDocument?
    @State private var errorMessage: String?
    @State private var isDropTargeted = false

    private let columns = [
        GridItem(.flexible(), spacing: 28),
        GridItem(.flexible(), spacing: 28)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Choose from...")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.text)

                LazyVGrid(columns: columns, spacing: 26) {
                    HomeSourceCard(
                        title: "Files",
                        subtitle: "Select PDF files from your Mac",
                        iconKind: .files
                    ) {
                        handleHomeFiles(PanelService.choosePDFs(allowsMultiple: true))
                    }

                    HomeSourceCard(
                        title: "Image",
                        subtitle: "Select an image to create a PDF",
                        iconKind: .image
                    ) {
                        let images = PanelService.chooseImages(allowsMultiple: true)
                        guard !images.isEmpty else { return }
                        openImagesTool(images)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 34)
            .frame(maxWidth: 1100, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(AppTheme.windowBackground)
        .dropDestination(for: URL.self) { urls, _ in
            handleHomeFiles(urls)
            return !urls.isEmpty
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.blue.opacity(colorScheme == .dark ? 0.055 : 0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.blue, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    }
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $selectedDocument) { selected in
            FileActionSheet(url: selected.url)
                .environmentObject(appState)
        }
        .alert("Unable to Open File", isPresented: errorAlertPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func handleHomeFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        let images = urls.filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }

        guard pdfs.count + images.count == urls.count else {
            errorMessage = "Only PDF, JPG and PNG files are supported here."
            return
        }

        guard pdfs.isEmpty || images.isEmpty else {
            errorMessage = "Drop PDFs or images in one operation, not a mixed selection."
            return
        }

        do {
            let maxBytes = entitlements.isPro ? AppConfig.proFileLimitBytes : AppConfig.freeFileLimitBytes

            if !pdfs.isEmpty {
                for url in pdfs {
                    try PDFService.validatePDF(url, maxBytes: maxBytes)
                }

                if pdfs.count == 1 {
                    selectedDocument = SelectedDocument(url: pdfs[0])
                } else {
                    appState.openTool(
                        ToolRegistry.tool(.merge),
                        entitlementManager: entitlements,
                        files: pdfs
                    )
                }
            } else {
                for url in images {
                    try PDFService.validateImage(url, maxBytes: maxBytes)
                }
                openImagesTool(images)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openImagesTool(_ images: [URL]) {
        guard !images.isEmpty else { return }
        do {
            let maxBytes = entitlements.isPro ? AppConfig.proFileLimitBytes : AppConfig.freeFileLimitBytes
            for url in images {
                try PDFService.validateImage(url, maxBytes: maxBytes)
            }
            appState.openTool(
                ToolRegistry.tool(.imagesToPDF),
                entitlementManager: entitlements,
                files: images
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum HomeSourceIconKind {
    case files
    case image
}

private struct HomeSourceCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    let iconKind: HomeSourceIconKind
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                FigmaHomeSourceIcon(kind: iconKind)

                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppTheme.text)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.38, green: 0.49, blue: 0.67))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(17)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .contentShape(Rectangle())
            .background(hovering ? AppTheme.blue.opacity(0.035) : AppTheme.softCardBackground(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(hovering ? AppTheme.blue.opacity(0.42) : AppTheme.line.opacity(0.62), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Recreates the Figma source icons rather than using generic SF Symbols.
/// The folder keeps the two-tone Finder-style silhouette and the image icon
/// uses the multicolour flower visible in the supplied design.
private struct FigmaHomeSourceIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    let kind: HomeSourceIconKind

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(colorScheme == .dark ? Color.black.opacity(0.18) : Color.white)
            .frame(width: 50, height: 50)
            .overlay {
                switch kind {
                case .files:
                    figmaFolder
                case .image:
                    figmaPhotoFlower
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(AppTheme.line.opacity(0.72), lineWidth: 1)
            }
    }

    private var figmaFolder: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: 30, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color(red: 0.19, green: 0.49, blue: 0.96))
            .offset(y: 1)
    }

    private var figmaPhotoFlower: some View {
        ZStack {
            petal(.red, x: 0, y: -14)
            petal(.orange, x: 10, y: -10)
            petal(.yellow, x: 14, y: 0)
            petal(.green, x: 10, y: 10)
            petal(.cyan, x: 0, y: 14)
            petal(.blue, x: -10, y: 10)
            petal(.purple, x: -14, y: 0)
            petal(.pink, x: -10, y: -10)

            Circle()
                .fill(Color.white.opacity(0.94))
                .frame(width: 10, height: 10)
                .overlay {
                    Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                }
        }
        .scaleEffect(0.82)
        .frame(width: 40, height: 40)
    }

    private func petal(_ color: Color, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: 21, height: 21)
            .offset(x: x, y: y)
    }
}

private struct FileActionSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let url: URL

    private var pageCount: Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.text)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }

            PDFSummaryPreview(url: url)

            Text(url.lastPathComponent)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Text("Which option would you like to choose?")
                .font(.system(size: 12, weight: .semibold))

            Text("This PDF has \(pageCount) \(pageCount == 1 ? "page" : "pages"). Preview/Edit opens the document workspace; Print uses the native macOS print system.")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 310)

            VStack(spacing: 10) {
                PrimaryButton(title: "Preview") {
                    dismiss()
                    appState.destination = .editor(url)
                }
                PrimaryButton(title: "Edit") {
                    dismiss()
                    appState.destination = .editor(url)
                }
                PrimaryButton(title: "Print") {
                    dismiss()
                    PrintService.printPDF(at: url)
                }
            }
        }
        .padding(20)
        .frame(width: 390)
        .background(AppTheme.surface)
    }
}
