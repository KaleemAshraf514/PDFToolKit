import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var destination: AppDestination = .home
    @Published var isPremiumPresented = false
    @Published var pendingToolAfterPurchase: PDFToolID?

    private var pendingFilesByTool: [PDFToolID: [URL]] = [:]

    func openTool(_ tool: PDFToolDefinition, entitlementManager: EntitlementManager, files: [URL] = []) {
        if !files.isEmpty {
            pendingFilesByTool[tool.id] = files
        }

        if tool.isComingSoon {
            destination = .tool(tool.id)
            return
        }

        if tool.tier == .pro && !entitlementManager.isPro {
            presentPremium(returnTo: tool.id)
        } else {
            destination = .tool(tool.id)
        }
    }

    func presentPremium(returnTo toolID: PDFToolID? = nil) {
        pendingToolAfterPurchase = toolID
        isPremiumPresented = true
    }

    func dismissPremium() {
        if let pendingToolAfterPurchase {
            pendingFilesByTool[pendingToolAfterPurchase] = nil
        }
        isPremiumPresented = false
        pendingToolAfterPurchase = nil
    }

    func consumePendingFiles(for toolID: PDFToolID) -> [URL] {
        let files = pendingFilesByTool[toolID] ?? []
        pendingFilesByTool[toolID] = nil
        return files
    }

    func completeUpgrade() {
        isPremiumPresented = false
        if let pendingToolAfterPurchase {
            destination = .tool(pendingToolAfterPurchase)
            self.pendingToolAfterPurchase = nil
        }
    }
}
