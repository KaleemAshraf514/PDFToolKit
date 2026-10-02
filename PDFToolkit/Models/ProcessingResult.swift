import Foundation

struct ProcessingResult: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let displayName: String
    let size: Int64?

    init(url: URL, displayName: String? = nil) {
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }
}
