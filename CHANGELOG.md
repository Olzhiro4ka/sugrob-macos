# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
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
- Fullscreen apps pause the snow on their display only.
- `--debug-surfaces` (window outlines, top edges, visible intervals) and `--instant-snow`.
- Knocked-off snow: debris particles under gravity with motion streaks, landing on windows
  below (snow transfers from window to window).
- Interactions: narrowing a window drops the snow from the removed part; moving a window
  sheds its snow with the window's momentum (snow no longer rides along); the cursor brushes
  snow off caps; closed/minimized windows drop their snow.
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

### Changed
- Settled caps skip relaxation until something changes them.
- Overlays are rebuilt only when screen frames or scale factors change, not when just the
  Dock or menu bar changes the visible frame (flakes no longer reshuffle).
- System process IDs (Dock, Stage Manager) are cached instead of looked up on every poll.
- Fresh snow eases into caps instead of appearing in steps; overflow at cap ends melts
  instead of dripping. Window positions are no longer extrapolated between polls.
