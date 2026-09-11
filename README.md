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
- The canvas starts at page width. Zoom out to reveal a wider drawing workspace; scrolling toward the bottom adds room automatically.
- Use the left glass sidebar to create or switch notes. Long-press a note to rename it.
- Hide the sidebar with its upper-right button; the floating sidebar button brings it back.
- The bottom glass shelf provides a pen, stroke eraser, undo, and redo. Its options menu enables finger drawing for simulator testing.
- Notes and PencilKit strokes save locally with SwiftData. Writes are debounced, with explicit saves on note switching and scene deactivation. Storage errors are surfaced without replacing saved files.

## Source layout

- `Buko/ContentView.swift` — workspace composition, selection, and save lifecycle.
- `Buko/Models/Note.swift` — persisted note metadata and drawing data.
- `Buko/Canvas/` — PencilKit bridge, paper/viewport geometry, and transient tool state.
- `Buko/Views/` — native glass sidebar and tool shelf.

## Scope

This is the initial canvas scaffold. AI gestures, bulletin extraction, generated handwriting, voice collaboration, synchronization, and export are not implemented. The workspace currently has a finite 3,000-point width with a 1,000-point page guide and grows downward in chunks. Viewport position and undo history are transient; loading a note fits its page again. The first implementation uses fixed ink width and a stroke eraser.

The local, gitignored `AGENTS.md` holds the detailed product vision, engineering plan, and device validation checklist.

## Native API references

- [Apple: PencilKit canvas](https://developer.apple.com/documentation/pencilkit/pkcanvasview)
- [Apple: clear Liquid Glass](https://developer.apple.com/documentation/swiftui/glass/clear)
