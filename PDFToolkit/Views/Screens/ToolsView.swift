import SwiftUI

struct ToolsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var entitlements: EntitlementManager
    @State private var selectedCategory: PDFToolCategory?

    private var displayedTools: [PDFToolDefinition] {
        guard let selectedCategory else { return ToolRegistry.tools }
        return ToolRegistry.tools.filter { $0.category == selectedCategory }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tools")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.text)

                Spacer()

                Menu {
                    Button("All Tools") { selectedCategory = nil }
                    Divider()
                    ForEach(PDFToolCategory.allCases, id: \.self) { category in
                        Button(category.rawValue) { selectedCategory = category }
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.muted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 34)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(displayedTools) { tool in
                        FigmaToolCard(tool: tool) {
                            appState.openTool(tool, entitlementManager: entitlements)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
        }
        .background(AppTheme.windowBackground)
    }
}

private struct FigmaToolCard: View {
    @EnvironmentObject private var entitlements: EntitlementManager
    @Environment(\.colorScheme) private var colorScheme

    let tool: PDFToolDefinition
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 11) {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(tool.tint)
                        .frame(width: 54, height: 54)
                        .overlay {
                            FigmaToolGlyph(toolID: tool.id)
                                .frame(width: 27, height: 27)
                        }
                        .shadow(color: tool.tint.opacity(0.24), radius: 7, y: 4)

                    Text(tool.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(minHeight: 28)
                }
                .frame(maxWidth: .infinity, minHeight: 126)
                .padding(.top, 13)
                .padding(.horizontal, 7)
                .background(hovering ? AppTheme.blue.opacity(0.045) : AppTheme.softCardBackground(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.line.opacity(colorScheme == .dark ? 0.42 : 0.18), lineWidth: 1)
                }

                tierIndicator
                    .padding(7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var tierIndicator: some View {
        if tool.isComingSoon {
            Text("SOON")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(height: 17)
                .background(AppTheme.muted)
                .clipShape(Capsule())
        } else if tool.tier == .pro && !entitlements.isPro {
            Circle()
                .fill(AppTheme.warning)
                .frame(width: 20, height: 20)
                .overlay {
                    FigmaCrownGlyph()
                        .frame(width: 10, height: 8)
                }
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
    }
}

/// Compact white monoline pictograms matching the supplied Figma family.
/// Every glyph is drawn on the same 32×32 logical grid with the same stroke,
/// so Merge, Split, Rotate, conversion, compression and OCR read as one set.
private struct FigmaToolGlyph: View {
    let toolID: PDFToolID

    var body: some View {
        Group {
            switch toolID {
            case .protect:
                Image(systemName: "lock")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white)

            case .unlock:
                Image(systemName: "lock.open")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white)

            default:
                FigmaLineGlyph(toolID: toolID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

private struct FigmaLineGlyph: View {
    let toolID: PDFToolID

    var body: some View {
        Canvas { context, size in
            let sx = size.width / 32
            let sy = size.height / 32
            let scale = min(sx, sy)
            let stroke = StrokeStyle(
                lineWidth: 2.05 * scale,
                lineCap: .round,
                lineJoin: .round
            )

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * sx, y: y * sy)
            }

            func strokePath(_ path: Path, width: CGFloat? = nil) {
                context.stroke(
                    path,
                    with: .color(.white),
                    style: StrokeStyle(
                        lineWidth: (width ?? 2.05) * scale,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            func line(_ points: [CGPoint], width: CGFloat? = nil) {
                guard let first = points.first else { return }
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                strokePath(path, width: width)
            }

            func document(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, fold: CGFloat = 4) {
                var path = Path()
                path.move(to: p(x, y))
                path.addLine(to: p(x + w - fold, y))
                path.addLine(to: p(x + w, y + fold))
                path.addLine(to: p(x + w, y + h))
                path.addLine(to: p(x, y + h))
                path.closeSubpath()

                path.move(to: p(x + w - fold, y))
                path.addLine(to: p(x + w - fold, y + fold))
                path.addLine(to: p(x + w, y + fold))
                strokePath(path)
            }

            func imageTile(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
                let rect = CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy)
                strokePath(Path(roundedRect: rect, cornerRadius: 1.8 * scale))

                var mountain = Path()
                mountain.move(to: p(x + 1.5, y + h - 2))
                mountain.addLine(to: p(x + w * 0.42, y + h * 0.53))
                mountain.addLine(to: p(x + w * 0.60, y + h * 0.70))
                mountain.addLine(to: p(x + w - 1.5, y + h * 0.38))
                strokePath(mountain, width: 1.45)

                let sun = CGRect(
                    x: (x + w * 0.66) * sx,
                    y: (y + 2.2) * sy,
                    width: 2.5 * scale,
                    height: 2.5 * scale
                )
                strokePath(Path(ellipseIn: sun), width: 1.35)
            }

            switch toolID {
            case .merge:
                // Reference-matched: two simple overlapping pages.
                document(x: 10, y: 5, w: 13, h: 19, fold: 4)
                document(x: 6, y: 9, w: 13, h: 19, fold: 4)

            case .split:
                // One page split down the middle with two restrained outward cues.
                document(x: 7, y: 5, w: 18, h: 22, fold: 4)
                line([p(16, 9), p(16, 24)], width: 1.55)
                line([p(14, 16), p(11.5, 16), p(13, 14.5)], width: 1.55)
                line([p(18, 16), p(20.5, 16), p(19, 14.5)], width: 1.55)

            case .rotate:
                // Page with a single compact clockwise arrow.
                document(x: 7, y: 8, w: 15, h: 19, fold: 4)
                var arc = Path()
                arc.move(to: p(16, 5.5))
                arc.addCurve(
                    to: p(27, 13.5),
                    control1: p(22, 4.5),
                    control2: p(27, 8)
                )
                arc.addCurve(
                    to: p(24.5, 18),
                    control1: p(27, 15.5),
                    control2: p(26, 17)
                )
                strokePath(arc)
                line([p(23.2, 15.5), p(24.7, 18.2), p(27.2, 16.7)], width: 1.8)

            case .compress:
                // Reference family: document in the middle, pressure moving inward.
                document(x: 10, y: 6, w: 12, h: 20, fold: 3.5)
                line([p(4, 12), p(7.5, 15.5), p(4, 19)], width: 1.75)
                line([p(28, 12), p(24.5, 15.5), p(28, 19)], width: 1.75)
                line([p(13, 12.5), p(19, 12.5)], width: 1.25)
                line([p(13, 16), p(19, 16)], width: 1.25)
                line([p(13, 19.5), p(19, 19.5)], width: 1.25)

            case .pdfToImages:
                // Clear left-to-right conversion: PDF/page → image.
                document(x: 3.5, y: 7, w: 10.5, h: 18, fold: 3)
                line([p(15.5, 16), p(18.5, 16)], width: 1.55)
                line([p(17.2, 14.5), p(18.8, 16), p(17.2, 17.5)], width: 1.55)
                imageTile(x: 20, y: 9, w: 9, h: 14)

            case .imagesToPDF:
                // Matching reverse conversion: image → PDF/page.
                imageTile(x: 3, y: 9, w: 9, h: 14)
                line([p(13.5, 16), p(16.5, 16)], width: 1.55)
                line([p(15.2, 14.5), p(16.8, 16), p(15.2, 17.5)], width: 1.55)
                document(x: 18, y: 7, w: 10.5, h: 18, fold: 3)

            case .watermark:
                // Simple page + centered text mark.
                document(x: 7, y: 5, w: 18, h: 22, fold: 4)
                line([p(11.5, 13), p(20.5, 13)], width: 1.75)
                line([p(16, 13), p(16, 21)], width: 1.75)

            case .ocr:
                // Minimal scan-frame + text mark. No extra document clutter.
                line([p(5, 11), p(5, 6), p(10, 6)])
                line([p(22, 6), p(27, 6), p(27, 11)])
                line([p(5, 21), p(5, 26), p(10, 26)])
                line([p(22, 26), p(27, 26), p(27, 21)])
                line([p(11, 13), p(21, 13)], width: 1.65)
                line([p(16, 13), p(16, 21)], width: 1.65)

            case .protect, .unlock:
                break
            }
        }
    }
}

private struct FigmaCrownGlyph: View {
    var body: some View {
        Canvas { context, size in
            var p = Path()
            p.move(to: CGPoint(x: 1, y: size.height * 0.25))
            p.addLine(to: CGPoint(x: size.width * 0.28, y: size.height * 0.58))
            p.addLine(to: CGPoint(x: size.width * 0.50, y: 1))
            p.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.58))
            p.addLine(to: CGPoint(x: size.width - 1, y: size.height * 0.25))
            p.addLine(to: CGPoint(x: size.width * 0.86, y: size.height - 1))
            p.addLine(to: CGPoint(x: size.width * 0.14, y: size.height - 1))
            p.closeSubpath()
            context.fill(p, with: .color(.white))
        }
    }
}
