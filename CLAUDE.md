# CLAUDE.md — Sugrob

Project memory for Claude Code. Read this fully before any work. Keep it up to date:
when an architectural decision changes or a non-obvious gotcha is discovered, update
the relevant section in the same commit.

## What this is

**Sugrob** (Russian "сугроб" — snowdrift) is a tiny open-source macOS menu bar app that
makes it snow on the desktop. Flakes fall over everything, settle on the **top edges of
windows** and on the **top of the Dock**, and the settled snow has physics:

- resize a window → snow beyond the new width falls off;
- move a window → snow does not ride along: it falls off, carrying the window's momentum
  (a fast jerk flings it);
- brush the snow with the cursor → it breaks into particles and falls;
- push snow off the Dock with the cursor;
- snow knocked off one window can land on another window below it and pile up there.

It is pure ambience. It must never get in the way of real work.

## Non-negotiable constraints

1. **Zero network.** No API calls, no telemetry, no update checks, no analytics. No
   network entitlement, no `URLSession`. If you think something needs the network, ask.
2. **Zero permission prompts by default.** No Screen Recording, no Accessibility, no
   Input Monitoring. Everything in the default mode works without any TCC prompt.
   - Window geometry: `CGWindowListCopyWindowInfo` and only these keys:
     `kCGWindowNumber`, `kCGWindowBounds`, `kCGWindowLayer`, `kCGWindowOwnerPID`,
     `kCGWindowAlpha`. **Never read `kCGWindowName`**, because that is what triggers the
     Screen Recording requirement.
   - Cursor: poll `NSEvent.mouseLocation` and `NSEvent.pressedMouseButtons` each tick.
     No global event monitors, no event taps.
   - Accessibility may only ever be an **opt-in** "Precise Dock detection" setting, off by
     default, requested only when the user flips that toggle.
3. **Click-through, always.** Overlay windows have `ignoresMouseEvents = true`. The app
   must never steal focus, intercept clicks, appear in Cmd-Tab, or show a Dock icon
   (`LSUIElement = YES`).
4. **Cheap.** Performance budget (Apple Silicon, medium intensity, one ~1500×960 pt Retina display):
   - CPU of the app process ≤ 3% average while idle-snowing (target; macOS's own floor for a
     30 fps full-screen present is ~3%, so if we exceed it the idle rate drops to 20 fps),
     ≤ 8% during interaction;
   - simulation + window polling ≤ 1.5 ms per tick on the main thread;
   - memory (physical footprint, as in Activity Monitor): ≤ 40 MB of our own memory
     **excluding** GPU memory we cannot avoid (a fixed ~49 MB Metal driver cost plus two
     drawables per screen, ~22 MB each on a Retina laptop screen). In practice ≤ 140 MB total
     on one Retina display, ~+45–70 MB per extra display. No growth over 1 hour (no leaks,
     bounded particle pools);
   - no GPU work at all while paused.
   (Revised after Phase 1 measurements; see "Known gotchas" → Metal memory / CPU floor.)
5. **No private APIs** (no `CGS*`/`SLS*` symbols, no `dlsym` tricks). Public frameworks only.
6. **No third-party dependencies** unless explicitly approved. Swift stdlib, AppKit,
   SwiftUI (settings only), Metal, MetalKit, QuartzCore, ServiceManagement, IOKit (power).

## Tech stack

- Swift 5.10+ / Swift 6 toolchain, **Swift Package Manager** (no `.xcodeproj` in git).
- Minimum macOS **14.0**. Universal binary (arm64 + x86_64) for releases.
- AppKit app lifecycle (`NSApplication` + `NSStatusItem`); SwiftUI only for the Settings window.
- Rendering: **Metal** via `MTKView` with instanced quads. Shaders are kept as a Swift
  string and compiled at runtime with `device.makeLibrary(source:options:)`, so plain
  `swift build` works without Xcode's offline Metal compiler.
- Simulation: CPU, plain Swift with `SIMD2<Float>`, struct-of-arrays, fixed-capacity pools.
- `.app` bundle is assembled by `scripts/bundle.sh` (Info.plist + binary + icon, ad-hoc
  `codesign --sign -`).

## Repository layout

```
Package.swift
Sources/
  SnowCore/          # pure simulation, NO AppKit/Metal imports; fully unit-testable
    Flakes.swift         falling flakes pool
    Debris.swift         detached snow particles pool (knocked-off snow)
    SnowCap.swift        heightmap of settled snow on one surface
    Surface.swift        surface = horizontal segment(s) that can hold snow
    World.swift          owns everything, step(dt, inputs) -> render data
    Interactions.swift   resize / fling / brush / disappear rules
    RNG.swift            seedable deterministic RNG (SplitMix64)
    Config.swift         all tunables in one place
  Sugrob/            # the app
    App/                 main.swift, AppDelegate, StatusItem menu
    Platform/            WindowTracker, DockLocator, ScreenManager, PowerMonitor, CoordinateSpace
    Render/              OverlayWindow, SnowRenderer (MTKView delegate), Shaders.swift
    Settings/            SettingsStore (UserDefaults), SettingsView (SwiftUI)
Tests/
  SnowCoreTests/
scripts/
  bundle.sh          # builds Sugrob.app into build/
  make_dmg.sh        # optional
Resources/
  Info.plist, AppIcon.icns
.github/workflows/   # ci.yml (build+test on PR), release.yml (on tag v*)
Makefile
README.md, README.ru.md, LICENSE (MIT), CHANGELOG.md
```

## Commands

```
make build      # swift build -c debug
make test       # swift test
make run        # build debug .app and open it (kills previous instance first)
make app        # release universal .app in build/Sugrob.app
make dmg        # zip/dmg for GitHub Releases
make clean
```

Debug flags (launch args, also via `make run ARGS="..."`):
- `--debug-surfaces` draws detected surfaces, dock frame and occlusion clipping;
- `--hud` shows fps, flake/debris counts, ms per tick, window-poll ms;
- `--instant-snow` pre-fills all caps (for demos and screenshots);
- `--seed N` makes the RNG deterministic;
- `--fps N` fixes the render rate (idle and active) to compare smoothness against CPU;
- `--precise-dock` turns on the opt-in Accessibility Dock measurement for this run;
- `--settings` opens the Settings window at launch.

## Architecture

### Overlay
- One borderless, transparent `OverlayWindow` per `NSScreen`, frame = full screen frame.
- `level = CGWindowLevelForKey(.dockWindow) + 1` (above the Dock so snow can sit on it,
  below menus and pop-ups, so context menus cover the flakes).
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`,
  `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `ignoresMouseEvents = true`.
- Rebuild overlays on `NSApplication.didChangeScreenParametersNotification`.

### Tick loop
- A single display-linked tick (`CADisplayLink` from `NSView`/`NSScreen` on macOS 14+, or
  `MTKView` `preferredFramesPerSecond`) drives: poll inputs → `World.step` → render.
- **Adaptive rates:**
  - render at 60 fps while something is moving fast (debris present, mouse button down,
    a window moving); otherwise 30 fps (60 fps idle measured at ~6% CPU, 30 fps at ~3%);
  - window-list polling at 30 Hz while the mouse button is down or a window changed in the
    last 0.5 s; otherwise 8 Hz. Positions are **not** interpolated or extrapolated between
    polls: snow doesn't ride along with windows, and extrapolation invented movement that
    shed snow off windows that had barely moved.
  - simulate with `targetTimestamp` deltas (presentation time), not callback time.
- **Pause completely** (stop display link, zero GPU) when: the screen is locked or asleep,
  the screensaver is running, the frontmost app is fullscreen on that display, the user
  toggles off, or "Pause on battery" is enabled and we are on battery (IOKit power source).
  Fullscreen pauses **only that display's overlay**; other displays keep snowing.

### Coordinate spaces (classic bug source)
- `CGWindowListCopyWindowInfo` bounds use a **top-left origin** in global display space
  (primary display's top-left = 0,0, y grows down).
- AppKit/`NSScreen` uses a **bottom-left origin** (y grows up).
- `SnowCore` works in **AppKit global points, y up**. All conversions go through
  `Platform/CoordinateSpace.swift`, nowhere else; the pure math it calls lives in
  `SnowCore/CoordinateMath.swift` so the multi-monitor cases are unit-tested. Convert with the **primary** screen
  height (`NSScreen.screens[0].frame.maxY`), not `NSScreen.main`.
- The renderer converts global points to each overlay's local space. Metal drawable is in
  pixels (`backingScaleFactor`).

### Window tracking (`WindowTracker`)
- `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)`
  returns windows **front to back**. Keep only: `layer == 0`, `alpha > 0.01`,
  `ownerPID != own pid`, width ≥ 80 and height ≥ 40.
- The call runs on a **background serial queue** (it is an IPC round trip to the WindowServer);
  results are applied on the main actor between ticks. At most one poll in flight.
- Ignore layer-0 windows owned by the Dock and `com.apple.WindowManager` (Stage Manager
  thumbnails are not real windows). Identified by PID via `NSRunningApplication`.
- **Mission Control / App Exposé:** detected when Dock-owned windows on layers 18/20 are on
  screen. While it shows, window frames are reported *scaled down*, so polls are not ingested
  and snow pauses (overlays hidden); a 0.25 s watch poll notices the end, and snow resumes
  0.6 s later once windows have animated home. Without this, every window looks like it
  jumped and all snow would shed.
- Identify windows by `kCGWindowNumber`. Each tick produce `TrackedWindow { id, frame, zIndex,
  velocity, sizeDelta, appeared, disappeared }`. Velocity = smoothed position delta / dt.
- A window's **snow surface** is its top edge, inset by the macOS corner radius
  (`Config.windowCornerRadius`, ~12 pt; caps droop at the rounded corners).
- **Occlusion:** a window's top edge is only "visible" where no window in front of it
  covers it. Compute visible x-intervals per surface each poll. Snow on hidden intervals is
  kept but not rendered and doesn't receive new flakes. If a front window moves over a cap,
  it simply hides it, the same way it does in the reference video.

### Dock (`DockLocator`)
- Default (no permissions): derive the Dock height and edge from `screen.frame` vs
  `screen.visibleFrame`. Width estimate: read `com.apple.dock` defaults (`tilesize`,
  `persistent-apps`, `persistent-others`, `show-recents`, `orientation`, `autohide`) via
  `UserDefaults(suiteName:)`, plus the count of running regular apps, which gives the pill
  width. Recompute on app launch/terminate notifications and on screen-parameter changes.
  Pure math in `SnowCore/DockLayout.swift`; constants in `Config` calibrated against AX on
  macOS 26 (68 pt slot per tile at tilesize 64, separator 0.478 × tilesize, 7.7 pt end
  padding, height tilesize + 20, Dock top 3 pt below `visibleFrame.minY`, centred on screen).
  Also refreshed every 5 s to catch preference changes that post no notification.
- Opt-in precise mode (`--precise-dock` until the Settings window exists): AX query of the
  Dock's list element. Only its **x and width** are used; on macOS 26 AX reports the Dock's y
  at the very bottom of the screen (off-screen), so y always comes from `visibleFrame`.
- The Dock is a cap with id `World.dockCapID`, frontmost: it hides window caps behind it and
  is drawn in front of them. `--debug-surfaces` outlines it in yellow; `--hud` /
  `--debug-surfaces` log each new estimate to stderr as `[dock] …`.
- v1 supports the **bottom** Dock only. Left/right or autohide → no Dock surface; existing
  Dock snow falls off as debris when the Dock hides.

### Simulation (`SnowCore`)
- **Flakes:** fixed pool. Spawn above the top of each screen; fall at 25–60 pt/s with a
  sinusoidal sway and a global gentle wind. On hitting a visible surface interval they're
  absorbed into that `SnowCap` column. Off-screen ones are recycled.
- **SnowCap:** heightmap, one column per 2 pt of surface width, `Float` heights,
  `maxHeight` ≈ 10–14 pt (config). Each step:
  - relaxation, so neighbor slope never exceeds the angle of repose and excess moves sideways;
    a cap whose relaxation moved nothing is *settled* and skipped until its heights change;
  - fresh snow lands in an `incoming` buffer and eases in (~0.2 s), so caps grow smoothly;
  - snow past a cap end slides over the rounded corner and **melts silently** (a constant
    drizzle of particles looked busy and kept the frame rate at 60 fps);
  - the cap is anchored to its window, but a moving window sheds its snow (see Interactions).
- **Debris:** knocked-off snow. Fixed pool, gravity ~1200 pt/s², light drag, short life.
  Debris that lands on another visible, resting surface is absorbed there, which is how snow
  transfers from window to window; it never lands on the cap it came from. Rendered as small particles stretched along velocity
  (motion streaks).
- **Interactions** (`Interactions.swift`):
  - *Resize:* columns that fall outside the new width turn into debris with a small outward
    kick. Heights are preserved for columns that remain (re-anchored by left edge or right
    edge depending on which side moved).
  - *Move (incl. fling):* snow never rides along. Each step, the rigid part of the window's
    displacement (both edges moving the same way, so a one-sided resize is not a move) sheds
    `(d - shedDeadZone) / shedDistance` of the cap (dead zone 0.3 pt, full at 6 pt), inheriting
    75% of the window velocity plus jitter. A drag empties the cap within a frame or two; a
    fast jerk flings the snow. A window collects no snow until it has rested `settleDelay`.
    (Decided by the user after Phase 2: "snow should fall off, not move with the window".
    This replaces the earlier "slow drags keep the snow" rule.)
  - *Brush:* cursor segment between the previous and current positions, radius ~10 pt. Columns
    under it are converted to debris with cursor velocity plus upward kick. Works with or
    without the mouse button down. Same for the Dock surface.
  - *Disappear:* window closed/minimized/moved to another Space → its whole cap becomes debris
    (capped count; excess mass is just dropped).
- Accumulation is slow (minutes to a nice cap). `--instant-snow` skips the wait.

### Rendering (`SnowRenderer`)
- One render pass per overlay, premultiplied alpha blending, cleared to transparent.
- Flakes and debris: instanced quads, soft round sprite computed in the fragment shader
  (no textures). Debris quads are stretched along velocity.
- Caps: triangle strip from the heightmap. Fill white, very light cool shading toward the
  bottom (≈ #E8EEF8), a 1 px brighter top highlight, slight value-noise lumpiness on the
  contour. Clip to the visible intervals.
- Upload per-frame data to a triple-buffered `MTLBuffer` ring. No allocations per frame.

### Settings (menu bar)
Menu: Snow on/off · Intensity (Light / Medium / Blizzard) · Snow on windows ✓ ·
Snow on Dock ✓ · Clear all snow · Settings… · Quit.
Settings window: intensity, max drift height (6–20 pt), wind (0–2×), frame rate, pause on
battery, launch at login (`SMAppService.mainApp`, not stored: the system is the source of
truth), opt-in precise Dock detection. Stored in `UserDefaults` (`SettingsStore`,
`@Observable`) and applied live via `SnowEngine.apply`.
Frame rate is a mode rather than a cap: *Balanced* (30 idle / 60 active, default),
*Smooth* (always 60, ~2× CPU), *Efficient* (never above 30).
The Settings window is torn down on close so SwiftUI's memory (~15 MB) is returned.

## Conventions

- Code, comments, commit messages, README: **English**. `README.ru.md` mirrors README.
- Swift API Design Guidelines; `final class` by default; no force unwraps outside tests;
  `@MainActor` on everything touching AppKit.
- All magic numbers live in `SnowCore/Config.swift` with a comment explaining the unit.
- `SnowCore` must not import AppKit, Metal, or Foundation types beyond basics, so it stays
  testable with deterministic seeds.
- Conventional Commits (`feat:`, `fix:`, `perf:`, `docs:`, `chore:`). Small commits, one
  logical change each.

## Definition of done (per change)

1. `make build` and `make test` pass with zero warnings.
2. New simulation logic has unit tests in `SnowCoreTests` (deterministic seed).
3. Performance-sensitive changes: run `make run ARGS="--hud"` and note the ms/tick in the PR/commit body.
   Phase reports also include WindowServer's CPU delta (with vs. without Sugrob), because the
   compositing cost of a full-screen transparent overlay lands there, not in our process.
4. Anything visual: describe exactly what the user should check manually, because you
   cannot see the screen. Ask the user to confirm before moving on to the next phase.
5. Update this file if architecture/gotchas changed; update CHANGELOG.md.

## Known gotchas

- Without a Developer ID, downloaded builds are quarantined by Gatekeeper. README must
  explain: right-click → Open, or `xattr -dr com.apple.quarantine /Applications/Sugrob.app`.
  Release CI notarizes **only if** signing secrets are present; otherwise ships ad-hoc signed.
- `CGWindowListCopyWindowInfo` costs ~0.5–3 ms depending on window count. Never call it
  more often than the adaptive rate allows, and never from the render thread.
- Stage Manager, Mission Control and Space switches make windows jump or vanish for a
  few frames. Debounce disappear (window missing for ≥ 3 consecutive polls) before
  converting caps to debris, otherwise all snow drops on every Space switch.
- Fullscreen detection: a layer-0 window whose bounds equal its screen's frame.
- Our own overlay windows appear in the window list. Filter by own PID.
- On macOS 26 (Tahoe), window corner radii are larger than on 14/15. Keep
  `windowCornerRadius` per-OS in Config.
- Command Line Tools (no Xcode) ship **Swift Testing** but **not XCTest**. Tests use
  `import Testing` (`@Test`, `#expect`). `make build`/`make test` pass `-warnings-as-errors`.
- With CLT, `swift build --arch arm64 --arch x86_64` (multi-arch) needs Xcode's build system.
  `scripts/bundle.sh release --universal` builds each arch separately and merges with `lipo`.
- Swift 6: a closure created inside `@MainActor` code inherits main-actor isolation. Metal
  completion handlers run on a Metal queue → runtime trap (`dispatch_assert_queue`). Mark them
  `@Sendable` and touch only Sendable state (e.g. a `DispatchSemaphore`).
- Metal memory (M4, macOS 26): the first command buffer that renders to a drawable adds a fixed
  ~49 MB of driver-owned "unmapped (graphics)" footprint, independent of drawable size. Each
  full-screen Retina drawable is ~22 MB (1470×956 pt @2x × 4 B); we cap `maximumDrawableCount`
  at 2. Measure with `footprint -p <pid>`.
- CPU floor: a bare 30 fps clear+present of a full-screen `CAMetalLayer` already costs ~3% of
  the process on M4/macOS 26. On a 60 Hz panel the display link only honours divisors of 60
  (asking for 24 fps yields 30).
- `--hud` also writes a line to stderr every 5 s; run the binary directly
  (`build/Sugrob.app/Contents/MacOS/Sugrob --hud 2>hud.log`) to collect numbers without seeing the screen.
- Pause can be smoke-tested by posting `com.apple.screensaver.didstart`/`didstop` as
  distributed notifications from a tiny Swift script.
- `CGWindowListCopyWindowInfo` wall time is ~0.2 ms warm but 1–4 ms when called at 8 Hz
  (cold caches, IPC wait). That is waiting, not our CPU, which is why polling is off-main.
- Debug builds are ~10× slower in the simulation (tick ≈ 0.9 ms vs 0.05 ms release). Quote
  release numbers in reports.
- Maximized windows have their top edge right under the menu bar; their caps are drawn there
  but the menu bar (level 24 > overlay 21) covers them. That is expected.
- The Dock process's windows in `CGWindowList` (layer 20 and two negative layers) all cover
  the whole screen, so they cannot be used to find the Dock pill.
- Ad-hoc signed builds get a new code signature on every rebuild, so an Accessibility grant
  for `--precise-dock` may have to be re-approved after rebuilding.
- While overlays are ordered out (paused), macOS releases their drawables: footprint drops
  from ~120 MB to ~70 MB.
- `--hud` logs `[pause] …` / `[resume] frames presented while paused: N`; N must be 0.
- `NSRunningApplication.runningApplications(withBundleIdentifier:)` and even
  `.processIdentifier` are **synchronous LaunchServices XPC calls** (~0.1–0.5 ms each). Never
  call them per tick or per poll; `SystemProcesses` caches the PIDs and refreshes on app
  launch/quit. (Calling them per poll raised the tick from 0.08 to 0.6 ms, max 2.5 ms.)
- `didChangeScreenParametersNotification` also fires when only a `visibleFrame` changes (Dock
  resized, menu bar auto-hidden). `ScreenManager` rebuilds overlays only when screen frames or
  scale factors actually changed.
- Profile with `sample <pid> 5 -file out.txt` (no permission needed for our own process).
