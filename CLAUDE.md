# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Showt** is an iOS app (Swift 5.0, iOS 18.2+, iPhone & iPad) that turns the phone into a persistence-of-vision (POV) sign. The user types a word or phrase, then waves the phone side-to-side — the motion-synced multi-slit barrier rendering makes the text appear to float in the air.

## Build & Test

This is a pure Xcode project (no Package.swift, no npm). All build/run/test operations go through Xcode or `xcodebuild`.

```bash
# Build for simulator
xcodebuild -project Showt.xcodeproj -scheme Showt -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run unit tests
xcodebuild -project Showt.xcodeproj -scheme Showt -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single test (Swift Testing framework)
xcodebuild -project Showt.xcodeproj -scheme Showt -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:ShowtTests/ShowtTests/<TestName>
```

For normal development, open `Showt.xcodeproj` in Xcode and use Cmd+B / Cmd+U.

## Architecture

The app has four Swift source files and no external dependencies:

### View Layer (SwiftUI)
- **`ShowtApp.swift`** — App entry point. `AppDelegate` locks orientation to portrait.
- **`ContentView.swift`** — Root view. Owns `showDisplayView: Bool` and `displayText: String` state, toggling between the two screens.
- **`InputView.swift`** — Text entry screen. Enforces 24-char uppercase limit. On "Create Showt", updates `displayText` and flips `showDisplayView = true`.
- **`DisplayView.swift`** — The POV rendering screen. Owns all display logic: text segmentation, image generation, Canvas drawing, and recording UI.

### Motion Layer
- **`MotionManager.swift`** — `ObservableObject` using `CoreMotion`. Publishes `tiltPosition`, `tiltVelocity`, `motionSpeed`, and `sweepPhase` at 60 Hz. Includes simulator mock motion and a CSV recording/export feature for tuning.

### Key Rendering Concepts in DisplayView

**Multi-slit barrier**: 40 vertical slits (`slitWidth ≈ 2.6pt`) drawn via SwiftUI `Canvas`. Only pixels behind slits are visible, creating the strobing POV effect.

**Text segmentation**: Long text is split into ≤6-character chunks (`splitTextForSweep`). The active chunk advances each time `sweepPhase` hits an edge (0.02 or 0.98), cycling through segments on each sweep.

**Speed-adaptive lookahead**: `predictedTilt` compensates for motion latency by adding `tiltVelocity * lookaheadFrames` (1–4 frames) so the displayed column leads the phone position.

**Arc correction**: Two arc offsets are applied — a global sweep arc (`sweepArcMaxDrop = 80pt`) based on normalized tilt, plus a per-column letter arc (`letterArcMaxDrop = 28pt`) to bow the text baseline into a readable arch.

**Text image generation**: `generateTextImage(for:)` renders the current segment to a `UIImage` via `UIGraphicsImageRenderer` using `UIFont.systemFont(.black)` at a large font size (700–920pt depending on text length). Font size and kern are tuned per character count.

**Strobe mode**: Togglable via the SOLID/STROBE button. Pulses opacity at ~56 Hz when active.

**Screen brightness**: Set to maximum (`UIScreen.main.brightness = 1.0`) on appear, restored on disappear.

### Data Flow

```
CMMotionManager (60Hz) → MotionManager (filters, publishes) → DisplayView (Canvas redraws per frame)
ContentView ($showDisplayView, $displayText) → InputView ↔ DisplayView
```

### Testing Framework

Uses Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest. The test target is `ShowtTests`.
