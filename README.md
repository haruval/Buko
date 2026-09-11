# Buko

A Pencil-first notes app exploring spatial collaboration with AI. Built with SwiftUI, PencilKit, SwiftData, and native clear Liquid Glass.

## Run

1. Open `Buko.xcodeproj` in Xcode 26 or newer (validated with Xcode 27).
2. Select the **Buko** scheme and an iPad simulator, or your iPad Pro 13-inch (M4).
3. For a physical device, select your development team under **Signing & Capabilities** and enable Developer Mode on the iPad if needed.
4. Run. The first launch creates one empty note; subsequent launches open the newest note.

Requires iOS/iPadOS 26+. No API keys, packages, or network services are required.

## Current interactions

- Write with Apple Pencil. Touch pans; pinch zooms.
- The canvas starts at page width. Pinching reveals four temporary page-fit corner guides; releasing hides them. Release within 8% of page-fit zoom to snap back. Zooming farther out and scrolling downward remain available.
- Use the left glass sidebar to create or switch notes. Long-press a note to rename it or move it to Trash.
- Hide the sidebar with its upper-right button; the floating sidebar button grows back into the library.
- The bottom glass shelf provides a pen, stroke eraser, undo, and redo. Hold the pencil button to enable finger drawing.
- The top-right settings button expands into a glass panel. Open **Trash** to restore deleted notes, including their drawings. Notes stay in Trash until restored; there is no automatic purge.
- The light canvas is `#F2F0EF`; dark mode is pure black. Clear glass has a translucent light-green or deeper-green tint.
- Notes and PencilKit strokes save locally with SwiftData. Writes are debounced, with explicit saves on note switching and scene deactivation. Storage errors are surfaced without replacing saved files.

## Source layout

- `Buko/ContentView.swift` — workspace composition, selection, and save lifecycle.
- `Buko/Models/Note.swift` — persisted note metadata and drawing data.
- `Buko/Canvas/` — PencilKit bridge, paper/viewport geometry, and transient tool state.
- `Buko/Views/` — expanding glass panels, notes library, settings/Trash, and tool shelf.

## Scope

This is the initial canvas scaffold. AI gestures, bulletin extraction, generated handwriting, voice collaboration, synchronization, and export are not implemented. The workspace currently has a finite 3,000-point width with a 1,000-point page guide and grows downward in chunks. Viewport position and undo history are transient; loading a note fits its page again. The first implementation uses fixed ink width and a stroke eraser.

## Checks

Run the geometry and real SwiftData storage checks on macOS:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Tests/run-checks.sh
```

These check page-fit projection, snap thresholds, scroll/rotation math, soft deletion, active/trash filtering, restore after reopening the store, and preservation of drawing bytes. Databases are temporary and separate from the app's notes.

The local, gitignored `AGENTS.md` holds the detailed product vision, engineering plan, and device validation checklist.

## Native API references

- [Apple: PencilKit canvas](https://developer.apple.com/documentation/pencilkit/pkcanvasview)
- [Apple: clear Liquid Glass](https://developer.apple.com/documentation/swiftui/glass/clear)
