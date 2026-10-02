import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var entitlements: EntitlementManager
    @EnvironmentObject private var history: HistoryStore

    @State private var selection = Set<UUID>()
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            historyToolbar
            Divider()

            if history.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(history.items) { item in
                            HistoryCard(
                                item: item,
                                isSelected: selection.contains(item.id),
                                onSelect: { toggleSelection(item.id) },
                                onEdit: { edit(item) },
                                onExport: { export(item) },
                                onShare: { share(item) },
                                onPrint: { printItem(item) },
                                onDelete: {
                                    history.delete(ids: [item.id])
                                    selection.remove(item.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
            }
        }
        .background(AppTheme.windowBackground)
        .alert("History", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var historyToolbar: some View {
        HStack {
            if !selection.isEmpty {
                Button {
                    history.delete(ids: selection)
                    selection.removeAll()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 10))
                        .frame(minHeight: 28)
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button {
                if allSelected {
                    selection.removeAll()
                } else {
                    selection = Set(history.items.map(\.id))
                }
            } label: {
                HStack(spacing: 8) {
                    Text(allSelected ? "Deselect All" : "All Select")
                    Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                }
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.text)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(history.items.isEmpty)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
    }

    private var allSelected: Bool {
        !history.items.isEmpty && selection.count == history.items.count
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 42, weight: .thin))
                .foregroundStyle(AppTheme.muted)
            Text("No history yet")
                .font(.system(size: 16, weight: .medium))
            Text("Files you save from PDF Toolkit will appear here with a local thumbnail.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func resolvedURL(_ item: HistoryItem) -> URL? {
        guard let url = history.resolvedURL(for: item) else {
            errorMessage = "The original saved file is no longer available at its saved location."
            return nil
        }
        return url
    }

    private func edit(_ item: HistoryItem) {
        guard let source = resolvedURL(item) else { return }
        Task {
            do {
                let directory = try await TemporaryFileManager.shared.makeTemporaryDirectory(prefix: "history-edit")
                let copy = directory.appendingPathComponent(source.lastPathComponent)
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                try FileManager.default.copyItem(at: source, to: copy)

                if copy.pathExtension.lowercased() == "pdf" {
                    appState.destination = .editor(copy)
                } else {
                    appState.openTool(
                        ToolRegistry.tool(.imagesToPDF),
                        entitlementManager: entitlements,
                        files: [copy]
                    )
                }
            } catch {
                errorMessage = "Unable to open this history item: \(error.localizedDescription)"
            }
        }
    }

    private func export(_ item: HistoryItem) {
        guard let source = resolvedURL(item) else { return }
        let ext = source.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext) ?? .data
        guard let destination = PanelService.saveFile(suggestedName: source.lastPathComponent, allowedType: type) else { return }

        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func share(_ item: HistoryItem) {
        guard let source = resolvedURL(item) else { return }
        Task {
            do {
                let directory = try await TemporaryFileManager.shared.makeTemporaryDirectory(prefix: "history-share")
                let copy = directory.appendingPathComponent(source.lastPathComponent)
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                try FileManager.default.copyItem(at: source, to: copy)
                SharingService.share(items: [copy])
            } catch {
                errorMessage = "Share failed: \(error.localizedDescription)"
            }
        }
    }

    private func printItem(_ item: HistoryItem) {
        guard let source = resolvedURL(item) else { return }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        PrintService.printFile(at: source)
    }
}

private struct HistoryCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: HistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onExport: () -> Void
    let onShare: () -> Void
    let onPrint: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                fileTypeIcon

                Text(item.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Button(action: onSelect) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? AppTheme.blue : AppTheme.muted)
                        .frame(width: 22, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                    Button(action: onExport) { Label("Export", systemImage: "square.and.arrow.down") }
                    Button(action: onShare) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button(action: onPrint) { Label("Print", systemImage: "printer") }
                    Divider()
                    Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.vertical")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.text)
                        .frame(width: 20, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
            }

            Button(action: onSelect) {
                thumbnail
                    .frame(maxWidth: .infinity)
                    .frame(height: 104)
                    .background(colorScheme == .dark ? Color.black.opacity(0.18) : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Text(item.outputSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
                Spacer()
                Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
            }
            .font(.system(size: 7.5))
            .foregroundStyle(AppTheme.muted)
        }
        .padding(8)
        .background(isSelected ? AppTheme.blue.opacity(0.075) : AppTheme.windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? AppTheme.blue.opacity(0.72) : AppTheme.line.opacity(colorScheme == .dark ? 0.66 : 0.78), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = item.thumbnailData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(3)
        } else {
            ZStack {
                AppTheme.surface
                Image(systemName: item.displayName.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "photo")
                    .font(.system(size: 30, weight: .thin))
                    .foregroundStyle(AppTheme.muted)
            }
        }
    }

    @ViewBuilder
    private var fileTypeIcon: some View {
        if item.displayName.lowercased().hasSuffix(".pdf") {
            Image(systemName: "doc.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.red)
        } else {
            ZStack {
                Circle()
                    .stroke(AppTheme.success, lineWidth: 1.2)
                    .frame(width: 16, height: 16)
                Image(systemName: "photo")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(AppTheme.success)
            }
        }
    }
}
