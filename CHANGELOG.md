# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- Snowplows retain a bounded, mass-based blade load before discharging it and clear
  fresh snow beneath their footprint after surface settling.
- The screen-edge snowplow is half the size and can be switched off in Settings or the menu.
  Its blade removes snow from the screen-edge heightmap by directing it sideways,
  leaving a clear path without building an oversized wall.
- Switching windows or Spaces preserves their settled snow without a burst of falling particles.
- Fullscreen Space transitions no longer stall snowfall while Metal waits for a drawable from
  an occluded overlay; the overlay redraws as soon as macOS marks it visible again.
- Space changes now request a window poll immediately. After Mission Control, snowfall resumes
  as soon as window frames settle instead of always waiting 0.6 seconds.
- Slightly stronger directional throw when a window starts moving or the cursor brushes snow;
  small window movements now give detached snow a visible impulse.
- Moving a window now detaches its snow from the old edge on the first measured displacement.
  The initial mouse-down poll no longer waits for the idle interval, and detached snow follows
  the latest movement direction, including quick reversals and downward throws.
- An upward cursor flick or a fast upward window movement can now throw loose snow upward;
  its launch speed follows the motion and is capped before it falls and settles again.
- Loose snow falls more slowly and can settle back on its source window after it stops moving.
  Window movement sheds snow immediately, even during a careful drag; brushing gives snow a
  brief hop before it falls.
- Clearing or disabling the Dock now removes its snow without leaving falling particles over an absent Dock.
- Fullscreen windows lose their accumulated snow and cannot collect more while fullscreen; windows extending from the Dock to the menu bar are now detected too.
- Empty desktops resume snowfall after leaving a fullscreen Space; ordinary Dock layer-20 windows no longer trigger a false Mission Control pause.
- Falling flakes remain visible in fullscreen mode while snow on the fullscreen window and its Dock is suppressed.
- Dock snow now tracks centred width changes as apps appear, disappear, or become recent; snow beyond either new edge falls off.

### Added
- Bottom snow can settle on the Dock or the screen edge. A miniature toy snowplow drives in
  from the right and clears the screen edge when its snow gets deep.
- Project skeleton: SwiftPM package (`SnowCore`, `Sugrob`, `SnowCoreTests`), Makefile,
  `scripts/bundle.sh` that assembles an ad-hoc signed `build/Sugrob.app`.
- Menu bar snowflake with a Snow on/off toggle and Quit. No Dock icon (`LSUIElement`).
- Deterministic SplitMix64 RNG and launch-flag parsing (`--hud`, `--debug-surfaces`,
  `--instant-snow`, `--seed N`).
- Falling snow: one click-through overlay per screen (rebuilt on display changes), Metal
  renderer with instanced soft round flakes (shaders compiled at runtime), fixed-size flake
  pool with sway and gentle gusting wind.
- Display-linked tick: 30 fps idle, 60 fps while a mouse button is down.
- Full pause (no tick, overlays hidden) on screen lock, screensaver, sleep, display sleep,
  fast user switching, shutdown, and when snow is toggled off.
- `--hud`: fps, flake count, ms per tick, render encode time, process CPU and memory.
- Snow settles on the top edges of windows: window tracking via `CGWindowListCopyWindowInfo`
  (no permissions; polled off the main thread at 8 Hz, 30 Hz while dragging), occlusion so
  covered parts of an edge show no snow, heightmap caps with angle-of-repose relaxation,
  lumpy ceiling, and droop over rounded corners. Caps move with their window; disappearing
  windows are debounced so Space switches don't wipe the snow.
- Fullscreen apps keep falling flakes while suppressing snow caps on the window and Dock.
- `--debug-surfaces` (window outlines, top edges, visible intervals) and `--instant-snow`.
- Knocked-off snow: debris particles under gravity with motion streaks, landing on windows
  below (snow transfers from window to window).
- Interactions: narrowing a window drops the snow from the removed part; moving a window
  immediately sheds its entire cap; the cursor brushes snow off caps;
  closed/minimized windows drop their snow.
- `--fps N` launch flag; HUD shows frame-pacing (worst gap, drops) and debris count.
- Snow on the Dock: its frame is estimated without permissions from the screen's visible
  frame and the Dock preferences (tile size, pinned apps, folders, recents, running apps),
  refreshed on app launch/quit. It can be brushed off with the cursor and falls off when the
  Dock hides. Optional precise width via Accessibility (`--precise-dock`, opt-in only).
- Full menu: Snow on/off, Intensity, Snow on Windows, Snow on Dock, Clear All Snow,
  Settings…, Quit. Settings window (SwiftUI): intensity, max drift height, wind, frame rate
  (Balanced / Smooth / Efficient), pause on battery, launch at login, precise Dock detection.
  Everything applies live.
- Pause on battery power (IOKit power-source notifications).
- Mission Control / App Exposé: snow pauses and nothing falls off when windows shrink into
  the overview. Stage Manager thumbnails don't collect snow.
- `--settings` launch flag; HUD shows settled snow mass and logs pauses with a count of frames
  presented while paused (always 0).
- App icon (drawn by `scripts/make_icon.swift`); the version is shown in Settings.
- Release packaging: `make app` builds a universal (arm64 + x86_64) app, `make dmg` packs a
  drag-to-Applications `.dmg`, a `.zip` and SHA-256 checksums. Developer ID builds are signed
  with the hardened runtime.
- GitHub Actions: CI (build, test, universal bundle, privacy guard) on pushes and pull
  requests; Release on `v*` tags, with signing and notarization when secrets are configured
  and ad-hoc signing otherwise.
- README in English and Russian, CONTRIBUTING, issue and pull request templates, Homebrew
  cask template in `packaging/`.

### Changed
- Settled caps skip relaxation until something changes them.
- Overlays are rebuilt only when screen frames or scale factors change, not when just the
  Dock or menu bar changes the visible frame (flakes no longer reshuffle).
- System process IDs (Dock, Stage Manager) are cached instead of looked up on every poll.
- Fresh snow eases into caps instead of appearing in steps; overflow at cap ends melts
  instead of dripping. Window positions are no longer extrapolated between polls.
