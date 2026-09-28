# Cmd+B as the tmux prefix in kitty

Makes **Cmd+B** in [kitty](https://sw.kovidgoyal.net/kitty/) on a Mac send
**Ctrl+B** (byte `0x02`), the default tmux prefix. On a Mac keyboard, Cmd sits
where Ctrl sits on a PC keyboard, so switching between a Mac and a Linux desktop
keeps the prefix under the same finger.

```bash
./set.sh     # add the mapping to kitty.conf and reload kitty
./unset.sh   # remove it and reload kitty
```

Both scripts are idempotent and back up `kitty.conf` (as
`kitty.conf.backup.<timestamp>`) before changing it. Set `KITTY_CONF` to target a
config file other than `~/.config/kitty/kitty.conf`.

The mapping they add:

```
# tmux prefix: Cmd+B sends Ctrl+B (0x02) — same physical position as Ctrl on a PC keyboard
map cmd+b send_text all \x02
```

To check it, open tmux (locally or over SSH) and press **Cmd+B** then **c**: a
new tmux window should open. Only the prefix changes; the key after it is typed
normally.

## Why it has to be done in kitty

Over SSH a terminal sends only bytes and escape sequences. Modifier keys never
cross the connection, and kitty on macOS drops Cmd+B by default, so the remote
side (tmux, xmodmap, keyd) receives nothing it could remap. The translation has
to happen in the terminal on the Mac.

## Alternatives considered

- `map cmd+b send_key ctrl+b` also works on kitty 0.26 and later; `send_text` is
  the more portable form.
- Karabiner-Elements could remap Cmd to Ctrl system-wide or per app, but that is
  far more invasive and breaks normal macOS Cmd shortcuts.
- tmux `prefix2` on the remote side can't help, because no byte arrives to bind.
