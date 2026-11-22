# ArtNotes

A free, open-source sketching and note-taking app for iPad, written in Swift with SwiftUI and PencilKit.
No accounts, no subscriptions, no paywalls, no analytics. Every tool is available to everyone.

- **Bundle ID:** `com.ArtApps.ArtNotes`
- **Platform:** iPadOS 17+
- **License:** GPL-3.0-or-later (see `LICENSE`)

ArtNotes is an independent project inspired by the interaction style of paper-like sketching apps.
It is not affiliated with or endorsed by Evernote, and it contains none of their code, artwork or branding.

## Features

- Notebooks with multiple pages: blank, ruled, grid or dotted paper
- Pens, fountain pen, pencil, marker, watercolor, crayon, eraser (stroke or pixel) and lasso
- Any color (palette plus full color picker), adjustable stroke width, on-screen ruler
- Hold at the end of a stroke to snap it to a clean shape (built into PencilKit)
- **PDF import:** open a PDF from inside the app, or use "Open in ArtNotes" from Files; every page becomes a page you can draw on
- **PDF export:** share a notebook as a PDF (backgrounds and imported pages stay vector)
- Page overview with thumbnails; duplicate, delete and add pages
- Autosave; notebooks are plain folders in the app's Documents directory and show up in the Files app

## Gestures

| Gesture | Action |
| --- | --- |
| One finger or Apple Pencil | Draw |
| Two fingers (drag) | Scroll the page |
| Pinch | Zoom |
| Two-finger tap | Undo |
| Three-finger tap | Redo |
| Apple Pencil double-tap | Switch to the eraser and back |
| Hand/Pencil button in the toolbar | Toggle finger drawing (pencil-only mode) |

## Building

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open ArtNotes.xcodeproj
```

Pick an iPad simulator or your device and run. Command line:

```sh
xcodebuild test -project ArtNotes.xcodeproj -scheme ArtNotes \
  -destination 'platform=iOS Simulator,name=iPad (10th generation)' CODE_SIGNING_ALLOWED=NO
```

## GitHub Actions

`.github/workflows/build.yml` runs on every push and pull request:

1. generates the project with XcodeGen,
2. builds and runs the unit tests on an iPad simulator,
3. builds an **unsigned** `ArtNotes-unsigned.ipa` for devices and uploads it as a workflow artifact.

Pushing a tag such as `v1.0.0` also attaches the IPA to a GitHub release.

The IPA is unsigned so the project builds with no secrets. To install it, sign it with your own Apple ID using a
sideloading tool (for example AltStore or Sideloadly). To produce signed builds for TestFlight or the App Store,
add your signing certificate and provisioning profile as repository secrets and extend the `ipa` job.

## Project layout

```
project.yml                     XcodeGen spec (bundle ID, Info.plist, targets)
ArtNotes/
  ArtNotesApp.swift             App entry point, "Open in" PDF handling
  Models/Notebook.swift         Notebook, page and background types
  Store/NotebookStore.swift     File-backed storage, PDF import, thumbnails
  PDF/PageRenderer.swift        Paper styles, PDF page drawing, compositing
  PDF/PDFExporter.swift         Notebook to PDF export
  Editor/EditorModel.swift      Tool state, undo state, debounced autosave
  Editor/PageCanvasView.swift   PencilKit canvas, zoom and gestures
  Editor/ToolbarView.swift      Tool, color and width controls
  Editor/NotebookEditorView.swift  Editor screen and page overview
  Library/LibraryView.swift     Notebook grid, new/import/rename/delete/export
ArtNotesTests/                  Unit tests for storage, import and export
```

## Status and known limitations

This first version was written without access to Xcode, so it has not yet been compiled or run on a device.
The first CI run is the first real build; expect to fix a few compile errors or warnings.
Things worth checking on real hardware first:

- Two-finger tap undo and three-finger tap redo while a stroke is in progress
- Ink sharpness at high zoom levels (the canvas is scaled by the scroll view)
- Apple Pencil double-tap (uses the older `UIPencilInteraction` delegate callback, which is deprecated on newer iPadOS)

Not implemented yet: moving pages by drag, per-page PDF text search, handwriting search, iCloud sync, inserting images.

## License

ArtNotes is free software: you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any
later version. It is distributed without any warranty. Note that the GPL's terms conflict with the App Store's
distribution terms, so distribute builds via GitHub releases, sideloading or F-Droid-style stores such as AltStore sources.

## Contributing

Issues and pull requests are welcome. Please keep the app free of paywalls, tracking and network calls.
