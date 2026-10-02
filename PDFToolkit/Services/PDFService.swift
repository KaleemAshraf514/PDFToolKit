import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

struct PDFProcessingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum PDFService {
    // MARK: Validation

    static func validatePDF(_ url: URL, maxBytes: Int64) throws {
        try validateSize(url, maxBytes: maxBytes)
        let ext = url.pathExtension.lowercased()
        guard ext == "pdf" else {
            throw PDFProcessingError(message: "\(url.lastPathComponent) is not a PDF file.")
        }
        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        if let type = values?.contentType, !type.conforms(to: .pdf) {
            throw PDFProcessingError(message: "\(url.lastPathComponent) has an unsupported file type.")
        }
        guard PDFDocument(url: url) != nil else {
            throw PDFProcessingError(message: "\(url.lastPathComponent) is corrupted, unsupported, or cannot be read as a PDF.")
        }
    }

    static func validateImage(_ url: URL, maxBytes: Int64) throws {
        try validateSize(url, maxBytes: maxBytes)
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
              (type.conforms(to: .jpeg) || type.conforms(to: .png)),
              NSImage(contentsOf: url) != nil else {
            throw PDFProcessingError(message: "\(url.lastPathComponent) is not a supported JPG/PNG image file.")
        }
    }

    private static func validateSize(_ url: URL, maxBytes: Int64) throws {
        let size = Int64((try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
        guard size <= maxBytes else {
            throw PDFProcessingError(message: "\(url.lastPathComponent) exceeds the \(ByteCountFormatter.string(fromByteCount: maxBytes, countStyle: .file)) file limit for the current plan.")
        }
    }

    // MARK: Merge

    static func merge(_ urls: [URL], outputURL: URL) throws {
        guard urls.count >= 2 else {
            throw PDFProcessingError(message: "Merge PDF requires at least two PDF files.")
        }
        let output = PDFDocument()
        var insertionIndex = 0
        for url in urls {
            guard let document = PDFDocument(url: url), !document.isLocked else {
                throw PDFProcessingError(message: "\(url.lastPathComponent) is encrypted or cannot be opened.")
            }
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex)?.copy() as? PDFPage else { continue }
                output.insert(page, at: insertionIndex)
                insertionIndex += 1
            }
        }
        guard insertionIndex > 0, output.write(to: outputURL) else {
            throw PDFProcessingError(message: "The merged PDF could not be written.")
        }
    }

    // MARK: Split

    static func split(_ url: URL, pageExpression: String, outputDirectory: URL) throws -> [URL] {
        guard let document = PDFDocument(url: url), !document.isLocked else {
            throw PDFProcessingError(message: "The PDF is encrypted or cannot be opened.")
        }
        let ranges = try parsePageGroups(pageExpression, pageCount: document.pageCount)
        guard !ranges.isEmpty else {
            throw PDFProcessingError(message: "Enter at least one valid page range, for example 1-3,5,8-10.")
        }

        var outputs: [URL] = []
        for (index, pages) in ranges.enumerated() {
            let splitDocument = PDFDocument()
            for pageNumber in pages {
                if let page = document.page(at: pageNumber - 1)?.copy() as? PDFPage {
                    splitDocument.insert(page, at: splitDocument.pageCount)
                }
            }
            let output = outputDirectory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-part-\(index + 1).pdf")
            guard splitDocument.pageCount > 0, splitDocument.write(to: output) else {
                throw PDFProcessingError(message: "One of the requested split files could not be written.")
            }
            outputs.append(output)
        }
        return outputs
    }

    static func splitEveryN(_ url: URL, every pageInterval: Int, outputDirectory: URL) throws -> [URL] {
        guard pageInterval > 0 else {
            throw PDFProcessingError(message: "Pages per file must be greater than zero.")
        }
        guard let document = PDFDocument(url: url), !document.isLocked else {
            throw PDFProcessingError(message: "The PDF is encrypted or cannot be opened.")
        }
        var groups: [String] = []
        var start = 1
        while start <= document.pageCount {
            let end = min(document.pageCount, start + pageInterval - 1)
            groups.append(start == end ? "\(start)" : "\(start)-\(end)")
            start = end + 1
        }
        return try split(url, pageExpression: groups.joined(separator: ","), outputDirectory: outputDirectory)
    }

    // MARK: Rotate

    static func rotate(_ url: URL, pagesExpression: String, degrees: Int, outputURL: URL) throws {
        guard [90, 180, 270].contains(degrees) else {
            throw PDFProcessingError(message: "Rotation must be 90°, 180°, or 270°.")
        }
        guard let document = PDFDocument(url: url), !document.isLocked else {
            throw PDFProcessingError(message: "The PDF is encrypted or cannot be opened.")
        }
        let pages = try flattenedPages(pagesExpression, pageCount: document.pageCount, emptyMeansAll: true)
        guard !pages.isEmpty else {
            throw PDFProcessingError(message: "Select at least one page to rotate.")
        }
        for number in pages {
            if let page = document.page(at: number - 1) {
                page.rotation = (page.rotation + degrees) % 360
            }
        }
        guard document.write(to: outputURL) else {
            throw PDFProcessingError(message: "The rotated PDF could not be written.")
        }
    }

    // MARK: Compression

    static func compress(_ url: URL, preset: CompressionPreset, outputURL: URL) throws {
        guard let document = PDFDocument(url: url), !document.isLocked else {
            throw PDFProcessingError(message: "The PDF is encrypted or cannot be opened.")
        }

        let fileManager = FileManager.default
        let workingDirectory = outputURL.deletingLastPathComponent()
        let optimizedURL = workingDirectory.appendingPathComponent(".pdf-toolkit-optimized-\(UUID().uuidString).pdf")
        let rasterURL = workingDirectory.appendingPathComponent(".pdf-toolkit-raster-\(UUID().uuidString).pdf")
        let candidates = [optimizedURL, rasterURL]
        defer {
            for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
                try? fileManager.removeItem(at: candidate)
            }
        }

        // PDF compression is not guaranteed to make every document smaller. A tiny,
        // mostly-vector PDF can become much larger when rasterized. Always generate
        // candidates and keep the smallest valid result, with the source itself as a
        // safe fallback. This guarantees "Compress" never inflates the file.
        let sourceSize = fileSize(at: url)
        var bestURL = url
        var bestSize = sourceSize

        let optimizeOptions: [PDFDocumentWriteOption: Any] = [.optimizeImagesForScreenOption: true]
        if document.write(toFile: optimizedURL.path, withOptions: optimizeOptions),
           PDFDocument(url: optimizedURL) != nil {
            let size = fileSize(at: optimizedURL)
            if size > 0, bestSize <= 0 || size < bestSize {
                bestURL = optimizedURL
                bestSize = size
            }
        }

        if preset != .low {
            // Balanced/strong create an additional lossy candidate. Lower DPI and JPEG
            // quality are deliberate; the source/optimized file is retained whenever
            // this raster candidate would be larger.
            let dpi: CGFloat = preset == .balanced ? 110 : 82
            let jpegQuality: CGFloat = preset == .balanced ? 0.56 : 0.38

            if try buildRasterCompressionCandidate(
                document,
                dpi: dpi,
                jpegQuality: jpegQuality,
                outputURL: rasterURL
            ), PDFDocument(url: rasterURL) != nil {
                let size = fileSize(at: rasterURL)
                if size > 0, bestSize <= 0 || size < bestSize {
                    bestURL = rasterURL
                    bestSize = size
                }
            }
        }

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        try fileManager.copyItem(at: bestURL, to: outputURL)

        guard let final = PDFDocument(url: outputURL), final.pageCount > 0 else {
            throw PDFProcessingError(message: "Compression failed.")
        }
    }

    private static func buildRasterCompressionCandidate(
        _ document: PDFDocument,
        dpi: CGFloat,
        jpegQuality: CGFloat,
        outputURL: URL
    ) throws -> Bool {
        let rebuilt = PDFDocument()

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let pixelSize = NSSize(
                width: max(1, bounds.width * dpi / 72),
                height: max(1, bounds.height * dpi / 72)
            )
            let rendered = page.thumbnail(of: pixelSize, for: .mediaBox)
            guard let tiff = rendered.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality]),
                  let jpegImage = NSImage(data: jpeg) else {
                return false
            }

            let options: [PDFPage.ImageInitializationOption: Any] = [
                .compressionQuality: jpegQuality,
                .mediaBox: NSValue(rect: bounds),
                .upscaleIfSmaller: false
            ]
            guard let rasterPage = PDFPage(image: jpegImage, options: options) else {
                return false
            }
            rebuilt.insert(rasterPage, at: rebuilt.pageCount)
        }

        guard rebuilt.pageCount == document.pageCount else { return false }
        return rebuilt.write(to: outputURL)
    }

    private static func fileSize(at url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    // MARK: PDF -> Images

    static func pdfToImages(_ url: URL, pagesExpression: String, format: ImageOutputFormat, dpi: CGFloat, jpegQuality: CGFloat, outputDirectory: URL) throws -> [URL] {
        guard let document = PDFDocument(url: url), !document.isLocked else {
            throw PDFProcessingError(message: "The PDF is encrypted or cannot be opened.")
        }
        let pages = try flattenedPages(pagesExpression, pageCount: document.pageCount, emptyMeansAll: true)
        var outputs: [URL] = []

        for pageNumber in pages {
            guard let page = document.page(at: pageNumber - 1) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let pixelSize = NSSize(width: max(1, bounds.width * dpi / 72), height: max(1, bounds.height * dpi / 72))
            let image = page.thumbnail(of: pixelSize, for: .mediaBox)
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff) else {
                throw PDFProcessingError(message: "Page \(pageNumber) could not be rendered.")
            }

            let data: Data?
            let ext: String
            switch format {
            case .jpeg:
                data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality])
                ext = "jpg"
            case .png:
                data = bitmap.representation(using: .png, properties: [:])
                ext = "png"
            }
            guard let data else {
                throw PDFProcessingError(message: "Page \(pageNumber) could not be encoded.")
            }
            let output = outputDirectory.appendingPathComponent("page-\(pageNumber).\(ext)")
            try data.write(to: output, options: .atomic)
            outputs.append(output)
        }
        return outputs
    }

    // MARK: Images -> PDF

    static func imagesToPDF(_ urls: [URL], pageSize: PDFImagePageSize, fitMode: ImageFitMode, outputURL: URL) throws {
        guard !urls.isEmpty else {
            throw PDFProcessingError(message: "Choose at least one image.")
        }
        let output = PDFDocument()

        for url in urls {
            guard let image = NSImage(contentsOf: url) else {
                throw PDFProcessingError(message: "\(url.lastPathComponent) could not be read as an image.")
            }

            let targetSize: NSSize
            switch pageSize {
            case .original:
                targetSize = image.size
            case .a4:
                targetSize = NSSize(width: 595, height: 842)
            case .letter:
                targetSize = NSSize(width: 612, height: 792)
            }

            let canvas = NSImage(size: targetSize)
            canvas.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: targetSize)).fill()
            let destination = fittedRect(imageSize: image.size, pageSize: targetSize, mode: fitMode)
            image.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1.0)
            canvas.unlockFocus()

            let options: [PDFPage.ImageInitializationOption: Any] = [
                .mediaBox: NSValue(rect: NSRect(origin: .zero, size: targetSize)),
                .upscaleIfSmaller: true,
                .compressionQuality: 0.92
            ]
            guard let page = PDFPage(image: canvas, options: options) else {
                throw PDFProcessingError(message: "A PDF page could not be created from \(url.lastPathComponent).")
            }
            output.insert(page, at: output.pageCount)
        }

        guard output.write(to: outputURL) else {
            throw PDFProcessingError(message: "The PDF could not be written.")
        }
    }

    // MARK: Watermark

    static func watermark(
        _ url: URL,
        text: String,
        opacity: CGFloat,
        fontSize: CGFloat,
        normalizedCenter: CGPoint,
        pagesExpression: String,
        outputURL: URL
    ) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PDFProcessingError(message: "Enter watermark text.")
        }
        guard let document = PDFDocument(url: url), !document.isLocked else {
            throw PDFProcessingError(message: "The PDF is encrypted or cannot be opened.")
        }
        let pages = Set(try flattenedPages(pagesExpression, pageCount: document.pageCount, emptyMeansAll: true))

        let safeFontSize = min(max(fontSize, 6), 360)
        let font = NSFont.systemFont(ofSize: safeFontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let measured = (text as NSString).size(withAttributes: attributes)

        for pageNumber in pages {
            guard let page = document.page(at: pageNumber - 1) else { continue }
            let pageBounds = page.bounds(for: .mediaBox)

            // Size the annotation from the actual font metrics instead of estimating
            // from character count. The previous character-count formula clipped wide
            // uppercase glyphs (for example the final letter in long ALL-CAPS text).
            let width = max(28, measured.width + 24)
            let height = max(24, measured.height + 12)

            let normalizedX = min(1, max(0, normalizedCenter.x))
            let normalizedY = min(1, max(0, normalizedCenter.y))
            let requestedCenter = CGPoint(
                x: pageBounds.minX + normalizedX * pageBounds.width,
                y: pageBounds.maxY - normalizedY * pageBounds.height
            )

            // Keep the editable watermark box on-page whenever it fits. Very large
            // watermarks may naturally extend to the page edges, but the text itself
            // is no longer clipped by an undersized annotation rectangle.
            let minCenterX = pageBounds.minX + min(width, pageBounds.width) / 2
            let maxCenterX = pageBounds.maxX - min(width, pageBounds.width) / 2
            let minCenterY = pageBounds.minY + min(height, pageBounds.height) / 2
            let maxCenterY = pageBounds.maxY - min(height, pageBounds.height) / 2
            let centerX = min(max(requestedCenter.x, minCenterX), maxCenterX)
            let centerY = min(max(requestedCenter.y, minCenterY), maxCenterY)

            let annotationBounds = CGRect(
                x: centerX - width / 2,
                y: centerY - height / 2,
                width: width,
                height: height
            )
            let annotation = PDFAnnotation(
                bounds: annotationBounds,
                forType: .freeText,
                withProperties: nil
            )
            annotation.contents = text
            annotation.font = font
            annotation.fontColor = NSColor(calibratedWhite: 0.18, alpha: min(1, max(0.02, opacity)))
            annotation.color = .clear
            annotation.alignment = .center
            page.addAnnotation(annotation)
        }

        guard document.write(to: outputURL) else {
            throw PDFProcessingError(message: "The watermarked PDF could not be written.")
        }
    }

    // MARK: Protect / Unlock

    static func protect(_ url: URL, password: String, outputURL: URL) throws {
        guard password.count >= 6 else {
            throw PDFProcessingError(message: "Use a password with at least 6 characters.")
        }
        guard let document = PDFDocument(url: url), !document.isLocked else {
            throw PDFProcessingError(message: "The PDF is already encrypted or cannot be opened.")
        }
        let options: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: password,
            .ownerPasswordOption: password
        ]
        guard document.write(toFile: outputURL.path, withOptions: options) else {
            throw PDFProcessingError(message: "The protected PDF could not be written.")
        }
    }

    static func unlock(_ url: URL, password: String, outputURL: URL) throws {
        guard let document = PDFDocument(url: url) else {
            throw PDFProcessingError(message: "The PDF cannot be opened.")
        }
        if document.isLocked {
            guard document.unlock(withPassword: password) else {
                throw PDFProcessingError(message: "The password is incorrect or this PDF uses unsupported protection.")
            }
        }

        // Rebuild from page copies instead of simply re-writing the unlocked source.
        // This avoids carrying the original encryption dictionary into the output.
        let unlocked = PDFDocument()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index)?.copy() as? PDFPage else { continue }
            unlocked.insert(page, at: unlocked.pageCount)
        }
        guard unlocked.pageCount > 0, unlocked.write(to: outputURL) else {
            throw PDFProcessingError(message: "The unlocked PDF could not be written.")
        }
        guard let verification = PDFDocument(url: outputURL), !verification.isLocked, verification.pageCount > 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw PDFProcessingError(message: "The unlocked output failed validation.")
        }
    }

    // MARK: ZIP export

    static func createZIP(from urls: [URL], outputURL: URL) throws {
        guard !urls.isEmpty else {
            throw PDFProcessingError(message: "There are no files to add to the ZIP archive.")
        }

        let fileManager = FileManager.default
        let parent = outputURL.deletingLastPathComponent()
        let staging = parent.appendingPathComponent("ZIP-Contents-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        for (index, source) in urls.enumerated() {
            var name = source.lastPathComponent
            var destination = staging.appendingPathComponent(name)
            if fileManager.fileExists(atPath: destination.path) {
                name = "\(index + 1)-\(name)"
                destination = staging.appendingPathComponent(name)
            }
            try fileManager.copyItem(at: source, to: destination)
        }

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", staging.path, outputURL.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0, fileManager.fileExists(atPath: outputURL.path) else {
            throw PDFProcessingError(message: "The ZIP archive could not be created.")
        }
    }

    // MARK: Page expression helpers

    static func flattenedPages(_ expression: String, pageCount: Int, emptyMeansAll: Bool = false) throws -> [Int] {
        if expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, emptyMeansAll {
            return Array(1...max(1, pageCount))
        }
        let groups = try parsePageGroups(expression, pageCount: pageCount)
        var seen = Set<Int>()
        var result: [Int] = []
        for group in groups {
            for page in group where seen.insert(page).inserted {
                result.append(page)
            }
        }
        return result
    }

    static func parsePageGroups(_ expression: String, pageCount: Int) throws -> [[Int]] {
        let chunks = expression
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var groups: [[Int]] = []
        for chunk in chunks {
            if chunk.contains("-") {
                let parts = chunk.split(separator: "-", maxSplits: 1).map(String.init)
                guard parts.count == 2,
                      let start = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                      let end = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                      start >= 1, end >= start, end <= pageCount else {
                    throw PDFProcessingError(message: "Invalid page range '\(chunk)'. The document has \(pageCount) pages.")
                }
                groups.append(Array(start...end))
            } else {
                guard let page = Int(chunk), page >= 1, page <= pageCount else {
                    throw PDFProcessingError(message: "Invalid page '\(chunk)'. The document has \(pageCount) pages.")
                }
                groups.append([page])
            }
        }
        return groups
    }

    private static func fittedRect(imageSize: NSSize, pageSize: NSSize, mode: ImageFitMode) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return NSRect(origin: .zero, size: pageSize) }
        let scaleX = pageSize.width / imageSize.width
        let scaleY = pageSize.height / imageSize.height
        let scale = mode == .fit ? min(scaleX, scaleY) : max(scaleX, scaleY)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(x: (pageSize.width - size.width) / 2, y: (pageSize.height - size.height) / 2, width: size.width, height: size.height)
    }
}
