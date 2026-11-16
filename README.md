<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="Sugrob icon">
</p>

<h1 align="center">Sugrob</h1>

<p align="center">
  Snow on your Mac desktop that actually piles up.<br>
  <a href="README.ru.md">Русская версия</a>
</p>

<!-- Demo GIF placeholder: record ~10 s of snow settling and being brushed off, save it as
     docs/demo.gif (≤ 5 MB) and uncomment the block below.
<p align="center">
  <img src="docs/demo.gif" width="720" alt="Snow settling on windows and the Dock">
</p>
-->

**Sugrob** (Russian *сугроб*, "snowdrift") is a tiny menu bar app that makes it snow over
everything on your screen. Flakes settle on the top edges of your windows and on the Dock or screen edge,
and the settled snow behaves like snow:

- **resize** a window and the snow past the new edge falls off;
- **move** a window and the snow doesn't ride along: it slides off, and a quick jerk flings it;
- **brush** the snow with the cursor and it crumbles into falling particles;
- push snow **off the Dock** with the cursor;
- watch a miniature snowplow clear snow when it piles up along the screen edge;
- snow knocked off one window lands on the window below it and **piles up there**.

## No permissions, no network

This is the main feature, not a footnote.

- **No permission prompts.** Sugrob needs no Screen Recording, Accessibility or Input
  Monitoring access. It only reads window *positions* (never titles or contents) and the
  cursor position, which macOS allows any app to do.
- **No network access at all.** No telemetry, no analytics, no update checks. The app never
  opens a connection; CI checks the source for network APIs on every commit.
- **Never in the way.** The snow layer ignores the mouse completely: clicks go straight
  through to whatever is under it. No Dock icon, not in ⌘-Tab, never takes focus.
- **Light.** About 3% CPU while snowing on Apple Silicon, nothing at all while paused.
  It pauses by itself when the screen is locked or asleep, during the screensaver, in
  Mission Control, on displays showing a fullscreen app, and (optionally) on battery.

## Install

1. Download `Sugrob-x.y.z.dmg` from the [latest release](../../releases/latest).
2. Open it and drag **Sugrob** into **Applications**.
3. Launch it. A snowflake appears in the menu bar.

> [!IMPORTANT]
> Release builds are not signed with an Apple Developer ID, so on first launch macOS says
> the app "cannot be opened because Apple cannot check it for malicious software".
> To open it anyway, do **one** of these:
> - right-click (or Control-click) Sugrob in Applications → **Open** → **Open**;
>   on macOS 15+, if there is no Open button, go to **System Settings → Privacy & Security**,
>   scroll down and click **Open Anyway**;
> - or run in Terminal:
>   ```sh
>   xattr -dr com.apple.quarantine /Applications/Sugrob.app
>   ```
>
> You only need to do this once. If you'd rather not trust a binary, [build it from
> source](#build-from-source): it takes a minute.

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
| **Clear All Snow** | Drop everything that has piled up. |
| **Settings…** (⌘,) | The settings window, below. |

The settings window adds:

- **Max drift height** (6–20 pt) and **Wind** (calm to 2×).
- **Frame rate:** *Balanced* (30 fps idle, 60 fps while snow is flying; the default),
  *Smooth* (always 60 fps, about twice the CPU) or *Efficient* (never above 30 fps).
- **Pause on battery.**
- **Launch at login.**
- **Precise Dock detection** (off by default). Sugrob estimates the Dock's size from your
  Dock settings, which is usually exact. If the snow sits slightly wider or narrower than
  your Dock, this option measures it through Accessibility, and macOS will ask for that
  permission only when you turn it on.

Everything applies immediately.

## Build from source

Requires macOS 14+ and Swift 6: either Xcode 16+ or just the Command Line Tools
(`xcode-select --install`).

```sh
git clone https://github.com/Olzhiro4ka/Snow.git
cd Snow
make test     # unit tests for the simulation
make run      # builds build/Sugrob.app (debug) and launches it
make app      # release universal (arm64 + x86_64) build/Sugrob.app
make dmg      # build/Sugrob-<version>.dmg and .zip
```

Copy `build/Sugrob.app` to `/Applications`. Builds you make yourself are not quarantined,
so they open without the Gatekeeper dance.

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
[CLAUDE.md](CLAUDE.md) for the full design notes.

## Contributing

Bug reports and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).
Two hard rules: no network, and no permission prompts in the default configuration.

## License

[MIT](LICENSE)
