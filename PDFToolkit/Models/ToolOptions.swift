import Foundation

enum CompressionPreset: String, CaseIterable, Identifiable {
    case low = "Low"
    case balanced = "Balanced"
    case strong = "Strong"
    var id: String { rawValue }
}

enum ImageOutputFormat: String, CaseIterable, Identifiable {
    case jpeg = "JPG"
    case png = "PNG"
    var id: String { rawValue }
}

enum PDFImagePageSize: String, CaseIterable, Identifiable {
    case original = "Original"
    case a4 = "A4"
    case letter = "Letter"
    var id: String { rawValue }
}

enum ImageFitMode: String, CaseIterable, Identifiable {
    case fit = "Fit"
    case fill = "Fill"
    var id: String { rawValue }
}

enum WatermarkPosition: String, CaseIterable, Identifiable {
    case center = "Center"
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
    var id: String { rawValue }
}
