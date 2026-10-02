import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

private enum SplitMode: String, CaseIterable, Identifiable {
    case ranges = "Page ranges"
    case everyN = "Every N pages"
    var id: String { rawValue }
}

struct ToolWorkflowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var entitlements: EntitlementManager
    @EnvironmentObject private var history: HistoryStore

    let toolID: PDFToolID

    @State private var files: [URL] = []
    @State private var previewURL: URL?
    @State private var livePreviewURLs: [URL] = []
    @State private var livePreviewDirectory: URL?
    @State private var finalDirectory: URL?
    @State private var previewTask: Task<Void, Never>?
    @State private var previewGeneration = UUID()
    @State private var isRenderingPreview = false
    @State private var didConsumePendingFiles = false

    @State private var pageExpression = ""
    @State private var splitMode: SplitMode = .ranges
    @State private var everyNPages = 2
    @State private var rotationDegrees = 90
    @State private var compressionPreset: CompressionPreset = .balanced
    @State private var imageFormat: ImageOutputFormat = .jpeg
    @State private var imageDPI: Double = 144
    @State private var jpegQuality: Double = 0.85
    @State private var imagePageSize: PDFImagePageSize = .a4
    @State private var imageFitMode: ImageFitMode = .fit
    @State private var watermarkText = "CONFIDENTIAL"
    @State private var watermarkOpacity: Double = 0.28
    @State private var watermarkSize: Double = 30
    @State private var watermarkCenter = CGPoint(x: 0.5, y: 0.5)
    @State private var password = ""
    @State private var confirmPassword = ""

    @State private var isProcessing = false
    @State private var results: [ProcessingResult] = []
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var previewStatusMessage: String?

    private var tool: PDFToolDefinition { ToolRegistry.tool(toolID) }
    private var maxBytes: Int64 { entitlements.isPro ? AppConfig.proFileLimitBytes : AppConfig.freeFileLimitBytes }

    var body: some View {
        alertContent
    }

    // Keep the root body intentionally small. SwiftUI builds deeply nested generic
    // types for every modifier; splitting the modifier chain avoids the compiler
    // "unable to type-check this expression in reasonable time" error.
    private var baseContent: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if tool.isComingSoon {
                comingSoon
            } else {
                HStack(spacing: 0) {
                    filesPanel
                        .frame(width: 300)
                    Divider()
                    previewPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    optionsPanel
                        .frame(width: 330)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppTheme.windowBackground)
    }

    private var lifecycleContent: some View {
        baseContent
            .onAppear(perform: handleAppear)
            .onDisappear(perform: handleDisappear)
    }

    private var documentOptionObservedContent: some View {
        lifecycleContent
            .onChange(of: pageExpression) { _, _ in scheduleLivePreview() }
            .onChange(of: splitMode) { _, _ in scheduleLivePreview() }
            .onChange(of: everyNPages) { _, _ in scheduleLivePreview() }
            .onChange(of: rotationDegrees) { _, _ in scheduleLivePreview() }
            .onChange(of: compressionPreset) { _, _ in scheduleLivePreview() }
    }

    private var imageOptionObservedContent: some View {
        documentOptionObservedContent
            .onChange(of: imageFormat) { _, _ in scheduleLivePreview() }
            .onChange(of: imageDPI) { _, _ in scheduleLivePreview() }
            .onChange(of: jpegQuality) { _, _ in scheduleLivePreview() }
            .onChange(of: imagePageSize) { _, _ in scheduleLivePreview() }
            .onChange(of: imageFitMode) { _, _ in scheduleLivePreview() }
    }

    private var watermarkOptionObservedContent: some View {
        imageOptionObservedContent
            .onChange(of: watermarkText) { _, _ in scheduleLivePreview() }
            .onChange(of: watermarkOpacity) { _, _ in scheduleLivePreview() }
            .onChange(of: watermarkSize) { _, _ in scheduleLivePreview() }
            .onChange(of: watermarkCenter) { _, _ in scheduleLivePreview() }
    }

    private var previewObservedContent: some View {
        watermarkOptionObservedContent
            .onChange(of: password) { _, _ in
                if toolID == .unlock {
                    scheduleLivePreview()
                }
            }
    }

    private var alertContent: some View {
        previewObservedContent
            .alert("PDF Toolkit", isPresented: errorAlertPresented) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func handleAppear() {
        guard !didConsumePendingFiles else { return }
        didConsumePendingFiles = true

        let pending = appState.consumePendingFiles(for: toolID)
        if !pending.isEmpty {
            addChosenFiles(pending)
        }
    }

    private func handleDisappear() {
        previewTask?.cancel()

        if let livePreviewDirectory {
            Task {
                await TemporaryFileManager.shared.cleanup(livePreviewDirectory)
            }
        }

        if let finalDirectory {
            Task {
                await TemporaryFileManager.shared.cleanup(finalDirectory)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                appState.destination = .tools
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 11))
                    .frame(minWidth: 62, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            RoundedRectangle(cornerRadius: 8)
                .fill(tool.tint.opacity(0.13))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: tool.systemImage)
                        .foregroundStyle(tool.tint)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(tool.title)
                        .font(.system(size: 16, weight: .semibold))
                    if tool.tier == .free || !entitlements.isPro {
                        TierBadge(tier: tool.tier)
                    }
                }
                Text(tool.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(isRenderingPreview ? AppTheme.warning : AppTheme.success)
                    .frame(width: 7, height: 7)
                Text(isRenderingPreview ? "Updating preview…" : "Live preview")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(AppTheme.muted)

            Text("Limit \(ByteCountFormatter.string(fromByteCount: maxBytes, countStyle: .file))/file")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, 20)
        .frame(height: 62)
        .background(AppTheme.surface)
    }

    private var comingSoon: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 18)
                .fill(tool.tint.opacity(0.13))
                .frame(width: 92, height: 92)
                .overlay {
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 39, weight: .medium))
                        .foregroundStyle(tool.tint)
                }
            Text("OCR PDF is Coming Soon")
                .font(.system(size: 22, weight: .semibold))
            Text("OCR remains an optional/stretch feature in the supplied requirements. It is not shown as a purchasable unlock until searchable-text output and review are implemented and validated.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button("Back to Tools") { appState.destination = .tools }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filesPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("1  Add files")
                .font(.system(size: 14, weight: .semibold))

            Button {
                chooseFiles()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: acceptsImages ? "photo.badge.plus" : "arrow.up.doc")
                        .font(.system(size: 27, weight: .thin))
                        .foregroundStyle(AppTheme.blue)
                    Text(filePrompt)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.text)
                        .multilineTextAlignment(.center)
                    Text("Click to choose or drag files here")
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.muted)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .background(AppTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.blue.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6]))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dropDestination(for: URL.self) { dropped, _ in
                addChosenFiles(dropped)
                return true
            }

            if !files.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(files.enumerated()), id: \.element) { index, url in
                            fileRow(url, index: index)
                            if index < files.count - 1 { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 210)
                .cardStyle()
            }

            if isProcessing {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Creating final output…")
                        .font(.system(size: 11, weight: .medium))
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.success)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !results.isEmpty {
                resultPanel
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(AppTheme.windowBackground)
    }

    private var previewPanel: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text("Live Preview")
                            .font(.system(size: 13, weight: .semibold))
                        if isRenderingPreview {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    Text(previewURL?.lastPathComponent ?? "Select files to preview the actual content")
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                }
                Spacer()

                if let url = previewURL, url.pathExtension.lowercased() == "pdf" {
                    Button {
                        openInCanvas(url)
                    } label: {
                        Label("Open in Canvas", systemImage: "rectangle.and.pencil.and.ellipsis")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(AppTheme.surface)

            if toolID == .watermark, let sourceURL = files.first {
                InteractiveWatermarkPreview(
                    url: sourceURL,
                    pageExpression: pageExpression,
                    text: watermarkText,
                    opacity: watermarkOpacity,
                    fontSize: $watermarkSize,
                    normalizedCenter: $watermarkCenter
                )
            } else if let previewURL {
                DocumentPreview(url: previewURL)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 42, weight: .thin))
                    Text("No document selected")
                        .font(.system(size: 13, weight: .medium))
                    Text("Choose or drop files. The center area shows the real source immediately and, for editable tool options, automatically regenerates the expected output while you change settings.")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(AppTheme.muted)
                .background(AppTheme.canvasBackground)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let previewStatusMessage {
                    Text(previewStatusMessage)
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if livePreviewURLs.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 7) {
                            ForEach(Array(livePreviewURLs.enumerated()), id: \.element) { index, url in
                                Button {
                                    previewURL = url
                                } label: {
                                    Text("Output \(index + 1)")
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 9)
                                        .frame(height: 27)
                                        .background(previewURL == url ? AppTheme.blue : AppTheme.elevatedSurface)
                                        .foregroundStyle(previewURL == url ? Color.white : AppTheme.text)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
        }
    }

    private var optionsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("2  Set options")
                    .font(.system(size: 14, weight: .semibold))

                optionControls

                Divider().padding(.vertical, 2)

                HStack(spacing: 7) {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(AppTheme.blue)
                    Text("Changes above update the preview automatically where the operation has a visual output.")
                }
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

                Text("3  Process")
                    .font(.system(size: 14, weight: .semibold))

                PrimaryButton(title: processingButtonTitle, systemImage: "sparkles", isDisabled: !canProcess || isProcessing) {
                    startProcessing()
                }

                if errorMessage != nil && !isProcessing {
                    Button("Retry") { startProcessing() }
                        .buttonStyle(.bordered)
                }

                Text("4  Download")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.top, 4)
                Text(results.isEmpty ? "The live preview is temporary. Process the tool to create validated output files, then save them from the Results panel." : "Final output is ready. Save the file you want; PDF-to-image can also export all results as a ZIP.")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.muted)

                Spacer(minLength: 12)
            }
            .padding(18)
        }
        .background(AppTheme.windowBackground)
    }

    @ViewBuilder
    private var optionControls: some View {
        switch toolID {
        case .merge:
            Text("Reorder the files with the arrow controls. The center preview is rebuilt in that exact page order.")
                .optionHelp()

        case .split:
            Picker("Split mode", selection: $splitMode) {
                ForEach(SplitMode.allCases) { Text($0.rawValue).tag($0) }
            }
            if splitMode == .ranges {
                TextField("Example: 1-3,5,8-10", text: $pageExpression)
                Text("Each comma-separated group becomes a separate PDF. The preview buttons below the document let you inspect each generated part.").optionHelp()
            } else {
                Stepper("Pages per file: \(everyNPages)", value: $everyNPages, in: 1...100)
            }

        case .rotate:
            TextField("Pages, e.g. 1-3,5 (blank = all)", text: $pageExpression)
            Picker("Rotation", selection: $rotationDegrees) {
                Text("90°").tag(90)
                Text("180°").tag(180)
                Text("270°").tag(270)
            }
            Text("The selected pages visibly rotate in the center preview before you create the final file.").optionHelp()

        case .compress:
            Picker("Compression", selection: $compressionPreset) {
                ForEach(CompressionPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            Text("Low keeps content structure where possible. Balanced/Strong may rasterize pages; the preview lets you inspect the resulting visual quality before final processing.").optionHelp()

        case .pdfToImages:
            TextField("Page range (blank = all)", text: $pageExpression)
            Picker("Output", selection: $imageFormat) {
                ForEach(ImageOutputFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            VStack(alignment: .leading) {
                Text("Resolution: \(Int(imageDPI)) DPI").font(.system(size: 10))
                Slider(value: $imageDPI, in: 72...300, step: 12)
            }
            if imageFormat == .jpeg {
                VStack(alignment: .leading) {
                    Text("JPEG quality: \(Int(jpegQuality * 100))%").font(.system(size: 10))
                    Slider(value: $jpegQuality, in: 0.35...1.0, step: 0.05)
                }
            }
            Text("For speed, Live Preview renders the first selected output page at the chosen format/quality. Final Process exports all selected pages.").optionHelp()

        case .imagesToPDF:
            Picker("Page size", selection: $imagePageSize) {
                ForEach(PDFImagePageSize.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Image fit", selection: $imageFitMode) {
                ForEach(ImageFitMode.allCases) { Text($0.rawValue).tag($0) }
            }
            Text("Fit prevents unintended cropping; Fill intentionally crops edges when needed. Reorder images on the left and the PDF preview updates.").optionHelp()

        case .watermark:
            TextField("Watermark text", text: $watermarkText)
            TextField("Page range (blank = all)", text: $pageExpression)
            VStack(alignment: .leading) {
                Text("Opacity: \(Int(watermarkOpacity * 100))%")
                    .font(.system(size: 10))
                Slider(value: $watermarkOpacity, in: 0.05...1.0, step: 0.01)
            }
            HStack(spacing: 10) {
                Stepper("Text size: \(Int(watermarkSize)) pt", value: $watermarkSize, in: 6...360, step: 2)
                Spacer()
                Button("Center") {
                    watermarkCenter = CGPoint(x: 0.5, y: 0.5)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text("Drag the watermark directly on the preview. Drag a blue handle to resize it. Position and size are applied to every selected page.").optionHelp()

        case .protect:
            SecureField("Password", text: $password)
            SecureField("Confirm password", text: $confirmPassword)
            passwordStrength
            Text("Encryption does not visually change a page, so the source PDF remains the exact visual preview. The final file is written with an open password and validated after creation. Passwords are not added to history or logs.").optionHelp()

        case .unlock:
            SecureField("PDF password", text: $password)
            Text("Enter the authorized password. When it is correct, the unlocked PDF itself appears in Live Preview before final processing.").optionHelp()

        case .ocr:
            EmptyView()
        }
    }

    private var passwordStrength: some View {
        let strength: (String, Color) = {
            if password.count >= 12 && password.rangeOfCharacter(from: .decimalDigits) != nil { return ("Strong", AppTheme.success) }
            if password.count >= 8 { return ("Medium", AppTheme.warning) }
            return ("Weak", AppTheme.danger)
        }()
        return HStack {
            Text("Password strength")
            Spacer()
            Text(strength.0).foregroundStyle(strength.1).fontWeight(.semibold)
        }
        .font(.system(size: 10))
    }

    private func fileRow(_ url: URL, index: Int) -> some View {
        HStack(spacing: 9) {
            MiniFilePreview(url: url, isImage: acceptsImages)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                Text(fileSizeText(url))
                    .font(.system(size: 8))
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: 4)
            if allowsReorder {
                Button { move(index, by: -1) } label: {
                    Image(systemName: "arrow.up")
                        .frame(width: 25, height: 25)
                        .contentShape(Rectangle())
                }
                .disabled(index == 0)
                Button { move(index, by: 1) } label: {
                    Image(systemName: "arrow.down")
                        .frame(width: 25, height: 25)
                        .contentShape(Rectangle())
                }
                .disabled(index == files.count - 1)
            }
            Button(role: .destructive) {
                removeFile(at: index)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 25, height: 25)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .frame(height: 62)
        .background(previewURL == url ? AppTheme.blue.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
        .draggable(url.absoluteString)
        .dropDestination(for: String.self) { items, _ in
            guard allowsReorder,
                  let raw = items.first,
                  let sourceURL = URL(string: raw),
                  let sourceIndex = files.firstIndex(of: sourceURL),
                  files.indices.contains(index) else { return false }
            var updated = files
            let moved = updated.remove(at: sourceIndex)
            let destinationIndex = sourceIndex < index ? max(0, index - 1) : index
            updated.insert(moved, at: min(destinationIndex, updated.count))
            files = updated
            scheduleLivePreview()
            return true
        }
        .onTapGesture {
            previewTask?.cancel()
            previewURL = url
            previewStatusMessage = "Showing source file. Change an option to return to the generated live preview."
        }
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Results")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("Clear") { clearResults() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.muted)
                    .frame(minHeight: 30)
                    .contentShape(Rectangle())
            }
            .padding(10)
            Divider()

            ForEach(results) { result in
                HStack(spacing: 9) {
                    Image(systemName: result.url.pathExtension.lowercased() == "pdf" ? "doc.fill" : "photo.fill")
                        .foregroundStyle(result.url.pathExtension.lowercased() == "pdf" ? Color.red : AppTheme.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.displayName).font(.system(size: 9, weight: .medium)).lineLimit(1)
                        Text(result.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
                            .font(.system(size: 8)).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    Button("Save & Open") { saveResult(result) }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
                .padding(9)
                .background(previewURL == result.url ? AppTheme.blue.opacity(0.10) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    previewURL = result.url
                    previewStatusMessage = "Showing final processed output."
                }
                Divider()
            }

            if toolID == .pdfToImages && results.count > 1 {
                Button {
                    saveAllResultsAsZIP()
                } label: {
                    Label("Save all as ZIP", systemImage: "archivebox")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.blue)
                .padding(8)
            }
        }
        .cardStyle()
    }

    private var acceptsImages: Bool { toolID == .imagesToPDF }
    private var allowsMultipleFiles: Bool { toolID == .merge || toolID == .imagesToPDF }
    private var allowsReorder: Bool { toolID == .merge || toolID == .imagesToPDF }

    private var filePrompt: String {
        switch toolID {
        case .merge: return "Choose two or more PDF files"
        case .imagesToPDF: return "Choose JPG/PNG image files"
        default: return "Choose a PDF file"
        }
    }

    private var canProcess: Bool {
        switch toolID {
        case .merge: return files.count >= 2
        case .imagesToPDF: return !files.isEmpty
        case .protect: return files.count == 1 && password.count >= 6 && password == confirmPassword
        case .unlock: return files.count == 1 && !password.isEmpty
        case .split: return files.count == 1 && (splitMode == .everyN || !pageExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        default: return files.count == 1
        }
    }

    private var processingButtonTitle: String {
        switch toolID {
        case .merge: return "Merge PDF"
        case .split: return "Split PDF"
        case .rotate: return "Rotate PDF"
        case .compress: return "Compress PDF"
        case .pdfToImages: return "Export Images"
        case .imagesToPDF: return "Create PDF"
        case .watermark: return "Add Watermark"
        case .protect: return "Protect PDF"
        case .unlock: return "Unlock PDF"
        case .ocr: return "Coming Soon"
        }
    }

    private func chooseFiles() {
        let chosen = acceptsImages
            ? PanelService.chooseImages(allowsMultiple: allowsMultipleFiles)
            : PanelService.choosePDFs(allowsMultiple: allowsMultipleFiles)
        addChosenFiles(chosen)
    }

    private func addChosenFiles(_ chosen: [URL]) {
        guard !chosen.isEmpty else { return }
        do {
            for url in chosen {
                if acceptsImages {
                    try PDFService.validateImage(url, maxBytes: maxBytes)
                } else {
                    try PDFService.validatePDF(url, maxBytes: maxBytes)
                }
            }

            clearResults()

            if allowsMultipleFiles {
                var combined = files
                for url in chosen where !combined.contains(url) {
                    combined.append(url)
                }
                files = combined
            } else {
                files = Array(chosen.prefix(1))
            }
            previewURL = files.first
            previewStatusMessage = "Source loaded. Building Live Preview…"
            scheduleLivePreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeFile(at index: Int) {
        guard files.indices.contains(index) else { return }
        files.remove(at: index)
        clearResults()
        previewURL = files.first
        scheduleLivePreview()
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard files.indices.contains(index), files.indices.contains(target) else { return }
        files.swapAt(index, target)
        scheduleLivePreview()
    }

    private func fileSizeText(_ url: URL) -> String {
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func openInCanvas(_ url: URL) {
        guard url.pathExtension.lowercased() == "pdf" else { return }

        let tempContainers = [livePreviewDirectory, finalDirectory].compactMap { $0 }
        if let container = tempContainers.first(where: { url.standardizedFileURL.path.hasPrefix($0.standardizedFileURL.path + "/") }) {
            Task {
                do {
                    let editorDirectory = try await TemporaryFileManager.shared.makeTemporaryDirectory(prefix: "editor")
                    let copyURL = editorDirectory.appendingPathComponent(url.lastPathComponent)
                    if FileManager.default.fileExists(atPath: copyURL.path) { try FileManager.default.removeItem(at: copyURL) }
                    try FileManager.default.copyItem(at: url, to: copyURL)
                    guard PDFDocument(url: copyURL) != nil else {
                        throw PDFProcessingError(message: "The temporary preview was not a readable PDF.")
                    }
                    _ = container
                    appState.destination = .editor(copyURL)
                } catch {
                    errorMessage = "Could not open the PDF in the canvas: \(error.localizedDescription)"
                }
            }
        } else {
            appState.destination = .editor(url)
        }
    }

    private func scheduleLivePreview() {
        previewTask?.cancel()
        guard !tool.isComingSoon, !files.isEmpty else {
            clearLivePreview(resetToSource: true)
            return
        }

        if toolID == .watermark {
            clearLivePreview(resetToSource: true)
            isRenderingPreview = false
            previewStatusMessage = "Interactive preview: drag the watermark to position it and drag a blue handle to resize it."
            return
        }

        let token = UUID()
        previewGeneration = token
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, previewGeneration == token else { return }
            await buildLivePreview(token: token)
        }
    }

    @MainActor
    private func buildLivePreview(token: UUID) async {
        guard previewGeneration == token else { return }
        isRenderingPreview = true
        previewStatusMessage = "Updating preview…"

        let localFiles = files
        let localToolID = toolID
        let localPageExpression = pageExpression
        let localSplitMode = splitMode
        let localEveryN = everyNPages
        let localRotation = rotationDegrees
        let localCompression = compressionPreset
        let localImageFormat = imageFormat
        let localDPI = imageDPI
        let localJPEGQuality = jpegQuality
        let localPageSize = imagePageSize
        let localFitMode = imageFitMode
        let localWatermarkText = watermarkText
        let localWatermarkOpacity = watermarkOpacity
        let localWatermarkSize = watermarkSize
        let localWatermarkCenter = watermarkCenter
        let localPassword = password
        let limit = maxBytes

        if localToolID == .protect {
            clearLivePreview(resetToSource: true)
            previewStatusMessage = "Live visual preview: encryption changes access, not page appearance. Final output will be password-protected."
            isRenderingPreview = false
            return
        }

        var newlyCreatedDirectory: URL?
        do {
            if localToolID == .merge && localFiles.count < 2 {
                clearLivePreview(resetToSource: true)
                previewStatusMessage = "Add at least two PDFs to see the merged output."
                isRenderingPreview = false
                return
            }
            if localToolID == .split && localSplitMode == .ranges && localPageExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clearLivePreview(resetToSource: true)
                previewStatusMessage = "Enter a page range to preview the split outputs."
                isRenderingPreview = false
                return
            }
            if localToolID == .unlock && localPassword.isEmpty {
                clearLivePreview(resetToSource: true)
                previewStatusMessage = "Enter the authorized password to preview the unlocked document."
                isRenderingPreview = false
                return
            }

            let directory = try await TemporaryFileManager.shared.makeTemporaryDirectory(prefix: "preview-\(localToolID.rawValue)")
            newlyCreatedDirectory = directory
            let outputURLs = try await Task.detached(priority: .userInitiated) { () throws -> [URL] in
                for url in localFiles {
                    if localToolID == .imagesToPDF {
                        try PDFService.validateImage(url, maxBytes: limit)
                    } else {
                        try PDFService.validatePDF(url, maxBytes: limit)
                    }
                }

                switch localToolID {
                case .merge:
                    let output = directory.appendingPathComponent("Live-Merged.pdf")
                    try PDFService.merge(localFiles, outputURL: output)
                    return [output]

                case .split:
                    guard let first = localFiles.first else { return [] }
                    if localSplitMode == .everyN {
                        return try PDFService.splitEveryN(first, every: localEveryN, outputDirectory: directory)
                    }
                    return try PDFService.split(first, pageExpression: localPageExpression, outputDirectory: directory)

                case .rotate:
                    let output = directory.appendingPathComponent("Live-Rotated.pdf")
                    try PDFService.rotate(localFiles[0], pagesExpression: localPageExpression, degrees: localRotation, outputURL: output)
                    return [output]

                case .compress:
                    let output = directory.appendingPathComponent("Live-Compressed.pdf")
                    try PDFService.compress(localFiles[0], preset: localCompression, outputURL: output)
                    return [output]

                case .pdfToImages:
                    guard let document = PDFDocument(url: localFiles[0]) else { return [] }
                    let selected = try PDFService.flattenedPages(localPageExpression, pageCount: document.pageCount, emptyMeansAll: true)
                    guard let firstPage = selected.first else { return [] }
                    return try PDFService.pdfToImages(
                        localFiles[0],
                        pagesExpression: String(firstPage),
                        format: localImageFormat,
                        dpi: CGFloat(localDPI),
                        jpegQuality: CGFloat(localJPEGQuality),
                        outputDirectory: directory
                    )

                case .imagesToPDF:
                    let output = directory.appendingPathComponent("Live-Images.pdf")
                    try PDFService.imagesToPDF(localFiles, pageSize: localPageSize, fitMode: localFitMode, outputURL: output)
                    return [output]

                case .watermark:
                    guard !localWatermarkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
                    let output = directory.appendingPathComponent("Live-Watermark.pdf")
                    try PDFService.watermark(
                        localFiles[0],
                        text: localWatermarkText,
                        opacity: CGFloat(localWatermarkOpacity),
                        fontSize: CGFloat(localWatermarkSize),
                        normalizedCenter: localWatermarkCenter,
                        pagesExpression: localPageExpression,
                        outputURL: output
                    )
                    return [output]

                case .unlock:
                    let output = directory.appendingPathComponent("Live-Unlocked.pdf")
                    try PDFService.unlock(localFiles[0], password: localPassword, outputURL: output)
                    return [output]

                case .protect, .ocr:
                    return []
                }
            }.value

            guard previewGeneration == token, !Task.isCancelled else {
                await TemporaryFileManager.shared.cleanup(directory)
                isRenderingPreview = false
                return
            }

            let oldDirectory = livePreviewDirectory
            livePreviewDirectory = directory
            newlyCreatedDirectory = nil
            livePreviewURLs = outputURLs
            previewURL = outputURLs.first ?? files.first

            if localToolID == .pdfToImages {
                previewStatusMessage = "Live output preview of the first selected page using the chosen \(localImageFormat.rawValue), resolution and quality."
            } else if outputURLs.count > 1 {
                previewStatusMessage = "Live output generated. Use the Output buttons below to inspect each result before final processing."
            } else {
                previewStatusMessage = "Live output generated from the current settings. Change an option and this view updates again."
            }

            if let oldDirectory, oldDirectory != directory {
                Task { await TemporaryFileManager.shared.cleanup(oldDirectory) }
            }
        } catch {
            if let newlyCreatedDirectory {
                await TemporaryFileManager.shared.cleanup(newlyCreatedDirectory)
            }
            if previewGeneration == token {
                clearLivePreview(resetToSource: true)
                previewStatusMessage = "Live Preview is waiting for valid settings: \(error.localizedDescription)"
            }
        }
        isRenderingPreview = false
    }

    private func startProcessing() {
        guard canProcess, !isProcessing else { return }
        errorMessage = nil
        statusMessage = nil
        clearResults()
        isProcessing = true

        let localFiles = files
        let localToolID = toolID
        let localPageExpression = pageExpression
        let localSplitMode = splitMode
        let localEveryN = everyNPages
        let localRotation = rotationDegrees
        let localCompression = compressionPreset
        let localImageFormat = imageFormat
        let localDPI = imageDPI
        let localJPEGQuality = jpegQuality
        let localPageSize = imagePageSize
        let localFitMode = imageFitMode
        let localWatermarkText = watermarkText
        let localWatermarkOpacity = watermarkOpacity
        let localWatermarkSize = watermarkSize
        let localWatermarkCenter = watermarkCenter
        let localPassword = password
        let limit = maxBytes

        Task {
            do {
                let directory = try await TemporaryFileManager.shared.makeTemporaryDirectory(prefix: "final-\(localToolID.rawValue)")
                finalDirectory = directory

                let outputURLs = try await Task.detached(priority: .userInitiated) { () throws -> [URL] in
                    for url in localFiles {
                        if localToolID == .imagesToPDF {
                            try PDFService.validateImage(url, maxBytes: limit)
                        } else {
                            try PDFService.validatePDF(url, maxBytes: limit)
                        }
                    }

                    switch localToolID {
                    case .merge:
                        let output = directory.appendingPathComponent("Merged.pdf")
                        try PDFService.merge(localFiles, outputURL: output)
                        return [output]
                    case .split:
                        guard let first = localFiles.first else { return [] }
                        if localSplitMode == .everyN {
                            return try PDFService.splitEveryN(first, every: localEveryN, outputDirectory: directory)
                        }
                        return try PDFService.split(first, pageExpression: localPageExpression, outputDirectory: directory)
                    case .rotate:
                        let output = directory.appendingPathComponent("Rotated.pdf")
                        try PDFService.rotate(localFiles[0], pagesExpression: localPageExpression, degrees: localRotation, outputURL: output)
                        return [output]
                    case .compress:
                        let output = directory.appendingPathComponent("Compressed.pdf")
                        try PDFService.compress(localFiles[0], preset: localCompression, outputURL: output)
                        return [output]
                    case .pdfToImages:
                        return try PDFService.pdfToImages(localFiles[0], pagesExpression: localPageExpression, format: localImageFormat, dpi: CGFloat(localDPI), jpegQuality: CGFloat(localJPEGQuality), outputDirectory: directory)
                    case .imagesToPDF:
                        let output = directory.appendingPathComponent("Images.pdf")
                        try PDFService.imagesToPDF(localFiles, pageSize: localPageSize, fitMode: localFitMode, outputURL: output)
                        return [output]
                    case .watermark:
                        let output = directory.appendingPathComponent("Watermarked.pdf")
                        try PDFService.watermark(localFiles[0], text: localWatermarkText, opacity: CGFloat(localWatermarkOpacity), fontSize: CGFloat(localWatermarkSize), normalizedCenter: localWatermarkCenter, pagesExpression: localPageExpression, outputURL: output)
                        return [output]
                    case .protect:
                        let output = directory.appendingPathComponent("Protected.pdf")
                        try PDFService.protect(localFiles[0], password: localPassword, outputURL: output)
                        return [output]
                    case .unlock:
                        let output = directory.appendingPathComponent("Unlocked.pdf")
                        try PDFService.unlock(localFiles[0], password: localPassword, outputURL: output)
                        return [output]
                    case .ocr:
                        return []
                    }
                }.value

                try validateFinalOutputs(outputURLs)
                results = outputURLs.map { ProcessingResult(url: $0) }
                previewURL = outputURLs.first ?? files.first
                previewStatusMessage = "Showing validated final output."

                if toolID == .compress,
                   let source = files.first,
                   let result = results.first {
                    let oldSize = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    let newSize = result.size ?? 0
                    if oldSize > 0 {
                        let reduction = max(0, 1 - Double(newSize) / Double(oldSize))
                        let finalSize = ByteCountFormatter.string(fromByteCount: newSize, countStyle: .file)
                        if newSize >= oldSize {
                            statusMessage = "Already compact · Kept the smallest safe version · Final size: \(finalSize) · Reduction: 0%"
                        } else {
                            statusMessage = "Validated output · Final size: \(finalSize) · Reduction: \(Int(reduction * 100))%"
                        }
                    }
                } else {
                    statusMessage = "Completed and validated. Review the final output in the center, then Save."
                }
            } catch {
                if let directory = finalDirectory {
                    finalDirectory = nil
                    await TemporaryFileManager.shared.cleanup(directory)
                }
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }

    private func validateFinalOutputs(_ urls: [URL]) throws {
        guard !urls.isEmpty else {
            throw PDFProcessingError(message: "The tool did not produce an output file.")
        }
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw PDFProcessingError(message: "An expected output file was not created.")
            }
            let size = Int64((try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
            guard size > 0 else {
                throw PDFProcessingError(message: "An output file was empty and was rejected.")
            }
            if url.pathExtension.lowercased() == "pdf" {
                guard let document = PDFDocument(url: url) else {
                    throw PDFProcessingError(message: "The generated PDF failed validation and will not be offered for saving.")
                }
                if toolID == .protect {
                    guard document.isLocked else {
                        throw PDFProcessingError(message: "The protected PDF was created without the expected password lock.")
                    }
                } else if document.pageCount <= 0 {
                    throw PDFProcessingError(message: "The generated PDF contains no readable pages.")
                }
            } else {
                guard NSImage(contentsOf: url) != nil else {
                    throw PDFProcessingError(message: "A generated image failed validation and will not be offered for saving.")
                }
            }
        }
    }

    private func saveResult(_ result: ProcessingResult) {
        let ext = result.url.pathExtension.lowercased()
        let type: UTType = ext == "pdf" ? .pdf : (ext == "png" ? .png : .jpeg)
        guard let destination = PanelService.saveFile(suggestedName: result.displayName, allowedType: type) else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: result.url, to: destination)

            let savedSize = Int64((try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
            guard savedSize > 0 else { throw PDFProcessingError(message: "The saved file is empty.") }
            if ext == "pdf" {
                guard let savedDocument = PDFDocument(url: destination) else {
                    throw PDFProcessingError(message: "The saved file could not be reopened as a PDF.")
                }
                if toolID == .protect {
                    guard savedDocument.isLocked else {
                        throw PDFProcessingError(message: "The saved protected PDF did not retain its password protection.")
                    }
                } else if savedDocument.pageCount <= 0 {
                    throw PDFProcessingError(message: "The saved PDF contains no readable pages.")
                }
            }
            if ext != "pdf", NSImage(contentsOf: destination) == nil {
                throw PDFProcessingError(message: "The saved image could not be reopened.")
            }

            history.addSavedFile(toolID: toolID, url: destination, outputSize: savedSize)
            statusMessage = "Saved and verified \(destination.lastPathComponent)"
            NSWorkspace.shared.open(destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func saveAllResultsAsZIP() {
        guard !results.isEmpty else { return }
        Task {
            do {
                let directory: URL
                if let finalDirectory {
                    directory = finalDirectory
                } else {
                    directory = try await TemporaryFileManager.shared.makeTemporaryDirectory(prefix: "zip")
                    finalDirectory = directory
                }
                let zipURL = directory.appendingPathComponent("PDF-Images.zip")
                let resultURLs = results.map(\.url)
                try await Task.detached(priority: .userInitiated) {
                    try PDFService.createZIP(from: resultURLs, outputURL: zipURL)
                }.value

                guard let destination = PanelService.saveFile(suggestedName: "PDF-Images.zip", allowedType: .zip) else { return }
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: zipURL, to: destination)
                let size = Int64((try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
                guard size > 0 else { throw PDFProcessingError(message: "The ZIP archive is empty.") }
                statusMessage = "Saved \(destination.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clearLivePreview(resetToSource: Bool) {
        previewTask?.cancel()
        livePreviewURLs = []
        if resetToSource { previewURL = files.first }
        if let livePreviewDirectory {
            Task { await TemporaryFileManager.shared.cleanup(livePreviewDirectory) }
            self.livePreviewDirectory = nil
        }
    }

    private func clearResults() {
        results = []
        statusMessage = nil
        if let finalDirectory {
            let directory = finalDirectory
            self.finalDirectory = nil
            Task { await TemporaryFileManager.shared.cleanup(directory) }
        }
    }
}


private struct InteractiveWatermarkPreview: NSViewRepresentable {
    let url: URL
    let pageExpression: String
    let text: String
    let opacity: Double
    @Binding var fontSize: Double
    @Binding var normalizedCenter: CGPoint

    func makeNSView(context: Context) -> WatermarkPreviewHostView {
        let view = WatermarkPreviewHostView()
        view.onCenterChange = { point in
            DispatchQueue.main.async {
                normalizedCenter = point
            }
        }
        view.onFontSizeChange = { size in
            DispatchQueue.main.async {
                fontSize = size
            }
        }
        return view
    }

    func updateNSView(_ nsView: WatermarkPreviewHostView, context: Context) {
        nsView.configure(
            url: url,
            pageExpression: pageExpression,
            text: text,
            opacity: opacity,
            fontSize: fontSize,
            normalizedCenter: normalizedCenter
        )
    }
}

private final class WatermarkPreviewHostView: NSView {
    private let pageView = WatermarkPreviewPageView()
    private var sourceURL: URL?
    private var document: PDFDocument?

    var onCenterChange: ((CGPoint) -> Void)? {
        didSet { pageView.onCenterChange = onCenterChange }
    }
    var onFontSizeChange: ((Double) -> Void)? {
        didSet { pageView.onFontSizeChange = onFontSizeChange }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        addSubview(pageView)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    func configure(
        url: URL,
        pageExpression: String,
        text: String,
        opacity: Double,
        fontSize: Double,
        normalizedCenter: CGPoint
    ) {
        if sourceURL != url {
            sourceURL = url
            document = PDFDocument(url: url)
        }

        guard let document, document.pageCount > 0 else {
            pageView.page = nil
            pageView.needsDisplay = true
            return
        }

        let requestedPages = try? PDFService.flattenedPages(
            pageExpression,
            pageCount: document.pageCount,
            emptyMeansAll: true
        )
        let pageIndex = max(0, min(document.pageCount - 1, (requestedPages?.first ?? 1) - 1))

        pageView.page = document.page(at: pageIndex)
        pageView.watermarkText = text
        pageView.watermarkOpacity = opacity
        pageView.watermarkFontSize = fontSize
        pageView.normalizedCenter = normalizedCenter
        pageView.needsDisplay = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let page = pageView.page else {
            pageView.frame = bounds
            return
        }

        let source = page.bounds(for: .mediaBox).size
        guard source.width > 0, source.height > 0 else { return }

        let available = bounds.insetBy(dx: 18, dy: 18)
        let scale = min(available.width / source.width, available.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        pageView.displayScale = scale
        pageView.frame = CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        pageView.needsDisplay = true
    }
}

private final class WatermarkPreviewPageView: NSView {
    enum Interaction {
        case none
        case move
        case resize
    }

    var page: PDFPage?
    var watermarkText = ""
    var watermarkOpacity: Double = 0.28
    var watermarkFontSize: Double = 30
    var normalizedCenter = CGPoint(x: 0.5, y: 0.5)
    var displayScale: CGFloat = 1

    var onCenterChange: ((CGPoint) -> Void)?
    var onFontSizeChange: ((Double) -> Void)?

    private var interaction: Interaction = .none
    private var startPointer: CGPoint = .zero
    private var startCenter: CGPoint = .zero
    private var startFontSize: Double = 30
    private var startResizeDistance: CGFloat = 1
    private var watermarkRect: CGRect = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.white.setFill()
        NSBezierPath(rect: bounds).fill()

        if let page, let context = NSGraphicsContext.current?.cgContext {
            let pageBounds = page.bounds(for: .mediaBox)
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            context.scaleBy(
                x: bounds.width / max(1, pageBounds.width),
                y: bounds.height / max(1, pageBounds.height)
            )
            context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }

        drawWatermark()
    }

    private func drawWatermark() {
        let text = watermarkText.isEmpty ? " " : watermarkText
        let displayedFontSize = max(6, CGFloat(watermarkFontSize) * max(0.01, displayScale))
        let font = NSFont.systemFont(ofSize: displayedFontSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: CGFloat(min(1, max(0.02, watermarkOpacity)))),
            .paragraphStyle: paragraph
        ]
        let measured = (text as NSString).size(withAttributes: attributes)
        let boxSize = CGSize(width: max(30, measured.width + 18), height: max(24, measured.height + 10))
        let center = clampedDisplayCenter(for: boxSize)
        watermarkRect = CGRect(
            x: center.x - boxSize.width / 2,
            y: center.y - boxSize.height / 2,
            width: boxSize.width,
            height: boxSize.height
        )

        (text as NSString).draw(
            in: watermarkRect.insetBy(dx: 7, dy: 4),
            withAttributes: attributes
        )

        let selection = NSBezierPath(roundedRect: watermarkRect.insetBy(dx: -3, dy: -3), xRadius: 3, yRadius: 3)
        selection.lineWidth = 1.5
        AppTheme.nsBlue.setStroke()
        selection.stroke()

        for point in handleCenters() {
            let rect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            AppTheme.nsBlue.setStroke()
            let outline = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            outline.lineWidth = 1.5
            outline.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        startPointer = point
        startCenter = normalizedCenter
        startFontSize = watermarkFontSize

        if handleHit(at: point) {
            interaction = .resize
            startResizeDistance = max(1, distance(point, displayCenter))
        } else if watermarkRect.insetBy(dx: -8, dy: -8).contains(point) {
            interaction = .move
        } else {
            interaction = .none
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch interaction {
        case .none:
            return
        case .move:
            guard bounds.width > 0, bounds.height > 0 else { return }
            let dx = (point.x - startPointer.x) / bounds.width
            let dy = (point.y - startPointer.y) / bounds.height
            let next = CGPoint(
                x: min(1, max(0, startCenter.x + dx)),
                y: min(1, max(0, startCenter.y + dy))
            )
            normalizedCenter = next
            onCenterChange?(next)
            needsDisplay = true
        case .resize:
            let currentDistance = max(1, distance(point, displayCenter))
            let scale = currentDistance / startResizeDistance
            let nextSize = min(360, max(6, startFontSize * Double(scale)))
            watermarkFontSize = nextSize
            onFontSizeChange?(nextSize)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        interaction = .none
    }

    private var displayCenter: CGPoint {
        CGPoint(
            x: normalizedCenter.x * bounds.width,
            y: normalizedCenter.y * bounds.height
        )
    }

    private func clampedDisplayCenter(for boxSize: CGSize) -> CGPoint {
        let requested = displayCenter
        let halfW = min(boxSize.width, bounds.width) / 2
        let halfH = min(boxSize.height, bounds.height) / 2
        return CGPoint(
            x: min(max(requested.x, halfW), max(halfW, bounds.width - halfW)),
            y: min(max(requested.y, halfH), max(halfH, bounds.height - halfH))
        )
    }

    private func handleCenters() -> [CGPoint] {
        let r = watermarkRect.insetBy(dx: -3, dy: -3)
        return [
            CGPoint(x: r.minX, y: r.minY),
            CGPoint(x: r.midX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.midY),
            CGPoint(x: r.maxX, y: r.midY),
            CGPoint(x: r.minX, y: r.maxY),
            CGPoint(x: r.midX, y: r.maxY),
            CGPoint(x: r.maxX, y: r.maxY)
        ]
    }

    private func handleHit(at point: CGPoint) -> Bool {
        handleCenters().contains { center in
            CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24).contains(point)
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

private struct MiniFilePreview: View {
    let url: URL
    let isImage: Bool

    var body: some View {
        Group {
            if isImage, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let document = PDFDocument(url: url), let page = document.page(at: 0) {
                Image(nsImage: page.thumbnail(of: NSSize(width: 44, height: 54), for: .mediaBox))
                    .resizable()
                    .scaledToFit()
                    .background(Color.white)
            } else {
                Image(systemName: isImage ? "photo" : "doc.fill")
                    .foregroundStyle(isImage ? AppTheme.success : Color.red)
            }
        }
        .frame(width: 38, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.line, lineWidth: 1))
    }
}

private extension View {
    func optionHelp() -> some View {
        self
            .font(.system(size: 10))
            .foregroundStyle(AppTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
