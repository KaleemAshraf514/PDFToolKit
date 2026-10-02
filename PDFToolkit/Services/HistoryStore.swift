import AppKit
import Foundation
import PDFKit

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []

    private let defaultsKey = "pdfToolkit.history.metadata.v2"
    private let legacyDefaultsKey = "pdfToolkit.history.metadata.v1"

    init() {
        load()
    }

    func add(_ item: HistoryItem) {
        items.removeAll { $0.bookmarkData == item.bookmarkData && $0.displayName == item.displayName }
        items.insert(item, at: 0)
        trimIfNeeded()
        save()
    }

    /// Adds a file the user has actually saved. History stores only a small thumbnail,
    /// metadata and a sandbox bookmark — never a duplicate of the whole document.
    func addSavedFile(toolID: PDFToolID?, url: URL, outputSize: Int64?) {
        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let item = HistoryItem(
            toolID: toolID,
            displayName: url.lastPathComponent,
            outputSize: outputSize,
            thumbnailData: makeThumbnailData(for: url),
            bookmarkData: bookmark
        )
        add(item)
    }

    func delete(ids: Set<UUID>) {
        items.removeAll(where: { ids.contains($0.id) })
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func resolvedURL(for item: HistoryItem) -> URL? {
        guard let bookmarkData = item.bookmarkData else { return nil }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        } catch {
            return nil
        }
    }

    private func trimIfNeeded() {
        if items.count > AppConfig.historyLimit {
            items = Array(items.prefix(AppConfig.historyLimit))
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            items = decoded
            return
        }

        // Old v1 metadata has no thumbnails/bookmarks. Keep the app usable after upgrade.
        if let legacy = UserDefaults.standard.data(forKey: legacyDefaultsKey),
           let legacyItems = try? JSONDecoder().decode([LegacyHistoryItem].self, from: legacy) {
            items = legacyItems.map {
                HistoryItem(
                    id: $0.id,
                    toolID: $0.toolID,
                    displayName: $0.displayName,
                    outputSize: $0.outputSize,
                    createdAt: $0.createdAt,
                    wasSuccessful: $0.wasSuccessful
                )
            }
            save()
        }
    }

    private func makeThumbnailData(for url: URL) -> Data? {
        let size = NSSize(width: 320, height: 210)
        let image: NSImage?

        if url.pathExtension.lowercased() == "pdf" {
            image = PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: size, for: .mediaBox)
        } else {
            image = NSImage(contentsOf: url)
        }

        guard let source = image else { return nil }
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let imageSize = source.size
        if imageSize.width > 0, imageSize.height > 0 {
            let scale = min(size.width / imageSize.width, size.height / imageSize.height)
            let drawSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let rect = NSRect(
                x: (size.width - drawSize.width) / 2,
                y: (size.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        canvas.unlockFocus()

        guard let tiff = canvas.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
    }
}

private struct LegacyHistoryItem: Codable {
    let id: UUID
    let toolID: PDFToolID?
    let displayName: String
    let outputSize: Int64?
    let createdAt: Date
    let wasSuccessful: Bool
}
