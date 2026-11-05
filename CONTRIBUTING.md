# Contributing to Sugrob

Thanks for helping! Sugrob is small on purpose. Changes that keep it light, private and
out of the way are the most welcome.

## Ground rules

These are not up for debate in a PR. Open an issue first if you think one must change.

1. **No network.** No requests, telemetry, analytics or update checks. CI fails if network
   APIs show up in `Sources/`.
2. **No permission prompts by default.** No Screen Recording, Accessibility or Input
   Monitoring in the default configuration. Never read `kCGWindowName`, because reading it
   requires Screen Recording. Accessibility exists only behind the opt-in "Precise Dock
   detection" toggle.
3. **Click-through, always.** The overlay must never take clicks or focus.
4. **Cheap.** About 3% CPU while idle-snowing, ≤ 1.5 ms per tick on the main thread, and no
   GPU work while paused. Measure with `make run ARGS="--hud"` and put the numbers in the PR.
5. **Public APIs only, no third-party dependencies.**

## Getting started

```sh
make build    # debug build, warnings are errors
make test     # SnowCore unit tests (Swift Testing)
make run ARGS="--hud --debug-surfaces"
```

Xcode 16+ or just the Command Line Tools work; there is no `.xcodeproj`. To use Xcode,
open `Package.swift`.

[CLAUDE.md](CLAUDE.md) holds the design notes, the coordinate-space rules and a list of known
gotchas. Read it before changing the simulation, window tracking or rendering.

## Code layout

- `Sources/SnowCore`: the simulation (flakes, caps, debris, interactions, Dock layout). Pure
  Swift with no AppKit or Metal, deterministic with `--seed`. **New behaviour here needs a
  unit test** in `Tests/SnowCoreTests`.
- `Sources/Sugrob`: the app (menu, window tracking, overlays, Metal renderer, settings).
- All tunables live in `SnowCore/Config.swift`, each with a comment giving its unit.

## Pull requests

- One logical change per PR, with [Conventional Commit](https://www.conventionalcommits.org/)
  messages (`feat:`, `fix:`, `perf:`, `docs:`, `chore:`).
- `make build` and `make test` must pass with zero warnings; CI runs both.
- For anything visual, describe what changed and attach a short screen recording if you can.
- For performance-sensitive changes, include before and after `--hud` numbers (ms/tick, CPU).
- Add a line to `CHANGELOG.md` under `[Unreleased]`.

## Reporting bugs

Use the bug report template. The most useful details are the macOS version, Mac model,
display setup (count, resolution, scaling), Dock position and size, and whether Stage
Manager is on. A `--hud` log helps a lot with performance issues:

```sh
/Applications/Sugrob.app/Contents/MacOS/Sugrob --hud 2> ~/Desktop/sugrob-hud.log
```

## Releasing (maintainers)

1. Move the `[Unreleased]` entries in `CHANGELOG.md` to `## [x.y.z] - YYYY-MM-DD`.
2. `git tag vx.y.z && git push origin vx.y.z`.
3. The Release workflow tests, builds the universal app, packs the `.dmg`, `.zip` and
   checksums, and publishes a GitHub release with the changelog section as notes. Tags with a
   suffix (`v1.0.0-beta.1`) become pre-releases.

Signing and notarization run only if these repository secrets exist; otherwise the build is
ad-hoc signed, and the release notes explain how to open it:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | `base64 -i DeveloperID.p12` of the Developer ID Application certificate and key |
| `DEVELOPER_ID_P12_PASSWORD` | password of that `.p12` |
| `DEVELOPER_ID_IDENTITY` | e.g. `Developer ID Application: Jane Doe (TEAMID1234)` |
| `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD` | Apple ID, team ID and an app-specific password for `notarytool` |

Then update `packaging/sugrob.rb` with the new version and the dmg's SHA-256 from the release's
`.sha256` file.
