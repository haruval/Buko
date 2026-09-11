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
- The canvas starts at page width. Pinching reveals four temporary page-fit corner guides; releasing hides them. Release within 28% of page-fit zoom to snap back. The guides extend into a full outline and blur away during the snap. Zoomed-out overview is read-only: tap with a finger or Pencil to return to writing, centered on that area. The default is a portrait 13-inch iPad Pro–proportioned (4:3) page, fitted to the screen width. It fills the portrait display; landscape retains the tall page and scrolls vertically. Page edges and zoom guides are rounded, with a reference radius tuned for the iPad Pro; UIKit does not publicly expose the physical screen radius. Existing pages form one continuous scroll range. Below the final sheet, a clear-glass **Scroll to create page** pill releases a glass dot as you pull. Crossing the detent commits one new page immediately; the dot expands into that sheet. A footer keeps this interaction above the tool shelf. Pulls at internal page boundaries never create or turn pages.
- Use the left glass sidebar to create or switch notes. Long-press a note to rename it or move it to Trash.
- Hide the sidebar with its upper-right button; the floating sidebar button grows back into the library.
- The bottom glass shelf provides a pen, stroke eraser, undo, and redo. Hold the pencil button to enable finger drawing.
- Settings contains **Grid lines** and **Enable infinite canvas (experimental)** switches, remembered between launches. Infinite mode restores the wider workspace and automatic downward growth. Switching modes preserves ink and blank pages.
- Pulling beyond the notebook reveals pure black outside the paper with a broad Gaussian feather and progressively blurred copies of the ink and grid. Zooming out from fit has a small resistance detent. A dark edge blur appears while departing fit and disappears in overview; overview pages always have sharp rounded edges. Blur images are cached per gesture and filtered off the main thread. Releasing below the minimum zoom uses native rubber-banding.
- The top-right settings button expands into a glass panel. Open **Trash** to restore deleted notes, including their drawings. Notes stay in Trash until restored; there is no automatic purge.
- The light canvas is `#F2F0EF`; the dark canvas is `#33343B`. Ink is uniformly black in light mode and white in dark mode, including previously saved strokes. Native clear glass is untinted in both appearances. Apple controls refraction strength; the public API has no intensity setting.
- Notes, page counts/current pages, and PencilKit strokes save locally with SwiftData. Writes are debounced, with explicit saves on note switching and scene deactivation. Storage errors are surfaced without replacing saved files.

## Source layout

- `Buko/ContentView.swift` — workspace composition, selection, and save lifecycle.
- `Buko/Models/Note.swift` — persisted note metadata and drawing data.
- `Buko/Canvas/` — PencilKit bridge, explicit monochrome ink presentation, overview camera, grid/backdrop, page navigation, progressive Gaussian content blur, snap guides, and transient tool state.
- `Buko/Views/` — expanding glass panels, notes library, settings/Trash, and tool shelf.

## Scope

This is the initial canvas scaffold. AI gestures, bulletin extraction, generated handwriting, voice collaboration, synchronization, and export are not implemented. Pages use stable 1,000-point-wide coordinates with portrait iPad Pro proportions. Experimental mode has a finite 3,000-point width and grows downward in chunks. The selected page persists; within-page viewport position and undo history are transient. The first implementation uses fixed ink width and a stroke eraser.

## Checks

Run the geometry, paging, real SwiftData storage, and PencilKit ink checks on macOS:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Tests/run-checks.sh
```

These check portrait iPad Pro page proportions, pull thresholds and cancellation, last-page-only creation and title collision handling, legacy drawing bounds, blank-page persistence, page-fit projection, snap thresholds, scroll/rotation math, soft deletion, active/trash filtering, restore after reopening the store, preservation of drawing bytes, legacy ink normalization, and preservation of stroke geometry through appearance changes and serialization. Databases are temporary and separate from the app's notes.

The **BukoValidation** scheme adds a simulator UI test for pull-to-create, continuous navigation, relaunch persistence, the experimental switch, landscape scrolling, and rounded overview presentation. Run it on a separate test simulator; it creates a local note.

The local, gitignored `AGENTS.md` holds the detailed product vision, engineering plan, and device validation checklist.

## Before physical-device testing

See [the device-safety review](DEVICE_SAFETY_REVIEW.md) for checked security boundaries, data-safety fixes, and remaining limitations. Use test notes until export/backup is implemented. Buko currently supports one window to prevent concurrent canvases overwriting the same note.

## Native API references

- [Apple: PencilKit canvas](https://developer.apple.com/documentation/pencilkit/pkcanvasview)
- [Apple: clear Liquid Glass](https://developer.apple.com/documentation/swiftui/glass/clear)

The collapsed library button has a clear-glass current-title pill beside it. New notes select immediately, duplicate titles receive numbered suffixes, and the library orders notes by last edit. Scrolling between existing pages does not change their edit date. Existing duplicate titles are disambiguated on launch without changing ink or edit timestamps.

UI tests use a DEBUG-only central accessibility target (`--canvasGestureTestArea`) to keep XCTest’s corner-to-corner pinch away from floating controls. This target only chooses gesture coordinates; zoom still runs through PencilKit. Rename validation uses the alert’s Return-key action to avoid stale iPad simulator keyboard frames.
