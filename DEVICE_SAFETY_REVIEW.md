# Buko: pre-device security and data-safety review

Reviewed September 10, 2026, against the current working tree, including the standard-page changes.

**Assessment:** reasonable to test on your iPad with disposable notes. No app-code behavior indicating device compromise, data exfiltration, or modification of other apps was found. This is a source/configuration review and simulator validation, not a guarantee of zero risk or a penetration test of iPadOS.

## Findings addressed

- **Concurrent windows could overwrite a note.** Each PencilKit canvas saves a complete drawing, and existing views do not merge another window's edits. The generated app manifest previously enabled multiple scenes. Added `Configuration/Info.plist` and disabled manifest autogeneration so the final built app explicitly declares `UIApplicationSupportsMultipleScenes = false`. Multi-window editing should return only with conflict handling. This risk was identified from the data flow; a two-window overwrite was not deliberately performed on user notes.
- **Failed drawing loads needed stronger write isolation.** Disabling touch input alone did not prevent potential programmatic drawing callbacks from an empty fallback canvas. `NoteCanvas` now attaches the writer, tool-session canvas, and page persistence callback only after successful decoding. Its drawing delegate also rejects callbacks before a successful load. Original drawing bytes remain untouched on failure. Build-checked and reviewed; corrupt-store fault injection is still a future integration test.

## Security scope and evidence

- Reviewed the shipping Swift files, persistence paths, project build configuration, generated simulator Info.plist, and linked app libraries. The app uses Apple frameworks; no third-party package dependencies, embedded service credentials, custom build scripts, dynamic code loading, web views, network client/server, analytics, or AI requests were found.
- No camera, microphone, photos, contacts, location, local-network, or tracking access is implemented or requested. No background execution modes, document import handlers, URL schemes, file-sharing settings, app groups, or iCloud entitlements are configured in this project.
- Notes are written through SwiftData in the app container. Preferences use AppStorage. The shipping app contains no filesystem deletion routine or permanent note deletion; Trash is a recoverable timestamp. Test-only temporary-store cleanup is outside the app target.
- Storage initialization failures preserve existing files instead of deleting/recreating the database. Save errors are shown with a retry action. Appearance changes preserve stroke geometry and save canonical monochrome ink.
- On a normally configured iPad, third-party apps run in Apple's sandbox, which restricts access to other apps and system files. This is an OS security boundary, not a promise that software has no bugs. [Apple's sandbox and entitlement documentation](https://support.apple.com/en-ae/guide/security/sec15bfe098e/web).

## Remaining risks and limits

1. **Buko is not yet a safe sole copy of important notes.** There is no export, independent backup, version history, or sync. Deleting the app, storage corruption, a future migration bug, or device loss can lose its local notes. Trash does not protect against those events. System backups depend on the user's device settings and are outside this app's backup guarantees.
2. **Recent edits can be lost on abrupt termination.** Explicit saves wait for 500 ms of inactivity, and note switching/scene deactivation flush changes. A crash during continuous writing, an in-flight stroke, or failed storage writes can lose edits since the last successful save. It is not a strict 500 ms maximum loss window.
3. **Large-note performance is not yet characterized on hardware.** Drawing serialization and snapshots have main-thread work; rapid gestures can overlap background Gaussian rendering jobs. Raster dimensions are capped, but stroke count, note count, and document length are not. Heavy usage may cause lag, battery use, memory pressure, or an app termination. No code that disables device thermal protections or performs privileged hardware operations was found.
4. **No private-note lock.** The app relies on device security and default OS file protection; it does not implement its own encryption or Face ID lock. Open notes may be visible in the app switcher. Exact on-device file protection and the final development-signed entitlements were not measured in this simulator review.

## Validation and next device step

- Final simulator build passed; its manifest was checked for single-window support and absence of sensitive permission/background keys. Installed and launched on the existing iPad Pro 13-inch (M5) simulator running iPadOS 27. A screenshot confirmed the workspace, existing note entries, and removal of the selected-note dot. Physical M4 deployment was not performed.
- Geometry, page pull rules, SwiftData reopen/Trash/restore/page metadata, and PencilKit monochrome/stroke preservation checks passed using isolated temporary data.
- Use the normal **Buko** scheme, your own development team, and the physical iPad run destination in Xcode. Minimum iPadOS is 26. Device signing and deployment are separate from the simulator build.
- Start with test notes and verify Pencil input, app background/reopen, note switching, and Trash/restore. Keep important originals elsewhere until export/backup and hardware stress testing are in place.
