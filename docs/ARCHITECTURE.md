# Architecture

Sugrob is a macOS 14+ menu bar app built with Swift 6 and Swift Package Manager.
Start with [CONTRIBUTING.md](../CONTRIBUTING.md) for build commands and contribution rules.

## Module boundaries

| Location | Responsibility |
| --- | --- |
| `Sources/SnowCore/` | Deterministic simulation, geometry, surface visibility and configuration |
| `Sources/Sugrob/App/` | App lifecycle, menu and simulation orchestration (`SnowEngine`) |
| `Sources/Sugrob/Platform/` | Window and Dock geometry, displays, session and power state |
| `Sources/Sugrob/Render/` | Click-through overlays, Metal renderer, shaders and diagnostic HUD |
| `Sources/Sugrob/Settings/` | Persisted preferences and SwiftUI settings |
| `Tests/SnowCoreTests/` | Swift Testing tests, with fixed seeds for random behavior |
| `Resources/` | Bundle metadata, app icon and snowplow artwork |
| `scripts/` | App bundling, signing, release archives and icon generation |

Keep SnowCore free of AppKit and Metal. Put tunable simulation constants in `Config.swift`
and document their units. AppKit-facing code belongs on `@MainActor`.

## Privacy and input

The application uses public APIs, with no network calls, telemetry or third-party dependencies.
Window tracking reads geometry with `CGWindowListCopyWindowInfo`; never read window titles
(`kCGWindowName`) or screen contents. Poll the cursor through `NSEvent`; do not add global
input monitors or event taps. Overlays always have `ignoresMouseEvents = true`.

Default behavior needs no privacy permission prompts. Precise Dock detection is opt-in:
only explicitly enabling it in Settings may request Accessibility access. Restoring a
saved preference or passing a launch flag must not prompt; without trust, use the estimate.

## Coordinates and surfaces

SnowCore uses **global AppKit points, with y increasing upward**. Core Graphics window
bounds use a top-left origin with y increasing downward. Convert through
`Platform/CoordinateSpace.swift` and the tested math in `SnowCore/CoordinateMath.swift`.
Use the primary display's top edge as the conversion reference, never `NSScreen.main`,
which can change with focus. The renderer converts global points into overlay-local space;
Metal drawable dimensions are pixels, scaled by the display backing scale.

Window lists arrive front to back. Filter out the app's own windows and system UI surfaces;
compute visible intervals so front windows hide covered parts of a snow cap. Poll window
geometry off the main thread, with at most one request in flight. Cache system-process IDs
rather than making LaunchServices calls each frame.

The Dock estimate combines the screen's visible frame and Dock preferences. Only a bottom,
visible Dock collects snow. Optional Accessibility measurements refine its horizontal extent;
vertical placement still comes from screen geometry. Bottom snow can instead use the screen
edge, where the optional snowplow clears accumulated snow.

## Simulation and rendering

`World` owns falling flakes, settled heightmap caps and detached debris. Particle pools are
bounded. Snow accumulates on visible surfaces, relaxes into slopes and detaches when windows
move or narrow or the cursor brushes it. Detached snow can land on resting surfaces again.
The screen-edge snowplow maintains a bounded blade load and discharges snow as it clears.

Each display has a transparent overlay above the Dock. Metal draws particles and caps;
shaders compile at runtime, so an offline Metal compiler is not required. The snowplow
texture is `Resources/SnowplowVariant2.png`, copied into the app by `scripts/bundle.sh`.
GPU completion handlers must be `@Sendable` and must not access main-actor state.

Balanced mode renders at 30 fps idle and 60 fps during interaction. Window polling adapts
separately. Smooth mode stays at 60 fps; Efficient caps rendering at 30 fps. Avoid per-frame
allocations and unnecessary relaxation of settled caps. GPU drawable memory grows with
screen size and display count, so report the display setup with performance measurements.

## Transitions and pauses

Lock, sleep, screensaver, Mission Control and optional battery handling pause snow. A paused
overlay must submit no GPU work. **Fullscreen is different:** falling flakes continue, while
snow on fullscreen windows and their Dock is suppressed.

Space changes can produce stale or transitional window geometry. Discard old-Space polls,
wait for geometry to settle and rebase caps without treating the transition as a window drag.
Missing windows are hidden immediately; lifecycle handling decides when to remove their snow.
Do not infer real movement from Mission Control's scaled window frames.

Rebuild overlays only when display frames or scale factors change. A visible-frame change
alone (for example, resizing the Dock) must not reset the simulation. Avoid waiting on a Metal
drawable from an occluded overlay; redraw when it becomes visible again.

## Build and diagnosis

`make build` and `make test` treat warnings as errors. `make run` assembles and launches a
native debug app. `make app` builds each release architecture separately and combines them
with `lipo`; it does not use SwiftPM's Xcode-only multi-architecture build invocation.
`make dmg` creates the app, ZIP, DMG and SHA-256 checksums in `build/`.

Use `make run ARGS="--hud --debug-surfaces"` to inspect timing and surface geometry.
`--instant-snow --seed 42` is useful for repeatable manual checks. For performance comparisons,
use a release build and capture its diagnostic output directly:

```sh
make app
build/Sugrob.app/Contents/MacOS/Sugrob --hud 2> sugrob-hud.log
```

Debug timing is not representative of release performance. Check frame pacing, process CPU,
WindowServer overhead and memory on the same hardware and display configuration. Verify
that lock/unlock, Mission Control, fullscreen, Space switching and display changes recover
without a burst of detached snow or stalled rendering.

## Packaging

The app is ad-hoc signed by default. Release automation can use Developer ID signing and
notarization when the secrets documented in CONTRIBUTING are configured. The bundle includes
the MIT license. Version comes from `VERSION` or the latest `v*` tag; the build number comes
from the commit count. Tagging a version triggers publication, so push release tags only after
validation. The Homebrew cask in `packaging/` is a template; set its version and checksum before
publishing it in a tap.
