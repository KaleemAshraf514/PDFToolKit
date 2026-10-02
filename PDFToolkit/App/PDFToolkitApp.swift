import AppKit
import SwiftUI

@main
struct PDFToolkitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var entitlements = EntitlementManager()
    @StateObject private var history = HistoryStore()

    var body: some Scene {
        WindowGroup(AppConfig.appName) {
            RootView()
                .environmentObject(appState)
                .environmentObject(entitlements)
                .environmentObject(history)
        }
        .defaultSize(width: 1240, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("Home") { appState.destination = .home }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Tools") { appState.destination = .tools }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("History") { appState.destination = .history }
                    .keyboardShortcut("3", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Intentionally do not force Aqua/DarkAqua. The app follows macOS System Appearance.
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await TemporaryFileManager.shared.cleanupAll() }
    }
}
