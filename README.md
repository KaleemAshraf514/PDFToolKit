# PDF Toolkit for macOS

A native macOS PDF utility built with **SwiftUI**, **PDFKit**, **AppKit**, and **StoreKit 2**.

PDF Toolkit provides common PDF operations, a custom visual PDF canvas/editor, live previews, history, printing/sharing, and Free/Pro feature gating in a single macOS app.

## Highlights

- Native macOS interface with system Light/Dark appearance
- PDF import from Finder and image import for image-to-PDF workflows
- Live PDF previews for tool operations
- Custom PDF canvas/editor with draggable, resizable, and rotatable overlays
- Text, stamp, and image elements on the editor canvas
- Export of edited pages into a flattened PDF
- File validation and temporary-file cleanup
- Saved-output history with thumbnails and file bookmarks
- Native macOS print and share flows
- StoreKit 2 subscriptions and lifetime purchase support
- Free/Pro tool gating with App Store entitlement checks

## PDF Tools

| Tool | Tier | Status |
| --- | --- | --- |
| Merge PDF | Free | Available |
| Split PDF | Free | Available |
| Rotate PDF | Free | Available |
| Compress PDF | Pro | Available |
| PDF to JPG/PNG | Pro | Available |
| JPG/PNG to PDF | Pro | Available |
| Watermark PDF | Pro | Available |
| Protect PDF | Pro | Available |
| Unlock PDF | Pro | Available |
| OCR PDF | Pro | Coming soon |

Free accounts currently use a **10 MB per-file limit** and Pro accounts use a **200 MB per-file limit**.

## PDF Editor Architecture

The editor intentionally combines PDFKit and AppKit instead of trying to make PDFKit handle every editing interaction.

```text
PDF file
   ↓
PDFKit.PDFDocument
   ↓
PDFKit.PDFPage
   ↓
Custom AppKit page view
   ↓
PDF page is rendered as the base layer
   ↓
Text / Stamp / Image CanvasElements
   ↓
Custom NSView interaction layer
   ↓
Drag / Resize / Rotate / Inline text editing
   ↓
Export renderer
   ↓
Original page + overlays rendered together
   ↓
Final PDFDocument written to disk
```

### PDFKit

PDFKit is used for document/page loading, PDF page rendering, thumbnails, page manipulation, password-related PDF operations, validation, printing, and final PDF document assembly.

### Custom AppKit canvas

The interactive editor uses custom AppKit views inside SwiftUI through `NSViewRepresentable`.

Canvas elements store page-relative/normalized geometry and styling data, which keeps their positions stable while zooming or resizing the window.

The current editable overlay types are:

- Text
- Stamp
- Image

During export, the original PDF page and the editor overlays are rendered together into the output PDF.

## Live Preview

Tool workflows generate temporary preview outputs and display them using PDFKit.

Visual options use a debounced preview flow so repeated changes do not trigger unnecessary processing on every small UI update.

Temporary previews are cleaned up by the app and are separate from files explicitly saved by the user.

## StoreKit 2

The app uses real StoreKit 2 APIs rather than a bundled local `.storekit` configuration.

Configured product identifiers:

| Product | Identifier |
| --- | --- |
| Weekly | `com.nt.weekly` |
| Monthly | `com.nt.monthly` |
| Yearly | `com.nt.yearly` |
| Lifetime | `com.nt.lifetime` |

Product information is loaded with `Product.products(for:)`, localized prices come from `Product.displayPrice`, purchases use `Product.purchase()`, and entitlement state is reconciled with verified StoreKit transactions/current entitlements.

For App Store Connect or Sandbox testing, use the Apple Developer team that owns the app's bundle identifier:

```text
com.nt.testapp
```

The centralized development entitlement switch is in:

```text
PDFToolkit/Core/AppConfig.swift
```

Available modes:

| Mode | Purpose |
| --- | --- |
| `.normal` | Use verified StoreKit entitlement state |
| `.forcePro` | Development-only forced Pro |
| `.forceFree` | Development-only forced Free |

The repository currently defaults to `.normal`.

## Navigation

The sidebar is visible on the top-level **Home**, **History**, and **Tools** screens.

When a tool workflow or PDF canvas/editor is opened, the sidebar is hidden so the working area can use the full window. Returning to a top-level screen restores it.

For Free users, upgrade/restore UI and Pro tool indicators are shown. When an active Pro entitlement is present, those upgrade indicators are removed.

## Tech Stack

| Technology | Usage |
| --- | --- |
| Swift | Application language |
| SwiftUI | Main application UI and state-driven screens |
| AppKit | Native canvas interaction, panels, printing/sharing integration |
| PDFKit | PDF loading, rendering, manipulation, validation and writing |
| StoreKit 2 | Products, purchases and entitlement state |
| Core Graphics | PDF/editor rendering support |

## Project Structure

```text
PDFToolkit/
├── App/
│   └── PDFToolkitApp.swift
├── Core/
│   ├── AppConfig.swift
│   ├── AppDestination.swift
│   ├── AppState.swift
│   └── AppTheme.swift
├── Models/
├── Resources/
├── Services/
│   ├── EntitlementManager.swift
│   ├── HistoryStore.swift
│   ├── PDFService.swift
│   ├── PanelService.swift
│   ├── PrintService.swift
│   ├── SharingService.swift
│   └── TemporaryFileManager.swift
└── Views/
    ├── Components/
    ├── Editor/
    └── Screens/
```

Important files:

| File | Responsibility |
| --- | --- |
| `PDFService.swift` | PDF processing engine |
| `ToolWorkflowView.swift` | Tool workflow and live-preview coordination |
| `PDFEditorModel.swift` | Editor state, CanvasElements, export |
| `PDFEditorView.swift` | Editor UI and native AppKit canvas |
| `EntitlementManager.swift` | StoreKit 2 products, purchases, entitlements |
| `HistoryStore.swift` | Saved-output history and bookmarks |
| `AppState.swift` | App routing/navigation state |

## Requirements

- macOS 14.0 or later
- Xcode with macOS 14+ SDK support
- Apple Developer signing team for StoreKit/App Store Connect testing

## Run Locally

Clone the repository:

```bash
git clone https://github.com/KaleemAshraf514/PDFToolKit.git
cd PDFToolKit
```

Open:

```text
PDFToolkit.xcodeproj
```

Then choose the appropriate Apple Developer team under **Signing & Capabilities** and run the macOS target.

## Security Notes

- Password values are not intentionally persisted in app history.
- Temporary processing files are managed separately from explicitly saved outputs.
- Unlock functionality is intended only for PDFs the user is authorized to access.
- App Store purchase state is based on verified StoreKit transactions when running in normal entitlement mode.

## Current Status

The main PDF workflows, editor/canvas, history, StoreKit integration, navigation behavior, and Free/Pro gating are implemented.

**OCR PDF is currently marked Coming Soon.**
