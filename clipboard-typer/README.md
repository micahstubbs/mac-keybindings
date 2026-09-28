# Clipboard typer (Right Control+V)

Press **Right Control+V** anywhere to *type* the clipboard's text instead of
pasting it. That helps with fields and apps that block paste but accept keyboard
input: remote-desktop and VM consoles, some web forms, installers.

The text goes out as Unicode keyboard events (`CGEvent.keyboardSetUnicodeString`),
so accented letters, emoji and CJK text arrive intact regardless of keyboard
layout. Left Control+V and Command+V are not affected.

## Install

Requires Xcode Command Line Tools and Python 3 to install; macOS 13 or newer.

```bash
./install.sh install     # compile, archive any previous install, start at login
./install.sh status      # installed binary, permission state, recent log lines
./install.sh uninstall   # stop and archive the binary and login agent
```

Then grant the installed binary,
`~/Library/Application Support/ClipboardTyper/bin/right-control-v-daemon`, both
permissions in **System Settings → Privacy & Security**:

- **Input Monitoring**, to see the Right Control+V press
- **Accessibility**, to post the typed text

Until both are granted the daemon exits, and launchd retries it every ten
seconds, so it starts on its own once you approve it.

## How it works

The daemon is a session-level `CGEventTap` listening for key-down events. macOS
reports which side of the keyboard a modifier came from in device-dependent flag
bits (`IOLLEvent.h`); Right Control is `NX_DEVICERCTLKEYMASK` (`0x2000`). The tap
fires only for key code 9 (V) with the Control flag *and* the right-side bit set
and Shift, Option and Command all clear. It swallows that key press and types the
clipboard on a background queue, in chunks, ignoring key repeat and further
triggers while typing is in progress.

## Options

| Variable | Default | Meaning |
| --- | --- | --- |
| `CLIPBOARD_TYPER_LABEL` | `io.github.micahstubbs.clipboard-typer` | Launch-agent label (installer) |
| `SEND_KEYS_INITIAL_DELAY` | `0.15` | Seconds to wait after the hotkey before typing |
| `SEND_KEYS_CHUNK_SIZE` | `64` | UTF-16 code units per synthetic event |
| `SEND_KEYS_CHUNK_DELAY` | `0.02` | Seconds between chunks |

Lower the chunk size or raise the delay if a slow target drops characters.

## Other ways to run it

```bash
swift right-control-v-daemon.swift --verbose       # foreground, prints each trigger
swift right-control-v-daemon.swift --check-access  # permission state of this process
swift right-control-v-daemon.swift --match-test    # flag-matching self-test
swift type-clipboard.swift --dry-run               # one-shot typer, for any hotkey tool
```

`type-clipboard.swift` types the clipboard once and exits. Bind it to any key
with the hotkey tool you already use if you'd rather not run a daemon. When run
this way, the permission belongs to whichever app launches it.

The daemon never logs clipboard contents, only character counts with `--verbose`.
