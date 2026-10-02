import AppKit
import PDFKit
import SwiftUI

struct CanvasRGBA: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    static let nearBlack = CanvasRGBA(red: 0.12, green: 0.12, blue: 0.14)
    static let white = CanvasRGBA(red: 1, green: 1, blue: 1)
    static let blue = CanvasRGBA(red: 0.19, green: 0.37, blue: 0.93)
    static let green = CanvasRGBA(red: 0.10, green: 0.58, blue: 0.30)
    static let orange = CanvasRGBA(red: 0.92, green: 0.42, blue: 0.12)
    static let red = CanvasRGBA(red: 0.82, green: 0.15, blue: 0.17)
    static let clear = CanvasRGBA(red: 0, green: 0, blue: 0, alpha: 0)

    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    var color: Color { Color(nsColor: nsColor) }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        red = Double(converted.redComponent)
        green = Double(converted.greenComponent)
        blue = Double(converted.blueComponent)
        alpha = Double(converted.alphaComponent)
    }
}

enum CanvasElementKind: String, Equatable {
    case text
    case stamp
    case image
}

enum CanvasInteractionMode: Equatable {
    case select
    case insertText
}

enum CanvasTextAlignment: String, CaseIterable, Identifiable {
    case left = "Left"
    case center = "Center"
    case right = "Right"
    var id: String { rawValue }

    var nsAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

struct CanvasElement: Identifiable, Equatable {
    let id: UUID
    var pageIndex: Int
    var kind: CanvasElementKind

    /// Normalized frame in page display coordinates (origin at top-left, 0...1).
    var frame: CGRect

    var text: String
    var fontName: String
    var fontSize: Double
    var textColor: CanvasRGBA
    var opacity: Double
    var rotation: Double
    var alignment: CanvasTextAlignment
    var isBold: Bool
    var isItalic: Bool
    var isUnderlined: Bool
    var shadowEnabled: Bool
    var borderWidth: Double
    var borderColor: CanvasRGBA
    var imageData: Data?
    var zIndex: Int

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        kind: CanvasElementKind,
        frame: CGRect,
        text: String = "",
        fontName: String = "Arial",
        fontSize: Double = 18,
        textColor: CanvasRGBA = .nearBlack,
        opacity: Double = 1,
        rotation: Double = 0,
        alignment: CanvasTextAlignment = .center,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        shadowEnabled: Bool = false,
        borderWidth: Double = 0,
        borderColor: CanvasRGBA = .blue,
        imageData: Data? = nil,
        zIndex: Int = 0
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.kind = kind
        self.frame = frame
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.opacity = opacity
        self.rotation = rotation
        self.alignment = alignment
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.shadowEnabled = shadowEnabled
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.imageData = imageData
        self.zIndex = zIndex
    }
}

@MainActor
final class PDFEditorModel: ObservableObject {
    enum InspectorMode: String {
        case text = "Text"
        case stamp = "Stamp"
        case image = "Image"
    }

    let sourceURL: URL
    let document: PDFDocument

    @Published var currentPageIndex = 0
    @Published var inspectorMode: InspectorMode = .text
    @Published var elements: [CanvasElement] = []
    @Published var selectedElementID: UUID?
    @Published var requestedInlineEditID: UUID?
    @Published var statusMessage: String?
    @Published var zoom: Double = 1.0
    @Published var interactionMode: CanvasInteractionMode = .select
    @Published var requestedCanvasScrollPage: Int?

    private var undoStack: [[CanvasElement]] = []
    private var redoStack: [[CanvasElement]] = []
    private var interactionSnapshot: [CanvasElement]?
    private var thumbnailCache: [Int: NSImage] = [:]
    private var pageImageCache: [Int: NSImage] = [:]

    /// Read the system font list once. Re-querying NSFontManager from the inspector on
    /// every slider/colour change was one of the biggest sources of editor stutter.
    let availableFonts: [String]

    init?(url: URL) {
        guard let doc = PDFDocument(url: url), !doc.isLocked else { return nil }
        sourceURL = url
        document = doc
        let families = NSFontManager.shared.availableFontFamilies.sorted()
        availableFonts = families.isEmpty ? ["Helvetica", "Arial", "Times New Roman", "Courier New"] : families
    }

    var pageCount: Int { document.pageCount }

    var selectedElement: CanvasElement? {
        guard let selectedElementID else { return nil }
        return elements.first(where: { $0.id == selectedElementID })
    }

    var currentPageElements: [CanvasElement] {
        elements(on: currentPageIndex)
    }

    func elements(on pageIndex: Int) -> [CanvasElement] {
        elements
            .filter { $0.pageIndex == pageIndex }
            .sorted { $0.zIndex < $1.zIndex }
    }

    func navigateToPage(_ index: Int) {
        guard pageCount > 0 else { return }
        let safeIndex = min(max(0, index), pageCount - 1)
        currentPageIndex = safeIndex
        selectedElementID = nil
        requestedInlineEditID = nil
        requestedCanvasScrollPage = safeIndex
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func thumbnail(for index: Int) -> NSImage? {
        if let cached = thumbnailCache[index] { return cached }
        guard let page = document.page(at: index) else { return nil }
        let image = page.thumbnail(of: NSSize(width: 118, height: 158), for: .mediaBox)
        thumbnailCache[index] = image
        return image
    }

    func pageSize(for index: Int? = nil) -> CGSize {
        let index = index ?? currentPageIndex
        guard let page = document.page(at: index) else { return CGSize(width: 595, height: 842) }
        let bounds = page.bounds(for: .mediaBox)
        return CGSize(width: max(1, bounds.width), height: max(1, bounds.height))
    }

    func pageImage(for index: Int? = nil, maxDimension: CGFloat = 1800) -> NSImage? {
        let index = index ?? currentPageIndex
        if let cached = pageImageCache[index] { return cached }
        guard let page = document.page(at: index) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let longest = max(bounds.width, bounds.height)
        let scale = longest > 0 ? min(3.0, maxDimension / longest) : 1
        let target = NSSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        let image = page.thumbnail(of: target, for: .mediaBox)
        pageImageCache[index] = image
        return image
    }

    func element(withID id: UUID) -> CanvasElement? {
        elements.first(where: { $0.id == id })
    }

    func replaceElement(_ element: CanvasElement) {
        guard let index = elements.firstIndex(where: { $0.id == element.id }) else { return }
        var copy = element
        copy.frame = clamp(copy.frame)
        elements[index] = copy
    }

    func select(_ id: UUID?) {
        selectedElementID = id
        guard let id, let element = elements.first(where: { $0.id == id }) else { return }
        interactionMode = .select
        switch element.kind {
        case .text: inspectorMode = .text
        case .stamp: inspectorMode = .stamp
        case .image: inspectorMode = .image
        }
    }

    func beginTextInsertion() {
        selectedElementID = nil
        requestedInlineEditID = nil
        inspectorMode = .text
        interactionMode = .insertText
        statusMessage = "Text tool active — click anywhere on the PDF to place a text box."
    }

    func cancelCanvasTool() {
        interactionMode = .select
        statusMessage = nil
    }

    func addText(_ text: String = "") {
        addText(at: CGPoint(x: 0.50, y: 0.47), text: text)
    }

    func addText(at normalizedPoint: CGPoint, text: String = "") {
        checkpoint()
        let initialText = text.isEmpty ? "Add Text" : text
        let width: CGFloat = 0.30
        let height: CGFloat = 0.065
        let x = min(1 - width, max(0, normalizedPoint.x - width / 2))
        let y = min(1 - height, max(0, normalizedPoint.y - height / 2))
        let element = CanvasElement(
            pageIndex: currentPageIndex,
            kind: .text,
            frame: CGRect(x: x, y: y, width: width, height: height),
            text: initialText,
            fontName: "Arial",
            fontSize: 18,
            textColor: .nearBlack,
            alignment: .left,
            zIndex: nextZIndex
        )
        elements.append(element)
        selectedElementID = element.id
        requestedInlineEditID = element.id
        inspectorMode = .text
        interactionMode = .select
        statusMessage = "Text added. Double-click to edit; drag to move; use the blue handles to resize and the rotate control to rotate."
    }

    func addStamp(_ label: String) {
        checkpoint()
        let tint = stampColor(label)
        let element = CanvasElement(
            pageIndex: currentPageIndex,
            kind: .stamp,
            frame: CGRect(x: 0.36, y: 0.45, width: 0.28, height: 0.07),
            text: label,
            fontName: "Arial",
            fontSize: 16,
            textColor: tint,
            opacity: 1,
            alignment: .center,
            isBold: true,
            borderWidth: 1.5,
            borderColor: tint,
            zIndex: nextZIndex
        )
        elements.append(element)
        selectedElementID = element.id
        interactionMode = .select
        inspectorMode = .stamp
        statusMessage = "\(label) stamp added. It is now selected and editable."
    }

    func addImage(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            statusMessage = "The selected image could not be prepared for the canvas."
            return
        }

        checkpoint()
        let page = pageSize()
        let pageAspect = page.width / max(1, page.height)
        let imageAspect = image.size.width / max(1, image.size.height)
        let width: CGFloat = 0.32
        let height = min(CGFloat(0.40), max(CGFloat(0.08), width * pageAspect / max(0.01, imageAspect)))
        let element = CanvasElement(
            pageIndex: currentPageIndex,
            kind: .image,
            frame: CGRect(x: 0.34, y: 0.42, width: width, height: height),
            opacity: 1,
            imageData: data,
            zIndex: nextZIndex
        )
        elements.append(element)
        selectedElementID = element.id
        interactionMode = .select
        inspectorMode = .image
        statusMessage = "Image added. Drag it or resize it from any corner."
    }

    func replaceSelectedImage(_ image: NSImage) {
        guard let id = selectedElementID,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return }
        checkpoint()
        updateElement(id: id, registerUndo: false) { $0.imageData = data }
        statusMessage = "Image replaced."
    }

    func removeSelectedElement() {
        guard let selectedElementID, let index = elements.firstIndex(where: { $0.id == selectedElementID }) else { return }
        checkpoint()
        elements.remove(at: index)
        self.selectedElementID = nil
        requestedInlineEditID = nil
        interactionMode = .select
        statusMessage = "Selected object removed."
    }

    func duplicateSelectedElement() {
        guard var selected = selectedElement else { return }
        checkpoint()
        selected = CanvasElement(
            pageIndex: selected.pageIndex,
            kind: selected.kind,
            frame: offsetFrame(selected.frame),
            text: selected.text,
            fontName: selected.fontName,
            fontSize: selected.fontSize,
            textColor: selected.textColor,
            opacity: selected.opacity,
            rotation: selected.rotation,
            alignment: selected.alignment,
            isBold: selected.isBold,
            isItalic: selected.isItalic,
            isUnderlined: selected.isUnderlined,
            shadowEnabled: selected.shadowEnabled,
            borderWidth: selected.borderWidth,
            borderColor: selected.borderColor,
            imageData: selected.imageData,
            zIndex: nextZIndex
        )
        elements.append(selected)
        selectedElementID = selected.id
        statusMessage = "Object duplicated."
    }

    func bringSelectedForward() {
        guard let id = selectedElementID else { return }
        checkpoint()
        updateElement(id: id, registerUndo: false) { $0.zIndex = nextZIndex }
    }

    func sendSelectedBackward() {
        guard let id = selectedElementID else { return }
        checkpoint()
        let currentMinimum = elements.map(\.zIndex).min() ?? 0
        updateElement(id: id, registerUndo: false) { $0.zIndex = currentMinimum - 1 }
    }

    func beginInteractiveEdit() {
        if interactionSnapshot == nil {
            interactionSnapshot = elements
        }
    }

    func endInteractiveEdit() {
        guard let snapshot = interactionSnapshot else { return }
        interactionSnapshot = nil
        if snapshot != elements {
            undoStack.append(snapshot)
            if undoStack.count > 60 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
    }

    func updateFrame(id: UUID, frame: CGRect) {
        updateElement(id: id, registerUndo: false) { $0.frame = clamp(frame) }
    }

    func updateSelected(_ change: (inout CanvasElement) -> Void) {
        guard let id = selectedElementID else { return }
        updateElement(id: id, registerUndo: false, change)
    }

    func beginInspectorEdit() {
        beginInteractiveEdit()
    }

    func endInspectorEdit() {
        endInteractiveEdit()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(elements)
        elements = previous
        if let selectedElementID, !elements.contains(where: { $0.id == selectedElementID }) {
            self.selectedElementID = nil
        }
        statusMessage = "Undo"
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(elements)
        elements = next
        if let selectedElementID, !elements.contains(where: { $0.id == selectedElementID }) {
            self.selectedElementID = nil
        }
        statusMessage = "Redo"
    }

    func export(to url: URL) throws {
        let output = PDFDocument()

        for pageIndex in 0..<document.pageCount {
            guard let sourcePage = document.page(at: pageIndex) else {
                throw PDFProcessingError(message: "Page \(pageIndex + 1) could not be prepared for export.")
            }

            let pageBounds = sourcePage.bounds(for: .mediaBox)
            let localFrame = CGRect(origin: .zero, size: pageBounds.size)
            let pageElements = elements
                .filter { $0.pageIndex == pageIndex }
                .sorted { $0.zIndex < $1.zIndex }

            let renderView = FlattenedPDFPageView(
                frame: localFrame,
                page: sourcePage,
                pageBounds: pageBounds,
                elements: pageElements
            )
            let pageData = renderView.dataWithPDF(inside: renderView.bounds)

            guard let renderedDocument = PDFDocument(data: pageData),
                  let renderedPage = renderedDocument.page(at: 0) else {
                throw PDFProcessingError(message: "Page \(pageIndex + 1) could not be rendered into the exported PDF.")
            }
            output.insert(renderedPage, at: output.pageCount)
        }

        guard output.pageCount == document.pageCount,
              output.pageCount > 0,
              output.write(to: url) else {
            throw PDFProcessingError(message: "The edited PDF could not be written.")
        }

        guard let check = PDFDocument(url: url),
              check.pageCount == document.pageCount,
              check.pageCount > 0 else {
            try? FileManager.default.removeItem(at: url)
            throw PDFProcessingError(message: "The exported file failed PDF validation and was not kept.")
        }
    }

    private var nextZIndex: Int { (elements.map(\.zIndex).max() ?? -1) + 1 }

    private func checkpoint() {
        undoStack.append(elements)
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func updateElement(id: UUID, registerUndo: Bool, _ change: (inout CanvasElement) -> Void) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        if registerUndo { checkpoint() }
        var copy = elements[index]
        change(&copy)
        copy.frame = clamp(copy.frame)
        elements[index] = copy
    }

    private func clamp(_ frame: CGRect) -> CGRect {
        let minimum: CGFloat = 0.025
        var width = min(1, max(minimum, frame.width))
        var height = min(1, max(minimum, frame.height))
        var x = min(1 - width, max(0, frame.minX))
        var y = min(1 - height, max(0, frame.minY))
        if !x.isFinite { x = 0 }
        if !y.isFinite { y = 0 }
        if !width.isFinite { width = 0.2 }
        if !height.isFinite { height = 0.1 }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func offsetFrame(_ frame: CGRect) -> CGRect {
        clamp(CGRect(x: frame.minX + 0.025, y: frame.minY + 0.025, width: frame.width, height: frame.height))
    }

    private func stampColor(_ label: String) -> CanvasRGBA {
        switch label.lowercased() {
        case "approved", "final": return .green
        case "draft", "experimental": return .blue
        case "notapproved", "notforpublicrelease": return .orange
        default: return .red
        }
    }


}


private final class FlattenedPDFPageView: NSView {
    private let page: PDFPage
    private let pageBounds: CGRect
    private let elements: [CanvasElement]

    init(frame frameRect: NSRect, page: PDFPage, pageBounds: CGRect, elements: [CanvasElement]) {
        self.page = page
        self.pageBounds = pageBounds
        self.elements = elements
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        NSColor.white.setFill()
        NSBezierPath(rect: bounds).fill()

        context.saveGState()
        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        for element in elements {
            draw(element, in: context)
        }
    }

    private func draw(_ element: CanvasElement, in context: CGContext) {
        let rect = localPDFRect(from: element.frame)

        context.saveGState()
        defer { context.restoreGState() }

        context.setAlpha(CGFloat(element.opacity))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat(element.rotation * .pi / 180))
        context.translateBy(x: -center.x, y: -center.y)

        if element.shadowEnabled {
            context.setShadow(
                offset: CGSize(width: 2, height: -2),
                blur: 4,
                color: NSColor.black.withAlphaComponent(0.26).cgColor
            )
        }

        switch element.kind {
        case .image:
            guard let data = element.imageData, let image = NSImage(data: data) else { return }
            let imageRect = aspectFitRect(imageSize: image.size, inside: rect)
            image.draw(
                in: imageRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: false,
                hints: nil
            )
            drawBorder(for: element, rect: rect)

        case .text, .stamp:
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = element.alignment.nsAlignment
            paragraph.lineBreakMode = .byWordWrapping

            let fontManager = NSFontManager.shared
            var font = fontManager.font(
                withFamily: element.fontName,
                traits: [],
                weight: 5,
                size: CGFloat(element.fontSize)
            ) ?? NSFont(name: element.fontName, size: CGFloat(element.fontSize))
                ?? NSFont.systemFont(ofSize: CGFloat(element.fontSize))

            if element.isBold {
                font = fontManager.convert(font, toHaveTrait: .boldFontMask)
            }
            if element.isItalic {
                font = fontManager.convert(font, toHaveTrait: .italicFontMask)
            }

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: element.textColor.nsColor,
                .paragraphStyle: paragraph
            ]
            if element.isUnderlined {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            let inset = rect.insetBy(
                dx: max(2, CGFloat(element.borderWidth) + 2),
                dy: max(1, CGFloat(element.borderWidth) + 1)
            )
            (element.text as NSString).draw(in: inset, withAttributes: attributes)
            drawBorder(for: element, rect: rect)
        }
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

    private func drawBorder(for element: CanvasElement, rect: CGRect) {
        guard element.borderWidth > 0 else { return }
        let path = NSBezierPath(rect: rect.insetBy(
            dx: CGFloat(element.borderWidth) / 2,
            dy: CGFloat(element.borderWidth) / 2
        ))
        path.lineWidth = CGFloat(element.borderWidth)
        element.borderColor.nsColor.setStroke()
        path.stroke()
    }

    private func localPDFRect(from normalizedTopLeftFrame: CGRect) -> CGRect {
        let width = normalizedTopLeftFrame.width * pageBounds.width
        let height = normalizedTopLeftFrame.height * pageBounds.height
        let x = normalizedTopLeftFrame.minX * pageBounds.width
        let yFromTop = normalizedTopLeftFrame.minY * pageBounds.height
        let y = pageBounds.height - yFromTop - height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
