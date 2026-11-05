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
