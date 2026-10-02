import Foundation

actor TemporaryFileManager {
    static let shared = TemporaryFileManager()

    private var trackedURLs: Set<URL> = []

    func makeTemporaryDirectory(prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFToolkit", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        trackedURLs.insert(directory)
        return directory
    }

    func track(_ url: URL) {
        trackedURLs.insert(url)
    }

    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        trackedURLs.remove(url)
    }

    func cleanupContainer(containing url: URL) {
        let standardizedPath = url.standardizedFileURL.path
        if let container = trackedURLs.first(where: { standardizedPath.hasPrefix($0.standardizedFileURL.path + "/") }) {
            try? FileManager.default.removeItem(at: container)
            trackedURLs.remove(container)
        }
    }

    func cleanupAll() {
        for url in trackedURLs {
            try? FileManager.default.removeItem(at: url)
        }
        trackedURLs.removeAll()
    }
}
