# Sugrob

*[Русская версия](README.ru.md)*

A tiny macOS menu bar app that makes it snow on your desktop. Flakes settle on the tops of
your windows and on the Dock, and the settled snow reacts: resize a window and it falls off,
fling a window and it flies away, brush it with the cursor and it crumbles.

> **Status:** early development. Not usable yet.

- No network access, ever.
- No permission prompts (no Screen Recording, Accessibility or Input Monitoring).
- Click-through overlay: it never steals focus or clicks.

## Build from source

Requires macOS 14+ and the Xcode Command Line Tools (Swift 6).

```sh
make test
make run          # builds build/Sugrob.app and launches it
```

## License

[MIT](LICENSE)
