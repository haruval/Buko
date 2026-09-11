# Circle intent prototype

Select the small glass circle to draw a loop with one finger (click and drag in
Simulator). With Pen or Eraser selected, use two fingers moving together around
the region. A changing finger spread yields to pinch; a straight translation
yields to scrolling. Overview remains read-only. Switch back to Pen to scroll
normally while using the simulator.

The TEST — PPL notebook is created once and selected. Settings (•••) → Development
→ Recreate PPL TEST note makes two fresh pages and moves the prior generated note
to Trash. Reset tracks a UUID, never the title, and does not overwrite unrelated
notes. Titles may gain a numeric suffix because Trash reserves existing names.
The fixture is synthetic hand-lettering encoded as real editable PencilKit
strokes, not a background image or a recognition answer key.

## Pipeline and tuning

- `Buko/AI/CircleGestureRecognizer.swift`: two-finger arbitration, or the one-finger
  toolbar mode. Loop closure/area thresholds are in `CircleGeometry.swift`.
- `CircleInkReader.swift`: works on an immutable drawing snapshot on its own actor.
  Samples visible stroke paths inside the polygon and recognizes the selected
  stable IDs with iPadOS 27 `PKStrokeRecognizer`. Nearby page-local handwriting
  provides context. Recognizer search supplies word bounds for the glass outline.
  If stroke recognition returns empty, accurate Vision OCR reads a bounded,
  canonical-black-on-white rendering of only the selected strokes. The popup
  identifies the reader. Vision's `OCRTool` was evaluated, but its opaque text
  output provides no word geometry, so the fallback calls Vision directly.
- **`IntentPrompts.swift`** contains the editable **system instructions**, example
  intents, input limits, and the `@Generable` response schema. Edit and rebuild to
  tune it. `PPLTestNote.swift` independently authors the fixture.
- `CircleIntentState.swift` creates a fresh `LanguageModelSession` using
  `SystemLanguageModel.default`, greedy sampling, and a 320-token response limit.
  The model describes the intended action, supporting evidence, and any needed
  clarification. It does not complete or modify the note. Notebook input is
  delimited JSON data, with instructions to treat it as data rather than commands.
- `CircleIntentOverlay.swift` renders native clear Liquid Glass using the sampled
  polygon, then recognized word/line envelopes. Spring deformation and a pulsing
  highlight respect Reduce Motion. The popup uses regular native glass to keep
  diagnostic text legible over ink. The temporary popup includes recognized text,
  the model's guess, evidence, and elapsed time.

All recognition/inference is local. There are no API keys, servers, or cloud
fallbacks. Apple Intelligence and model availability are checked at runtime;
unavailable models, empty regions, recognition errors, and timeout are explicit.
A 45-second watchdog bounds the visible wait. A request token rejects late output.
New circles, edits, tool changes, navigation, note replacement, backgrounding,
resizing and camera transitions cancel the old request. Ordinary scrolling
clears the overlay rather than leaving it attached to a different region.

## Validation and limits

- Actual simulator touch loop on the PPL comparison produced the recognized text
  “lexical analysis vs parsing:” and the Foundation Models guess “The user wants
  to fill in the difference between lexical analysis and parsing.” This used
  PencilKit recognition and the on-device model, about 4 seconds in that run.
- An isolated macOS 27 executable exercised the real Vision fallback and model:
  “The user wants to fill in the comparison between lexical analysis and parsing.”
  The command-line PencilKit recognizer returned empty there; the iPad simulator
  successfully used PencilKit. No fixture text was substituted for recognition.
- Focused UI validation covers reset, tool selection, non-loop cancellation with
  no new ink, outside dismissal, native pinch/overview, and relaunch persistence.
- Geometry checks cover clockwise/counterclockwise loops, open/tiny/straight
  rejection, concave selection and document coordinates. Existing ink and real
  SwiftData migration/rollback/Trash checks also pass.

The generated fixture is a development aid, not a handwriting accuracy benchmark.
The one-finger simulator loop is tested; physical two-finger arbitration and
Pencil/palm interaction still require the M4 iPad. Very flat initial arcs can
look like pans; finger separation changes can look like pinches. Tune with real
traces before treating gesture recognition as stable. Test ambiguous, complete,
multiline and non-English handwriting beyond this English PPL fixture. The
prototype guesses intent; it does not claim certainty or perform spatial edits.

## Deferred adapters

Evaluate custom adapter training after collecting an intent evaluation set and
establishing a prompt-only baseline. Apple's linked toolkit currently states
that 26.0.0 is its final release and is not compatible with OS 27 or later.
Recheck Apple's supported customization route before implementation. Do not
bundle an iOS 26 adapter into this iOS 27 pipeline.

Sources checked September 11, 2026:
- https://developer.apple.com/documentation/pencilkit/pkstrokerecognizer
- https://developer.apple.com/videos/play/wwdc2026/203/
- https://developer.apple.com/documentation/Vision/OCRTool
- https://developer.apple.com/apple-intelligence/foundation-models-adapter/
