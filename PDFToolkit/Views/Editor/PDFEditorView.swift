import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

private enum CanvasFrameComponent {
    case x
    case y
    case width
    case height
}

private enum ResizeHandlePosition: CaseIterable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight
}

struct PDFEditorView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var history: HistoryStore

    let url: URL
    @StateObject private var model: PDFEditorModel
    @State private var exportError: String?

    init(url: URL) {
        self.url = url
        _model = StateObject(wrappedValue: PDFEditorModel(url: url) ?? PDFEditorModel.placeholder(url: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            editorTopBar
            Divider()

            HStack(spacing: 0) {
                thumbnailSidebar
                Divider()
                NativePDFCanvas(model: model)
                    .background(AppTheme.canvasBackground)
                Divider()
                inspector
            }
        }
        .background(AppTheme.canvasBackground)
        .onDisappear {
            Task { await TemporaryFileManager.shared.cleanupContainer(containing: url) }
        }
        .alert("PDF Toolkit", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var editorTopBar: some View {
        HStack(spacing: 18) {
            Button {
                appState.destination = .home
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 10))
                    .frame(minWidth: 54, minHeight: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { model.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canUndo)
            .help("Undo")

            Button { model.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canRedo)
            .help("Redo")

            toolbarAction(
                title: "Text",
                icon: "textformat",
                isActive: model.interactionMode == .insertText
            ) {
                if model.interactionMode == .insertText {
                    model.cancelCanvasTool()
                } else {
                    model.beginTextInsertion()
                }
            }

            toolbarAction(title: "Stamp", icon: "person.crop.rectangle.stack") {
                model.select(nil)
                model.inspectorMode = .stamp
            }

            toolbarAction(title: "Image", icon: "photo.badge.plus") {
                addImage()
            }

            Spacer()

            if model.selectedElement != nil {
                Button {
                    model.duplicateSelectedElement()
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    model.removeSelectedElement()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                exportEditedPDF()
            } label: {
                Label("Export", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                shareEditedPDF()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                printEditedPDF()
            } label: {
                Label("Print", systemImage: "printer")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(AppTheme.surface)
    }

    private func toolbarAction(
        title: String,
        icon: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 8))
            }
            .frame(width: 50, height: 42)
            .background(isActive ? AppTheme.blue.opacity(0.12) : Color.clear)
            .foregroundStyle(isActive ? AppTheme.blue : AppTheme.text)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var thumbnailSidebar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                Text("\(model.currentPageIndex + 1)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.blue)
                    .frame(width: 26, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.blue, lineWidth: 1))
                Text("/\(max(1, model.pageCount))")
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(0..<model.pageCount, id: \.self) { index in
                        Button {
                            model.navigateToPage(index)
                        } label: {
                            VStack(spacing: 5) {
                                if let image = model.thumbnail(for: index) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: 120, maxHeight: 155)
                                        .background(Color.white)
                                }
                                Text("\(index + 1)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 19)
                                    .background(model.currentPageIndex == index ? AppTheme.blue : AppTheme.muted)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            .padding(5)
                            .contentShape(Rectangle())
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(model.currentPageIndex == index ? AppTheme.blue : Color.clear, lineWidth: 1.5)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
            }

            Divider()

            VStack(spacing: 7) {
                HStack(spacing: 6) {
                    Button { model.zoom = max(0.35, model.zoom - 0.10) } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Zoom out")

                    Slider(value: $model.zoom, in: 0.35...5.0, step: 0.05)

                    Button { model.zoom = min(5.0, model.zoom + 0.10) } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Zoom in")
                }

                HStack {
                    Button("Fit") { model.zoom = 1.0 }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppTheme.blue)
                    Spacer()
                    Text("\(Int(model.zoom * 100))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(width: 170)
        .background(AppTheme.surface)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(inspectorTitle)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if model.selectedElement != nil {
                    Text("Selected")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppTheme.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.blue.opacity(0.10))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let selected = model.selectedElement {
                        selectedInspector(selected)
                    } else {
                        emptyInspector
                    }
                }
                .padding(.bottom, 16)
            }

            Spacer(minLength: 0)

            if let status = model.statusMessage {
                Text(status)
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.success)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 265)
        .background(AppTheme.surface)
    }

    private var inspectorTitle: String {
        if let selected = model.selectedElement {
            switch selected.kind {
            case .text: return "Text"
            case .stamp: return "Stamp"
            case .image: return "Image"
            }
        }
        return model.inspectorMode.rawValue
    }

    @ViewBuilder
    private var emptyInspector: some View {
        switch model.inspectorMode {
        case .stamp:
            Text("Choose a stamp, then drag and resize it directly on the PDF.")
                .inspectorHelp()
            stampLibrary
        case .text:
            Text("Add text from the toolbar. The new object becomes selectable with drag/resize handles and full formatting controls here.")
                .inspectorHelp()
            PrimaryButton(title: "Add Text", systemImage: "plus") {
                model.beginTextInsertion()
            }
        case .image:
            Text("Add an image, then move, resize, rotate and style it on the page.")
                .inspectorHelp()
            PrimaryButton(title: "Add Image", systemImage: "photo.badge.plus") {
                addImage()
            }
        }
    }

    @ViewBuilder
    private func selectedInspector(_ selected: CanvasElement) -> some View {
        if selected.kind == .text || selected.kind == .stamp {
            VStack(alignment: .leading, spacing: 6) {
                Text("Text")
                    .inspectorLabel()
                TextField("Text", text: selectedBinding(\.text, fallback: ""))
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Font")
                    .inspectorLabel()
                Picker("", selection: selectedBinding(\.fontName, fallback: "Arial")) {
                    ForEach(model.availableFonts, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Font Size")
                    .inspectorLabel()
                HStack(spacing: 8) {
                    TextField(
                        "Size",
                        value: selectedBinding(\.fontSize, fallback: 18),
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 68)
                    Text("pt")
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.muted)
                    Spacer()
                    formatToggle("B", keyPath: \.isBold, fallback: false)
                    formatToggle("I", keyPath: \.isItalic, fallback: false)
                    formatToggle("U", keyPath: \.isUnderlined, fallback: false)
                }
                Slider(value: selectedBinding(\.fontSize, fallback: 18), in: 6...200, step: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Alignment")
                    .inspectorLabel()
                HStack(spacing: 7) {
                    alignmentButton(.left, icon: "text.alignleft")
                    alignmentButton(.center, icon: "text.aligncenter")
                    alignmentButton(.right, icon: "text.alignright")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Text Color")
                    .inspectorLabel()
                HStack(spacing: 8) {
                    colorPresetButton(.nearBlack)
                    colorPresetButton(.white)
                    colorPresetButton(.red)
                    colorPresetButton(.blue)
                    colorPresetButton(.green)
                    colorPresetButton(.orange)
                }
                ColorPicker("Custom color", selection: textColorBinding, supportsOpacity: false)
                    .font(.system(size: 10))
                    .help("Choose any text color")
            }
        }

        if selected.kind == .image {
            PrimaryButton(title: "Replace Image", systemImage: "photo.badge.arrow.down") {
                replaceImage()
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Opacity")
                    .inspectorLabel()
                Spacer()
                Text("\(Int((model.selectedElement?.opacity ?? 1) * 100))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppTheme.muted)
            }
            Slider(value: selectedBinding(\.opacity, fallback: 1), in: 0.08...1, step: 0.01)
        }

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Rotation")
                    .inspectorLabel()
                Spacer()
                TextField(
                    "Degrees",
                    value: selectedBinding(\.rotation, fallback: 0),
                    format: .number.precision(.fractionLength(0...1))
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 62)
                Text("°")
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.muted)
            }
            Slider(value: selectedBinding(\.rotation, fallback: 0), in: -180...180, step: 1)
        }

        Toggle("Shadow", isOn: selectedBinding(\.shadowEnabled, fallback: false))
            .font(.system(size: 10))

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Border")
                    .inspectorLabel()
                Spacer()
                Text(String(format: "%.1f pt", model.selectedElement?.borderWidth ?? 0))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppTheme.muted)
            }
            Slider(value: selectedBinding(\.borderWidth, fallback: 0), in: 0...8, step: 0.5)
            ColorPicker("Border Color", selection: borderColorBinding, supportsOpacity: false)
                .font(.system(size: 10))
        }

        geometryInspector

        HStack(spacing: 8) {
            Button("Send Back") { model.sendSelectedBackward() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Bring Front") { model.bringSelectedForward() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }

        HStack(spacing: 8) {
            Button("Duplicate") { model.duplicateSelectedElement() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Delete", role: .destructive) { model.removeSelectedElement() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }

        if selected.kind == .stamp {
            Divider()
            Text("Stamp presets")
                .inspectorLabel()
            stampLibrary
        }
    }

    private var geometryInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Position & Size")
                .inspectorLabel()
            Text("Drag the object directly on the page, use the eight handles to resize it, or enter exact values here.")
                .inspectorHelp()

            HStack(spacing: 8) {
                geometryField("X", component: .x)
                geometryField("Y", component: .y)
            }
            HStack(spacing: 8) {
                geometryField("W", component: .width)
                geometryField("H", component: .height)
            }

            if model.selectedElement != nil {
                Slider(value: frameBinding(.x), in: 0...1, step: 0.002)
                Slider(value: frameBinding(.y), in: 0...1, step: 0.002)
            }
        }
    }

    private func geometryField(_ label: String, component: CanvasFrameComponent) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppTheme.muted)
                .frame(width: 13)
            TextField(
                label,
                value: percentageFrameBinding(component),
                format: .number.precision(.fractionLength(0...1))
            )
            .textFieldStyle(.roundedBorder)
            Text("%")
                .font(.system(size: 8))
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var stampLibrary: some View {
        VStack(spacing: 8) {
            ForEach(["Approved", "Final", "NotForPublicRelease", "Draft", "Experimental", "NotApproved", "Confidential", "TopSecret"], id: \.self) { label in
                Button {
                    model.addStamp(label)
                } label: {
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(stampTint(label), lineWidth: 1.3)
                        }
                        .foregroundStyle(stampTint(label))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func formatToggle(_ title: String, keyPath: WritableKeyPath<CanvasElement, Bool>, fallback: Bool) -> some View {
        let binding = selectedBinding(keyPath, fallback: fallback)
        Button {
            binding.wrappedValue.toggle()
        } label: {
            Group {
                if title == "B" {
                    Text(title).bold()
                } else if title == "I" {
                    Text(title).italic()
                } else {
                    Text(title).underline()
                }
            }
            .font(.system(size: 13))
            .frame(width: 34, height: 28)
            .background(binding.wrappedValue ? AppTheme.blue : AppTheme.elevatedSurface)
            .foregroundStyle(binding.wrappedValue ? Color.white : AppTheme.text)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func alignmentButton(_ alignment: CanvasTextAlignment, icon: String) -> some View {
        let binding = selectedBinding(\.alignment, fallback: CanvasTextAlignment.center)
        return Button {
            binding.wrappedValue = alignment
        } label: {
            Image(systemName: icon)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(binding.wrappedValue == alignment ? AppTheme.blue : AppTheme.elevatedSurface)
                .foregroundStyle(binding.wrappedValue == alignment ? Color.white : AppTheme.text)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectedBinding<Value>(_ keyPath: WritableKeyPath<CanvasElement, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { model.selectedElement?[keyPath: keyPath] ?? fallback },
            set: { newValue in model.updateSelected { $0[keyPath: keyPath] = newValue } }
        )
    }

    private var textColorBinding: Binding<Color> {
        Binding(
            get: { model.selectedElement?.textColor.color ?? Color.primary },
            set: { newColor in
                model.updateSelected { $0.textColor = CanvasRGBA(NSColor(newColor)) }
            }
        )
    }


    private func colorPresetButton(_ color: CanvasRGBA) -> some View {
        Button {
            model.updateSelected { $0.textColor = color }
        } label: {
            Circle()
                .fill(color.color)
                .frame(width: 20, height: 20)
                .overlay {
                    Circle().stroke(
                        model.selectedElement?.textColor == color ? AppTheme.blue : AppTheme.line,
                        lineWidth: model.selectedElement?.textColor == color ? 2.5 : 1
                    )
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Set text color")
    }

    private var borderColorBinding: Binding<Color> {
        Binding(
            get: { model.selectedElement?.borderColor.color ?? AppTheme.blue },
            set: { newColor in
                model.updateSelected { $0.borderColor = CanvasRGBA(NSColor(newColor)) }
            }
        )
    }

    private func percentageFrameBinding(_ component: CanvasFrameComponent) -> Binding<Double> {
        Binding(
            get: { frameBinding(component).wrappedValue * 100 },
            set: { frameBinding(component).wrappedValue = $0 / 100 }
        )
    }

    private func frameBinding(_ component: CanvasFrameComponent) -> Binding<Double> {
        Binding(
            get: {
                guard let frame = model.selectedElement?.frame else { return 0 }
                switch component {
                case .x: return Double(frame.minX)
                case .y: return Double(frame.minY)
                case .width: return Double(frame.width)
                case .height: return Double(frame.height)
                }
            },
            set: { newValue in
                model.updateSelected { element in
                    var frame = element.frame
                    let value = CGFloat(newValue)
                    switch component {
                    case .x: frame.origin.x = value
                    case .y: frame.origin.y = value
                    case .width: frame.size.width = value
                    case .height: frame.size.height = value
                    }
                    element.frame = frame
                }
            }
        )
    }

    private func stampTint(_ label: String) -> Color {
        switch label.lowercased() {
        case "approved", "final": return .green
        case "draft", "experimental": return AppTheme.blue
        case "notapproved", "notforpublicrelease": return .orange
        default: return .red
        }
    }

    private func addImage() {
        let chosen = PanelService.chooseImages(allowsMultiple: false)
        guard let imageURL = chosen.first, let image = NSImage(contentsOf: imageURL) else { return }
        model.addImage(image)
    }

    private func replaceImage() {
        let chosen = PanelService.chooseImages(allowsMultiple: false)
        guard let imageURL = chosen.first, let image = NSImage(contentsOf: imageURL) else { return }
        model.replaceSelectedImage(image)
    }

    private func exportEditedPDF() {
        guard let destination = PanelService.saveFile(suggestedName: "Edited-\(url.lastPathComponent)", allowedType: .pdf) else { return }
        do {
            try model.export(to: destination)
            let savedSize = Int64((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            history.addSavedFile(toolID: nil, url: destination, outputSize: savedSize)
            model.statusMessage = "Exported and validated \(destination.lastPathComponent)."
            NSWorkspace.shared.open(destination)
        } catch {
            exportError = error.localizedDescription
        }
    }


    private func printEditedPDF() {
        Task {
            do {
                let directory = try await TemporaryFileManager.shared.makeTemporaryDirectory(prefix: "print")
                let tempURL = directory.appendingPathComponent("Print-\(url.lastPathComponent)")
                try model.export(to: tempURL)
                PrintService.printPDF(at: tempURL)
                await TemporaryFileManager.shared.cleanup(directory)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func shareEditedPDF() {
        Task {
            do {
                let directory = try await TemporaryFileManager.shared.makeTemporaryDirectory(prefix: "share")
                let tempURL = directory.appendingPathComponent("Edited-\(url.lastPathComponent)")
                try model.export(to: tempURL)
                SharingService.share(items: [tempURL])
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}

private struct NativePDFCanvas: NSViewRepresentable {
    @ObservedObject var model: PDFEditorModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NativePDFCanvasHostView {
        let view = NativePDFCanvasHostView(document: model.document)
        context.coordinator.connect(view)
        return view
    }

    func updateNSView(_ nsView: NativePDFCanvasHostView, context: Context) {
        context.coordinator.model = model
        context.coordinator.connect(nsView)
        nsView.apply(
            elements: model.elements,
            selectedID: model.selectedElementID,
            interactionMode: model.interactionMode,
            requestedInlineEditID: model.requestedInlineEditID,
            requestedPage: model.requestedCanvasScrollPage,
            zoom: model.zoom
        )
    }

    @MainActor
    final class Coordinator {
        var model: PDFEditorModel

        init(model: PDFEditorModel) {
            self.model = model
        }

        func connect(_ view: NativePDFCanvasHostView) {
            view.onSelectElement = { [weak self] id, pageIndex in
                guard let self else { return }
                self.model.currentPageIndex = pageIndex
                self.model.select(id)
            }

            view.onInsertText = { [weak self] pageIndex, point in
                guard let self else { return }
                self.model.currentPageIndex = pageIndex
                self.model.addText(at: point)
            }

            view.onCommitElement = { [weak self] element in
                self?.model.replaceElement(element)
            }

            view.onBeginElementInteraction = { [weak self] in
                self?.model.beginInteractiveEdit()
            }

            view.onEndElementInteraction = { [weak self] in
                self?.model.endInteractiveEdit()
            }

            view.onPageFocused = { [weak self] pageIndex in
                guard let self else { return }
                if self.model.currentPageIndex != pageIndex {
                    self.model.currentPageIndex = pageIndex
                }
            }

            view.onZoomChanged = { [weak self] zoom in
                guard let self else { return }
                if abs(self.model.zoom - zoom) > 0.001 {
                    self.model.zoom = zoom
                }
            }

            view.onInlineEditRequestHandled = { [weak self] id in
                guard let self else { return }
                if self.model.requestedInlineEditID == id {
                    self.model.requestedInlineEditID = nil
                }
            }

            view.onCanvasToolConsumed = { [weak self] in
                self?.model.interactionMode = .select
            }
        }
    }
}

/// High-performance native canvas used inside the SwiftUI editor.
///
/// The previous SwiftUI implementation wrote to the full `@Published elements`
/// array on every mouse-move. That forced the entire multi-page canvas hierarchy
/// to be diffed and rebuilt for every drag frame. This host keeps the PDF pages
/// and editing objects as persistent AppKit views. Drag/resize/rotate is performed
/// locally at native event speed and the SwiftUI model is committed only when the
/// interaction ends.
private final class NativePDFCanvasHostView: NSView {
    let canvasScrollView = CanvasNativeScrollView()
    let documentView: NativePDFPagesDocumentView

    var onSelectElement: ((UUID?, Int) -> Void)?
    var onInsertText: ((Int, CGPoint) -> Void)?
    var onCommitElement: ((CanvasElement) -> Void)?
    var onBeginElementInteraction: (() -> Void)?
    var onEndElementInteraction: (() -> Void)?
    var onPageFocused: ((Int) -> Void)?
    var onZoomChanged: ((Double) -> Void)?
    var onInlineEditRequestHandled: ((UUID) -> Void)?
    var onCanvasToolConsumed: (() -> Void)?

    private var lastRequestedPage: Int?
    private var lastViewportSize: CGSize = .zero

    init(document: PDFDocument) {
        documentView = NativePDFPagesDocumentView(document: document)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        canvasScrollView.drawsBackground = true
        canvasScrollView.backgroundColor = NSColor.windowBackgroundColor
        canvasScrollView.hasVerticalScroller = true
        canvasScrollView.hasHorizontalScroller = true
        canvasScrollView.autohidesScrollers = true
        canvasScrollView.allowsMagnification = true
        canvasScrollView.minMagnification = 0.35
        canvasScrollView.maxMagnification = 5.0
        canvasScrollView.magnification = 1.0
        canvasScrollView.documentView = documentView
        canvasScrollView.contentView.postsBoundsChangedNotifications = true

        canvasScrollView.onControlZoom = { [weak self] zoom in
            self?.onZoomChanged?(Double(zoom))
        }
        canvasScrollView.onScrollFinished = { [weak self] in
            self?.updateCurrentPageFromViewport()
        }

        documentView.onSelectElement = { [weak self] id, page in
            self?.onSelectElement?(id, page)
        }
        documentView.onInsertText = { [weak self] page, point in
            self?.onInsertText?(page, point)
            self?.onCanvasToolConsumed?()
        }
        documentView.onCommitElement = { [weak self] element in
            self?.onCommitElement?(element)
        }
        documentView.onBeginElementInteraction = { [weak self] in
            self?.onBeginElementInteraction?()
        }
        documentView.onEndElementInteraction = { [weak self] in
            self?.onEndElementInteraction?()
        }
        documentView.onPageFocused = { [weak self] page in
            self?.onPageFocused?(page)
        }
        documentView.onInlineEditRequestHandled = { [weak self] id in
            self?.onInlineEditRequestHandled?(id)
        }

        addSubview(canvasScrollView)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        canvasScrollView.frame = bounds

        let viewport = canvasScrollView.contentView.bounds.size
        if abs(viewport.width - lastViewportSize.width) > 1 || abs(viewport.height - lastViewportSize.height) > 1 {
            lastViewportSize = viewport
            documentView.layoutPages(forViewportWidth: max(1, viewport.width))
        }
    }

    func apply(
        elements: [CanvasElement],
        selectedID: UUID?,
        interactionMode: CanvasInteractionMode,
        requestedInlineEditID: UUID?,
        requestedPage: Int?,
        zoom: Double
    ) {
        documentView.interactionMode = interactionMode
        documentView.sync(
            elements: elements,
            selectedID: selectedID,
            requestedInlineEditID: requestedInlineEditID
        )

        let safeZoom = CGFloat(min(5.0, max(0.35, zoom)))
        if abs(canvasScrollView.magnification - safeZoom) > 0.001,
           !canvasScrollView.isHandlingControlZoom {
            canvasScrollView.magnification = safeZoom
        }

        if let requestedPage {
            if lastRequestedPage != requestedPage || !documentView.isPageMostlyVisible(requestedPage, in: canvasScrollView) {
                lastRequestedPage = requestedPage
                scrollToPage(requestedPage)
            }
        } else {
            lastRequestedPage = nil
        }
    }

    private func scrollToPage(_ index: Int) {
        guard let pageView = documentView.pageView(at: index) else { return }
        let destination = CGPoint(
            x: max(0, pageView.frame.midX - canvasScrollView.contentView.bounds.width / (2 * max(0.01, canvasScrollView.magnification))),
            y: max(0, pageView.frame.minY - 24)
        )
        canvasScrollView.contentView.scroll(to: destination)
        canvasScrollView.reflectScrolledClipView(canvasScrollView.contentView)
        onPageFocused?(index)
    }

    private func updateCurrentPageFromViewport() {
        let visible = canvasScrollView.documentVisibleRect
        let centerY = visible.midY
        guard let nearest = documentView.pageViews.min(by: {
            abs($0.frame.midY - centerY) < abs($1.frame.midY - centerY)
        }) else { return }
        onPageFocused?(nearest.pageIndex)
    }
}

private final class CanvasNativeScrollView: NSScrollView {
    var onControlZoom: ((CGFloat) -> Void)?
    var onScrollFinished: (() -> Void)?
    fileprivate(set) var isHandlingControlZoom = false

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            guard let documentView else { return }
            isHandlingControlZoom = true
            defer { isHandlingControlZoom = false }

            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
            let factor = CGFloat(exp(Double(delta) * 0.018))
            let target = min(maxMagnification, max(minMagnification, magnification * factor))
            let center = documentView.convert(event.locationInWindow, from: nil)
            setMagnification(target, centeredAt: center)
            onControlZoom?(target)
            return
        }

        super.scrollWheel(with: event)
        onScrollFinished?()
    }
}

private final class NativePDFPagesDocumentView: NSView {
    let document: PDFDocument
    fileprivate var pageViews: [NativePDFPageView] = []
    var interactionMode: CanvasInteractionMode = .select {
        didSet { pageViews.forEach { $0.interactionMode = interactionMode } }
    }

    var onSelectElement: ((UUID?, Int) -> Void)?
    var onInsertText: ((Int, CGPoint) -> Void)?
    var onCommitElement: ((CanvasElement) -> Void)?
    var onBeginElementInteraction: (() -> Void)?
    var onEndElementInteraction: (() -> Void)?
    var onPageFocused: ((Int) -> Void)?
    var onInlineEditRequestHandled: ((UUID) -> Void)?

    init(document: PDFDocument) {
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        buildPages()
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    private func buildPages() {
        pageViews.forEach { $0.removeFromSuperview() }
        pageViews.removeAll()

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let pageView = NativePDFPageView(page: page, pageIndex: index)
            pageView.interactionMode = interactionMode
            wire(pageView)
            pageViews.append(pageView)
            addSubview(pageView)
        }
    }

    private func wire(_ pageView: NativePDFPageView) {
        pageView.onSelectElement = { [weak self] id, page in self?.onSelectElement?(id, page) }
        pageView.onInsertText = { [weak self] page, point in self?.onInsertText?(page, point) }
        pageView.onCommitElement = { [weak self] element in self?.onCommitElement?(element) }
        pageView.onBeginElementInteraction = { [weak self] in self?.onBeginElementInteraction?() }
        pageView.onEndElementInteraction = { [weak self] in self?.onEndElementInteraction?() }
        pageView.onPageFocused = { [weak self] page in self?.onPageFocused?(page) }
        pageView.onInlineEditRequestHandled = { [weak self] id in self?.onInlineEditRequestHandled?(id) }
    }

    func layoutPages(forViewportWidth viewportWidth: CGFloat) {
        guard !pageViews.isEmpty else {
            frame.size = CGSize(width: viewportWidth, height: 1)
            return
        }

        let largestPDFWidth = pageViews.map { $0.pdfPageSize.width }.max() ?? 595
        let desiredPageWidth = min(920, max(440, viewportWidth - 112))
        let fitScale = desiredPageWidth / max(1, largestPDFWidth)
        let documentWidth = max(viewportWidth, largestPDFWidth * fitScale + 112)

        var y: CGFloat = 56
        for pageView in pageViews {
            let size = CGSize(
                width: pageView.pdfPageSize.width * fitScale,
                height: pageView.pdfPageSize.height * fitScale
            )
            let x = (documentWidth - size.width) / 2
            pageView.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            pageView.displayScale = fitScale
            pageView.layoutElementViewsFromModel()
            y += size.height + 38
        }

        frame = CGRect(x: 0, y: 0, width: documentWidth, height: y + 56)
    }

    func sync(elements: [CanvasElement], selectedID: UUID?, requestedInlineEditID: UUID?) {
        let grouped = Dictionary(grouping: elements, by: \.pageIndex)
        for pageView in pageViews {
            pageView.sync(
                elements: grouped[pageView.pageIndex] ?? [],
                selectedID: selectedID,
                requestedInlineEditID: requestedInlineEditID
            )
        }
    }

    func pageView(at index: Int) -> NativePDFPageView? {
        pageViews.first(where: { $0.pageIndex == index })
    }

    func isPageMostlyVisible(_ index: Int, in scrollView: NSScrollView) -> Bool {
        guard let pageView = pageView(at: index) else { return false }
        return scrollView.documentVisibleRect.intersects(pageView.frame.insetBy(dx: 0, dy: pageView.frame.height * 0.25))
    }
}

private final class NativePDFPageView: NSView {
    let page: PDFPage
    let pageIndex: Int
    let pdfPageSize: CGSize
    var displayScale: CGFloat = 1
    var interactionMode: CanvasInteractionMode = .select

    var onSelectElement: ((UUID?, Int) -> Void)?
    var onInsertText: ((Int, CGPoint) -> Void)?
    var onCommitElement: ((CanvasElement) -> Void)?
    var onBeginElementInteraction: (() -> Void)?
    var onEndElementInteraction: (() -> Void)?
    var onPageFocused: ((Int) -> Void)?
    var onInlineEditRequestHandled: ((UUID) -> Void)?

    private var elementViews: [UUID: NativeCanvasElementView] = [:]

    init(page: PDFPage, pageIndex: Int) {
        self.page = page
        self.pageIndex = pageIndex
        let pageBounds = page.bounds(for: .mediaBox)
        self.pdfPageSize = CGSize(width: max(1, pageBounds.width), height: max(1, pageBounds.height))
        super.init(frame: CGRect(origin: .zero, size: self.pdfPageSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -3)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        NSColor.white.setFill()
        context.fill(bounds)

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

    override func mouseDown(with event: NSEvent) {
        endInlineEditing(except: nil)
        window?.makeFirstResponder(self)
        onPageFocused?(pageIndex)

        let point = convert(event.locationInWindow, from: nil)
        let normalized = CGPoint(
            x: min(1, max(0, point.x / max(1, bounds.width))),
            y: min(1, max(0, point.y / max(1, bounds.height)))
        )

        if interactionMode == .insertText {
            onInsertText?(pageIndex, normalized)
        } else {
            onSelectElement?(nil, pageIndex)
        }
    }

    func sync(elements: [CanvasElement], selectedID: UUID?, requestedInlineEditID: UUID?) {
        let incomingIDs = Set(elements.map(\.id))
        let removedIDs = elementViews.keys.filter { !incomingIDs.contains($0) }
        for id in removedIDs {
            elementViews[id]?.removeFromSuperview()
            elementViews[id] = nil
        }

        for element in elements.sorted(by: { $0.zIndex < $1.zIndex }) {
            let view: NativeCanvasElementView
            if let existing = elementViews[element.id] {
                view = existing
            } else {
                view = NativeCanvasElementView(element: element)
                elementViews[element.id] = view
                wire(view)
                addSubview(view)
            }

            view.pageDisplaySize = bounds.size
            view.pdfDisplayScale = displayScale
            view.isSelected = selectedID == element.id
            view.applyModelElement(element)
            view.layer?.zPosition = CGFloat(element.zIndex + 10)

            if requestedInlineEditID == element.id && !view.isInlineEditing {
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    view.beginInlineEditing(selectAll: true)
                    self.onInlineEditRequestHandled?(element.id)
                }
            }
        }
    }

    func layoutElementViewsFromModel() {
        for view in elementViews.values {
            view.pageDisplaySize = bounds.size
            view.pdfDisplayScale = displayScale
            view.applyNormalizedFrameIfIdle()
        }
    }

    private func wire(_ view: NativeCanvasElementView) {
        view.onSelect = { [weak self] id in
            guard let self else { return }
            self.endInlineEditing(except: id)
            self.onSelectElement?(id, self.pageIndex)
            self.onPageFocused?(self.pageIndex)
        }
        view.onCommit = { [weak self] element in self?.onCommitElement?(element) }
        view.onBeginInteraction = { [weak self] in self?.onBeginElementInteraction?() }
        view.onEndInteraction = { [weak self] in self?.onEndElementInteraction?() }
    }

    private func endInlineEditing(except id: UUID?) {
        for (elementID, view) in elementViews where elementID != id {
            view.finishInlineEditing(commit: true)
        }
    }
}

private final class NativeCanvasElementView: NSView, NSTextViewDelegate {
    enum Interaction {
        case none
        case move
        case resize(ResizeHandlePosition)
        case rotate
    }

    var element: CanvasElement
    var pageDisplaySize: CGSize = .zero
    var pdfDisplayScale: CGFloat = 1
    var isSelected = false {
        didSet { if oldValue != isSelected { needsDisplay = true } }
    }

    var onSelect: ((UUID) -> Void)?
    var onCommit: ((CanvasElement) -> Void)?
    var onBeginInteraction: (() -> Void)?
    var onEndInteraction: (() -> Void)?

    private(set) var isInlineEditing = false
    private var textEditor: NSTextView?
    private var interaction: Interaction = .none
    private var interactionStartElement: CanvasElement?
    private var interactionStartRect: CGRect = .zero
    private var interactionStartPointer: CGPoint = .zero
    private var interactionStartAngle: Double = 0
    private var isFinishingInlineEdit = false

    init(element: CanvasElement) {
        self.element = element
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        applyNormalizedFrameIfIdle()
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func applyModelElement(_ updated: CanvasElement) {
        guard !isPerformingPointerInteraction else {
            isSelected = true
            return
        }

        let preserveEditorText = isInlineEditing
        let currentEditorText = textEditor?.string
        element = updated
        applyNormalizedFrameIfIdle()
        applyRotation()
        needsDisplay = true

        if isInlineEditing {
            applyEditorStyle()
            if !preserveEditorText || currentEditorText == nil {
                textEditor?.string = element.text
            }
        }
    }

    func applyNormalizedFrameIfIdle() {
        guard !isPerformingPointerInteraction,
              pageDisplaySize.width > 0,
              pageDisplaySize.height > 0 else { return }

        let rect = CGRect(
            x: element.frame.minX * pageDisplaySize.width,
            y: element.frame.minY * pageDisplaySize.height,
            width: max(18, element.frame.width * pageDisplaySize.width),
            height: max(18, element.frame.height * pageDisplaySize.height)
        )
        frame = rect
        applyRotation()
    }

    private func applyRotation() {
        frameCenterRotation = CGFloat(element.rotation)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !isInlineEditing else {
            drawSelectionIfNeeded()
            return
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        if element.shadowEnabled {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = 4
            shadow.shadowOffset = CGSize(width: 2, height: -2)
            shadow.set()
        }

        switch element.kind {
        case .image:
            drawImageElement()
        case .text, .stamp:
            drawTextElement()
        }

        if element.borderWidth > 0 {
            let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            path.lineWidth = CGFloat(max(0.5, element.borderWidth))
            element.borderColor.nsColor.withAlphaComponent(CGFloat(element.opacity)).setStroke()
            path.stroke()
        }

        drawSelectionIfNeeded()
    }

    private func drawTextElement() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = element.alignment.nsAlignment
        paragraph.lineBreakMode = .byWordWrapping

        let font = resolvedFont()
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: element.textColor.nsColor.withAlphaComponent(CGFloat(element.opacity)),
            .paragraphStyle: paragraph
        ]
        if element.isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        let textRect = bounds.insetBy(dx: 5, dy: 4)
        let text = element.text.isEmpty ? " " : element.text
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func drawImageElement() {
        guard let data = element.imageData, let image = NSImage(data: data) else {
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(rect: bounds).fill()
            return
        }

        let destination = aspectFitRect(imageSize: image.size, inside: bounds.insetBy(dx: 2, dy: 2))
        image.draw(
            in: destination,
            from: .zero,
            operation: .sourceOver,
            fraction: CGFloat(element.opacity),
            respectFlipped: true,
            hints: nil
        )
    }

    private func resolvedFont() -> NSFont {
        let fontManager = NSFontManager.shared
        let displaySize = max(7, CGFloat(element.fontSize) * max(0.01, pdfDisplayScale))
        var font = fontManager.font(
            withFamily: element.fontName,
            traits: [],
            weight: 5,
            size: displaySize
        ) ?? NSFont(name: element.fontName, size: displaySize)
            ?? NSFont.systemFont(ofSize: displaySize)

        if element.isBold {
            font = fontManager.convert(font, toHaveTrait: .boldFontMask)
        }
        if element.isItalic {
            font = fontManager.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    private func drawSelectionIfNeeded() {
        guard isSelected else { return }

        let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        border.lineWidth = 1.5
        AppTheme.nsBlue.setStroke()
        border.stroke()

        for position in ResizeHandlePosition.allCases {
            let center = handleCenter(position)
            let rect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            AppTheme.nsBlue.setStroke()
            let outline = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            outline.lineWidth = 1.5
            outline.stroke()
        }

        let rotateRect = rotationHandleRect
        AppTheme.nsBlue.setFill()
        NSBezierPath(ovalIn: rotateRect).fill()
        NSColor.white.setStroke()
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: CGPoint(x: rotateRect.midX, y: rotateRect.midY),
            radius: 4.3,
            startAngle: 35,
            endAngle: 315,
            clockwise: false
        )
        arc.lineWidth = 1.4
        arc.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Keep selection controls interactive even while an NSTextView is active inside
        // the element. Without this, the inline editor can swallow clicks that are
        // visually on the resize/rotation handles.
        if isSelected, let superview {
            let local = convert(point, from: superview)
            if rotationHandleRect.insetBy(dx: -8, dy: -8).contains(local) || resizeHandle(at: local) != nil {
                return self
            }
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)

        if event.clickCount >= 2, element.kind == .text {
            onSelect?(element.id)
            beginInlineEditing(selectAll: false)
            return
        }

        isSelected = true
        interactionStartElement = element
        interactionStartRect = unrotatedDisplayRectFromElement()
        interactionStartPointer = superview?.convert(event.locationInWindow, from: nil) ?? .zero

        if rotationHandleRect.insetBy(dx: -5, dy: -5).contains(local) {
            interaction = .rotate
            interactionStartAngle = pointerAngle(inSuperviewAt: interactionStartPointer)
        } else if let handle = resizeHandle(at: local) {
            interaction = .resize(handle)
        } else {
            interaction = .move
        }

        onSelect?(element.id)
        onBeginInteraction?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard interactionStartElement != nil,
              let superview else { return }

        let pointer = superview.convert(event.locationInWindow, from: nil)
        let dx = pointer.x - interactionStartPointer.x
        let dy = pointer.y - interactionStartPointer.y

        switch interaction {
        case .none:
            break
        case .move:
            var rect = interactionStartRect.offsetBy(dx: dx, dy: dy)
            rect = clampedDisplayRect(rect, minimumSize: CGSize(width: 26, height: 20))
            setLocalDisplayRect(rect)

        case .resize(let handle):
            var rect = resizedDisplayRect(
                start: interactionStartRect,
                dx: dx,
                dy: dy,
                handle: handle
            )
            rect = clampedDisplayRect(rect, minimumSize: CGSize(width: 26, height: 20))
            setLocalDisplayRect(rect)

        case .rotate:
            let angle = pointerAngle(inSuperviewAt: pointer)
            let delta = shortestAngleDifference(from: interactionStartAngle, to: angle)
            let startRotation = interactionStartElement?.rotation ?? element.rotation
            element.rotation = normalizedDegrees(startRotation + delta)
            applyRotation()
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard interactionStartElement != nil else { return }
        interaction = .none
        interactionStartElement = nil
        onCommit?(element)
        onEndInteraction?()
    }

    func beginInlineEditing(selectAll: Bool) {
        guard element.kind == .text, !isInlineEditing else { return }
        isInlineEditing = true
        interaction = .none
        interactionStartElement = nil

        let editor = NSTextView(frame: bounds.insetBy(dx: 3, dy: 2))
        editor.delegate = self
        editor.string = element.text
        editor.drawsBackground = false
        editor.isRichText = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.textContainerInset = CGSize(width: 2, height: 1)
        editor.textContainer?.widthTracksTextView = true
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = false
        editor.autoresizingMask = [.width, .height]
        textEditor = editor
        addSubview(editor)
        applyEditorStyle()
        needsDisplay = true

        DispatchQueue.main.async { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.window?.makeFirstResponder(editor)
            if selectAll {
                editor.selectAll(nil)
            }
        }
    }

    func finishInlineEditing(commit: Bool) {
        guard isInlineEditing, !isFinishingInlineEdit else { return }
        isFinishingInlineEdit = true
        defer { isFinishingInlineEdit = false }

        if let textEditor {
            element.text = textEditor.string
            textEditor.delegate = nil
            textEditor.removeFromSuperview()
        }
        self.textEditor = nil
        isInlineEditing = false
        needsDisplay = true

        if commit {
            onCommit?(element)
        }
    }

    func textDidChange(_ notification: Notification) {
        guard let textEditor else { return }
        element.text = textEditor.string
    }

    func textDidEndEditing(_ notification: Notification) {
        finishInlineEditing(commit: true)
    }

    private func applyEditorStyle() {
        guard let editor = textEditor else { return }
        editor.font = resolvedFont()
        editor.textColor = element.textColor.nsColor.withAlphaComponent(CGFloat(element.opacity))
        editor.alignment = element.alignment.nsAlignment
        editor.typingAttributes = [
            .font: resolvedFont(),
            .foregroundColor: element.textColor.nsColor.withAlphaComponent(CGFloat(element.opacity))
        ]
    }

    private var isPerformingPointerInteraction: Bool {
        switch interaction {
        case .none: return interactionStartElement != nil
        default: return true
        }
    }

    private func unrotatedDisplayRectFromElement() -> CGRect {
        CGRect(
            x: element.frame.minX * pageDisplaySize.width,
            y: element.frame.minY * pageDisplaySize.height,
            width: element.frame.width * pageDisplaySize.width,
            height: element.frame.height * pageDisplaySize.height
        )
    }

    private func setLocalDisplayRect(_ rect: CGRect) {
        guard pageDisplaySize.width > 0, pageDisplaySize.height > 0 else { return }
        element.frame = CGRect(
            x: rect.minX / pageDisplaySize.width,
            y: rect.minY / pageDisplaySize.height,
            width: rect.width / pageDisplaySize.width,
            height: rect.height / pageDisplaySize.height
        )
        frameCenterRotation = 0
        frame = rect
        applyRotation()
        needsDisplay = true
    }

    private func clampedDisplayRect(_ input: CGRect, minimumSize: CGSize) -> CGRect {
        var rect = input.standardized
        rect.size.width = min(max(minimumSize.width, rect.width), max(minimumSize.width, pageDisplaySize.width))
        rect.size.height = min(max(minimumSize.height, rect.height), max(minimumSize.height, pageDisplaySize.height))
        rect.origin.x = min(max(0, rect.minX), max(0, pageDisplaySize.width - rect.width))
        rect.origin.y = min(max(0, rect.minY), max(0, pageDisplaySize.height - rect.height))
        return rect
    }

    private func resizeHandle(at point: CGPoint) -> ResizeHandlePosition? {
        let threshold: CGFloat = 13
        for handle in ResizeHandlePosition.allCases {
            let center = handleCenter(handle)
            let hit = CGRect(x: center.x - threshold, y: center.y - threshold, width: threshold * 2, height: threshold * 2)
            if hit.contains(point) { return handle }
        }
        return nil
    }

    private func handleCenter(_ handle: ResizeHandlePosition) -> CGPoint {
        // Keep handles fully inside the element bounds. Handles centered exactly on
        // the edge are partly clipped by AppKit and are unnecessarily hard to hit.
        let inset: CGFloat = 6
        switch handle {
        case .topLeft: return CGPoint(x: inset, y: inset)
        case .top: return CGPoint(x: bounds.midX, y: inset)
        case .topRight: return CGPoint(x: max(inset, bounds.maxX - inset), y: inset)
        case .left: return CGPoint(x: inset, y: bounds.midY)
        case .right: return CGPoint(x: max(inset, bounds.maxX - inset), y: bounds.midY)
        case .bottomLeft: return CGPoint(x: inset, y: max(inset, bounds.maxY - inset))
        case .bottom: return CGPoint(x: bounds.midX, y: max(inset, bounds.maxY - inset))
        case .bottomRight: return CGPoint(x: max(inset, bounds.maxX - inset), y: max(inset, bounds.maxY - inset))
        }
    }

    private var rotationHandleRect: CGRect {
        let y = min(max(2, bounds.height - 22), 18)
        return CGRect(x: bounds.midX - 9, y: y, width: 18, height: 18)
    }

    private func pointerAngle(inSuperviewAt point: CGPoint) -> Double {
        let rect = unrotatedDisplayRectFromElement()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return atan2(Double(point.y - center.y), Double(point.x - center.x)) * 180 / .pi
    }

    private func shortestAngleDifference(from start: Double, to end: Double) -> Double {
        var difference = end - start
        while difference > 180 { difference -= 360 }
        while difference < -180 { difference += 360 }
        return difference
    }

    private func normalizedDegrees(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }

    private func resizedDisplayRect(
        start: CGRect,
        dx: CGFloat,
        dy: CGFloat,
        handle: ResizeHandlePosition
    ) -> CGRect {
        var x = start.minX
        var y = start.minY
        var width = start.width
        var height = start.height

        switch handle {
        case .topLeft:
            x += dx; y += dy; width -= dx; height -= dy
        case .top:
            y += dy; height -= dy
        case .topRight:
            y += dy; width += dx; height -= dy
        case .left:
            x += dx; width -= dx
        case .right:
            width += dx
        case .bottomLeft:
            x += dx; width -= dx; height += dy
        case .bottom:
            height += dy
        case .bottomRight:
            width += dx; height += dy
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func aspectFitRect(imageSize: CGSize, inside rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}


private extension View {
    func inspectorLabel() -> some View {
        self
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppTheme.text)
    }

    func inspectorHelp() -> some View {
        self
            .font(.system(size: 9))
            .foregroundStyle(AppTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension PDFEditorModel {
    static func placeholder(url: URL) -> PDFEditorModel {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("PDFToolkit-empty.pdf")
        if !FileManager.default.fileExists(atPath: temp.path) {
            let image = NSImage(size: NSSize(width: 595, height: 842))
            image.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: image.size)).fill()
            image.unlockFocus()
            let doc = PDFDocument()
            if let page = PDFPage(image: image) { doc.insert(page, at: 0) }
            _ = doc.write(to: temp)
        }
        return PDFEditorModel(url: temp)!
    }
}
