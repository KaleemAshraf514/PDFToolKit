import Foundation

struct HistoryItem: Codable, Identifiable, Hashable {
    let id: UUID
    let toolID: PDFToolID?
    let displayName: String
    let outputSize: Int64?
    let createdAt: Date
    let wasSuccessful: Bool

    /// Small local preview only. The document itself is not duplicated into history.
    let thumbnailData: Data?

    /// Security-scoped bookmark to the file the user explicitly saved.
    /// This keeps History useful across launches without retaining another full copy.
    let bookmarkData: Data?

    init(
        id: UUID = UUID(),
        toolID: PDFToolID?,
        displayName: String,
        outputSize: Int64?,
        createdAt: Date = Date(),
        wasSuccessful: Bool = true,
        thumbnailData: Data? = nil,
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.toolID = toolID
        self.displayName = displayName
        self.outputSize = outputSize
        self.createdAt = createdAt
        self.wasSuccessful = wasSuccessful
        self.thumbnailData = thumbnailData
        self.bookmarkData = bookmarkData
    }
}
