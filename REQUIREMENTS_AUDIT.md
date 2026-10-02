# PDF Toolkit v5 — Requirements & UX Audit

## Product workflow
- Home follows the supplied macOS/Figma direction: a `Choose from…` area first, with large Files and Image cards, plus a PDF Tools section on the same screen.
- Home accepts both click-to-select and drag & drop for PDF/JPG/PNG.
- Tool flow remains: Add files → configure options → live preview → process → validated result → Save & Open.
- The app follows system Light/Dark appearance.

## Tool behavior
- Merge: 2+ PDFs, remove/reorder, generated merged preview, final validated PDF.
- Split: page ranges or Every N pages, each generated part can be previewed.
- Rotate: selected pages, 90°/180°/270°, generated result is shown live.
- Compress: Low/Balanced/Strong, generated result is shown live, final size/reduction is reported.
- PDF → JPG/PNG: page range, format, DPI and JPEG quality, generated images are previewable.
- JPG/PNG → PDF: multiple images, reorder, page size and Fit/Fill, generated PDF preview.
- Watermark: text, opacity, size, position and page range with live generated PDF preview.
- Protect: password + confirmation + strength guidance. Encryption is non-visual, so preview stays on the source document while final output is validated as protected.
- Unlock: authorized password only; no password bypass. Successful unlocked result is previewed.
- OCR: Coming Soon/stretch feature and does not route to the Premium screen.

## Canvas/editor — rebuilt in v5
- SwiftUI-first editor with PDFKit/AppKit used only where native PDF/macOS capabilities are needed.
- Actual source PDF page is rendered as the fixed base layer.
- PDF page render, page thumbnails and font-family list are cached so changing text/color/geometry no longer re-renders a large PDF thumbnail on every state update.
- Added text, stamp and image objects are true interactive overlay objects.
- Click to select; drag the object body to move it.
- Eight resize handles: four corners + four edge handles.
- Double-click text/stamp to edit its text directly on the canvas.
- Right inspector provides exact text, font family, font size, bold/italic/underline, alignment, text color, opacity, rotation, shadow and border controls.
- Text color has immediate preset swatches plus the macOS Color Picker.
- Exact X/Y/W/H percentage fields are available in addition to direct dragging/resizing.
- Duplicate/delete, layer order and undo/redo are retained.
- Export rebuilds each edited PDF page through a native PDF-backed AppKit view and re-validates the resulting PDF before it is kept/opened.

## Monetization
- Free: Merge, Split, Rotate.
- Pro: Compress, PDF↔image conversion, Watermark, Protect, Unlock; OCR is Pro-tier but Coming Soon.
- Tool tiers are centralized in `ToolRegistry`.
- Testing entitlement override is centralized in `AppConfig.testingEntitlementOverride`.
- StoreKit 2 purchase/restore structure uses App Store Connect/Sandbox product metadata; the local StoreKit configuration has been removed.

## Intentional scope boundaries
- iCloud/Google Drive/Dropbox/OAuth are deferred by request.
- Account creation/backend authentication is deferred by request.
- OCR implementation remains stretch/Coming Soon.
- The supplied product requirements explicitly do not require a full arbitrary existing-PDF-content editor. The canvas supports adding/editing/moving/resizing/styling new text, stamps and images over the existing PDF and exports those changes into a new PDF. Reflowing/replacing every original PDF text object like Acrobat's full Edit PDF engine would be a separate larger feature.
