import AppKit
import UniformTypeIdentifiers

@MainActor
enum PanelService {
    static func choosePDFs(allowsMultiple: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.urls : []
    }


    static func choosePDFsAndImages(allowsMultiple: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .jpeg, .png]
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseImages(allowsMultiple: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func saveFile(suggestedName: String, allowedType: UTType = .pdf) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [allowedType]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
