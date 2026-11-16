<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="Sugrob icon">
</p>

<h1 align="center">Sugrob</h1>

<p align="center">
  Snow on your Mac desktop that actually piles up.<br>
  <a href="README.ru.md">Русская версия</a>
</p>

<p align="center">
  <a href="https://github.com/Olzhiro4ka/sugrob-macos/actions/workflows/ci.yml"><img src="https://github.com/Olzhiro4ka/sugrob-macos/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-24292f" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6-F05138" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-397B70" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="https://github.com/Olzhiro4ka/sugrob-macos/releases">Releases</a> ·
  <a href="CONTRIBUTING.md">Contributing</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

**Sugrob** (Russian *сугроб*, "snowdrift") is a tiny menu bar app that makes it snow over
everything on your screen. Flakes settle on the top edges of your windows and on the Dock or screen edge,
and the settled snow behaves like snow:

- **resize** a window and the snow past the new edge falls off;
- **move** a window and the snow doesn't ride along: it slides off, and a quick jerk flings it;
- **brush** the snow with the cursor and it crumbles into falling particles;
- push snow **off the Dock** with the cursor;
- watch a miniature snowplow clear snow when it piles up along the screen edge;
- snow knocked off one window lands on the window below it and **piles up there**.

## Made to stay out of your way

- **No permission prompts by default.** Sugrob needs no Screen Recording, Accessibility or Input
  Monitoring access. It only reads window *positions* (never titles or contents) and the
  cursor position. Precise Dock detection optionally uses Accessibility (see Settings).
- **No network access at all.** No telemetry, no analytics, no update checks. The app never
  opens a connection; CI checks the source for network APIs on every commit.
- **Never in the way.** The snow layer ignores the mouse completely: clicks go straight
  through to whatever is under it. No Dock icon and no entry in ⌘-Tab; the overlay never takes focus.
- **Adaptive rendering.** Balanced mode uses 30 fps at rest and 60 fps during interaction.
  Snow pauses on screen lock, sleep, the screensaver, Mission Control and, optionally,
  battery power. In fullscreen apps, flakes keep falling while window and Dock drifts are hidden.

## A few things to know

- Dock accumulation supports a **bottom, visible Dock**. For a side or auto-hidden Dock,
  choose **Screen Edge** under Bottom Snow.
- The Dock width is an estimate unless you enable precise detection.
- CPU and memory use depend on display count, resolution, intensity and frame-rate mode.
  Use `--hud` to measure your setup.

## Install

1. Download `Sugrob-x.y.z.dmg` from the [GitHub Releases](https://github.com/Olzhiro4ka/sugrob-macos/releases).
2. Open it and drag **Sugrob** into **Applications**.
3. Launch it. A snowflake appears in the menu bar.

> [!NOTE]
> Builds may be marked **Pre-release**. Check the release notes for known limitations
> and signing/notarization status. For a build that is not notarized, macOS may block
> the first launch. If you trust the download, allow it in **System Settings → Privacy
> & Security → Open Anyway** after trying to launch it. You can also build from source.

Requires macOS 14 Sonoma or later, Apple Silicon or Intel.

## Settings

Click the snowflake in the menu bar:

| Menu item | What it does |
|---|---|
| **Snow** | Turn the snow on or off. The snowflake dims when it is off. |
| **Intensity** | Light, Medium or Blizzard. |
| **Snow on Windows** | Toggle snow on window edges. |
| **Bottom Snow** | Choose the Dock or the screen edge. |
| **Snowplow** | Enable or disable the snowplow on the screen edge. |
| **Clear All Snow** | Clear accumulated snow. |
| **Settings…** (⌘,) | The settings window, below. |

The settings window adds:

- **Max drift height** (6–20 pt) and **Wind** (calm to 2×).
- **Frame rate:** *Balanced* (30 fps idle, 60 fps while snow is flying; the default),
  *Smooth* (always 60 fps, about twice the CPU) or *Efficient* (never above 30 fps).
- **Pause on battery.**
- **Launch at login.**
- **Precise Dock detection** (off by default). Sugrob estimates the Dock's size from your
  Dock settings. If the snow sits slightly wider or narrower than
  your Dock, this option measures it through Accessibility, and macOS will ask for that
  permission only when you turn it on.

Everything applies immediately.

## Build from source

Requires macOS 14+ and Swift 6: either Xcode 16+ or just the Command Line Tools
(`xcode-select --install`).

```sh
git clone https://github.com/Olzhiro4ka/sugrob-macos.git
cd Snow
make build    # debug executable; warnings are errors
make test     # unit tests for the simulation
make run      # builds build/Sugrob.app (debug) and launches it
make app      # release universal (arm64 + x86_64) build/Sugrob.app
make dmg      # build/Sugrob-<version>.dmg and .zip
```

Copy `build/Sugrob.app` to `/Applications`. Builds you make yourself are not quarantined,
so download quarantine does not apply.

Useful launch flags for development (`make run ARGS="--hud --debug-surfaces"`):

| Flag | Effect |
|---|---|
| `--hud` | fps, frame times, particle counts, CPU and memory |
| `--debug-surfaces` | outlines detected windows, their top edges and the Dock |
| `--instant-snow` | start with full drifts (for screenshots) |
| `--seed N` | deterministic randomness |
| `--fps N` | fixed frame rate |
| `--precise-dock` | Accessibility-based Dock measurement for this run |
| `--settings` | open the settings window at launch |

## How it works

One transparent, click-through window per display sits just above the Dock. Window
positions come from `CGWindowListCopyWindowInfo`, polled off the main thread a few times a
second, and the snow on each window edge is a small heightmap with angle-of-repose
physics. Everything is drawn with Metal in a single pass. The simulation lives in
`Sources/SnowCore`, has no UI dependencies and is covered by unit tests. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full design notes.

## Contributing

Bug reports and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).
Two hard rules: no network, and no permission prompts in the default configuration.

## License

[MIT](LICENSE) © 2026 Sugrob contributors. The license covers the source and bundled artwork.
