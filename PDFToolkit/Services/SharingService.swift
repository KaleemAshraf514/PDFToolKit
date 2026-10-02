import AppKit

@MainActor
enum SharingService {
    static func share(items: [Any]) {
        guard let contentView = NSApp.keyWindow?.contentView ?? NSApp.windows.first?.contentView else { return }
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
    }
}
