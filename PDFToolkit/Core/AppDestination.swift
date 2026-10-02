import Foundation

enum AppDestination: Hashable {
    case home
    case history
    case tools
    case tool(PDFToolID)
    case editor(URL)
}
