# mac-keybindings

Native macOS keyboard and mouse shortcuts, with no third-party hotkey utility.
Each tool is a small Swift program or shell script you can read in one sitting.

| Tool | What it does |
| --- | --- |
| [MacBindings](macbindings/) | Menu-bar app: **F6 → Mission Control**, **F9 → Lock Screen**, and modifier + mouse thumb button moves the current window to the left, middle or right third of its display |
| [Clipboard typer](clipboard-typer/) | **Right Control+V** types the clipboard as keystrokes, for fields that block paste |
| [kitty tmux prefix](kitty-tmux-prefix/) | **Cmd+B** in kitty sends Ctrl+B, so the tmux prefix is under the same finger on Mac and PC keyboards |

MacBindings and the clipboard typer replace bindings that previously lived in
BetterTouchTool. They use a Core Graphics event tap, run as per-user login agents,
and make no network connections.

## Quick start

```bash
git clone https://github.com/micahstubbs/mac-keybindings.git
cd mac-keybindings

./macbindings/macbindings.sh install     # F6/F9 and window thirds
./clipboard-typer/install.sh install     # Right Control+V
./kitty-tmux-prefix/set.sh               # Cmd+B tmux prefix in kitty
```

Then grant permissions: each tool's README says which ones and where. macOS
privacy approvals are per Mac and can't be scripted, which is deliberate.

## Requirements

- macOS 13 Ventura or newer; universal build for Apple Silicon and Intel
  (Intel is compiled but hasn't been tested on Intel hardware)
- Xcode Command Line Tools (`xcode-select --install`) and Python 3 to build and
  install. The installed apps need neither.
- [kitty](https://sw.kovidgoyal.net/kitty/) for the tmux prefix mapping
- No `sudo`, no Homebrew packages, no background network services

## Safety properties

- Installers never delete. Previous installs move into a timestamped archive
  directory under `~/Library/Application Support/`.
- Only exact matches are swallowed; everything else passes through, including
  the releases of keys you pressed before a shortcut was paused.
- Typed text and clipboard contents are never logged.
- The live end-to-end test uses its own unsaved window and stops if focus moves
  elsewhere, so it can't move or type into your documents.

## Tests

```bash
./tests/run.sh
```

Runs the portable checks (shell syntax, kitty config round trip, launch-agent
plist generation, a personal-data scrub) everywhere. On macOS it also compiles
and runs the MacBindings routing and geometry tests and the Right Control+V
flag-matching test. CI runs the full suite on a macOS runner and ShellCheck on Linux.

`./macbindings/macbindings.sh live-test` is a separate end-to-end check against
the installed, permitted app; see the [MacBindings README](macbindings/README.md).

## Documentation

- [MacBindings](macbindings/README.md): install, permissions, button learning,
  commands, configuration, multi-Mac installs
- [Clipboard typer](clipboard-typer/README.md)
- [kitty tmux prefix](kitty-tmux-prefix/README.md)
- [Design notes](docs/design-notes.md): event-tap pairing, window geometry,
  safe testing, distribution
- [Contributing](CONTRIBUTING.md)

## License

[Apache License 2.0](LICENSE).
