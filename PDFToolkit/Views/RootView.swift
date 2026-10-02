import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if showsSidebar {
                    SidebarView()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.windowBackground)
            }
            .frame(minWidth: 1080, minHeight: 700)
            .background(AppTheme.windowBackground)

            if appState.isPremiumPresented {
                Color.black.opacity(0.34)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.dismissPremium()
                    }
                    .transition(.opacity)
                    .zIndex(10)

                PremiumView()
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: -34)
                                .combined(with: .opacity)
                                .combined(with: .scale(scale: 0.975)),
                            removal: .offset(y: -22)
                                .combined(with: .opacity)
                                .combined(with: .scale(scale: 0.985))
                        )
                    )
                    .zIndex(11)
            }
        }
        .animation(
            .spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.16),
            value: appState.isPremiumPresented
        )
        .animation(.easeInOut(duration: 0.18), value: appState.destination)
    }


    private var showsSidebar: Bool {
        switch appState.destination {
        case .home, .history, .tools:
            return true
        case .tool, .editor:
            return false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.destination {
        case .home:
            HomeView()
        case .history:
            HistoryView()
        case .tools:
            ToolsView()
        case .tool(let id):
            ToolWorkflowView(toolID: id)
        case .editor(let url):
            PDFEditorView(url: url)
        }
    }
}
