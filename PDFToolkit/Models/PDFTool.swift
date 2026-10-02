import Foundation
import SwiftUI

enum ToolTier: String, Codable, CaseIterable {
    case free = "FREE"
    case pro = "PRO"
}

enum PDFToolCategory: String, Codable, CaseIterable {
    case organize = "Organize"
    case convert = "Convert"
    case optimize = "Optimize"
    case security = "Security"
    case edit = "Edit"
}

enum PDFToolID: String, Codable, CaseIterable, Identifiable {
    case merge
    case split
    case rotate
    case compress
    case pdfToImages
    case imagesToPDF
    case watermark
    case protect
    case unlock
    case ocr

    var id: String { rawValue }
}

struct PDFToolDefinition: Identifiable, Hashable {
    let id: PDFToolID
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let background: Color
    let tier: ToolTier
    let category: PDFToolCategory
    let isComingSoon: Bool
}

enum ToolRegistry {
    static let tools: [PDFToolDefinition] = [
        .init(id: .merge, title: "Merge PDF", subtitle: "Combine multiple PDF files into one document.", systemImage: "doc.on.doc", tint: Color(red: 0.749, green: 0.447, blue: 0.122), background: Color(red: 1.0, green: 0.96, blue: 0.87), tier: .free, category: .organize, isComingSoon: false),
        .init(id: .split, title: "Split PDF", subtitle: "Extract page ranges into separate PDF files.", systemImage: "scissors", tint: Color(red: 0.647, green: 0.157, blue: 0.969), background: Color(red: 0.95, green: 0.92, blue: 1.0), tier: .free, category: .organize, isComingSoon: false),
        .init(id: .rotate, title: "Rotate PDF", subtitle: "Rotate selected pages by 90°, 180°, or 270°.", systemImage: "rotate.right", tint: Color(red: 0.000, green: 0.780, blue: 0.698), background: Color(red: 0.88, green: 0.98, blue: 0.99), tier: .free, category: .organize, isComingSoon: false),
        .init(id: .compress, title: "Compress PDF", subtitle: "Reduce PDF size with low, balanced, or strong compression.", systemImage: "doc.zipper", tint: Color(red: 0.494, green: 0.729, blue: 0.988), background: Color(red: 0.91, green: 0.95, blue: 1.0), tier: .pro, category: .optimize, isComingSoon: false),
        .init(id: .pdfToImages, title: "PDF to JPG/PNG", subtitle: "Export PDF pages as image files.", systemImage: "photo.on.rectangle", tint: Color(red: 0.984, green: 0.067, blue: 0.173), background: Color(red: 1.0, green: 0.92, blue: 0.95), tier: .pro, category: .convert, isComingSoon: false),
        .init(id: .imagesToPDF, title: "JPG/PNG to PDF", subtitle: "Create one PDF from multiple image files.", systemImage: "photo.stack", tint: Color(red: 0.000, green: 0.780, blue: 0.698), background: Color(red: 0.89, green: 0.98, blue: 0.94), tier: .pro, category: .convert, isComingSoon: false),
        .init(id: .watermark, title: "Watermark PDF", subtitle: "Add a configurable text watermark to selected pages.", systemImage: "textformat", tint: Color(red: 0.647, green: 0.157, blue: 0.969), background: Color(red: 0.95, green: 0.93, blue: 1.0), tier: .pro, category: .edit, isComingSoon: false),
        .init(id: .protect, title: "Protect PDF", subtitle: "Add an open password to a PDF document.", systemImage: "lock.fill", tint: Color(red: 1.000, green: 0.251, blue: 0.424), background: Color(red: 1.0, green: 0.91, blue: 0.93), tier: .pro, category: .security, isComingSoon: false),
        .init(id: .unlock, title: "Unlock PDF", subtitle: "Remove password protection from an authorized PDF.", systemImage: "lock.open.fill", tint: Color(red: 0.388, green: 0.729, blue: 0.165), background: Color(red: 0.91, green: 0.98, blue: 0.88), tier: .pro, category: .security, isComingSoon: false),
        .init(id: .ocr, title: "OCR PDF", subtitle: "Make scanned PDF pages searchable.", systemImage: "text.viewfinder", tint: Color(red: 0.592, green: 0.886, blue: 0.984), background: Color(red: 0.91, green: 0.95, blue: 1.0), tier: .pro, category: .convert, isComingSoon: true)
    ]

    static func tool(_ id: PDFToolID) -> PDFToolDefinition {
        tools.first(where: { $0.id == id })!
    }
}
