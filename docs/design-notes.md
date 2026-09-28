# Design notes

How the native tools in this repo recognize global input, move windows and get
tested without disturbing real work. These decisions were exercised on macOS 26.3
and 15.x in September 2026; recheck the APIs when targeting newer releases.

## Recognizing input

- Both apps use a session-level
  [Core Graphics event tap](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:))
  placed at the head of the queue, so they can swallow a matched event before any
  app sees it.
- Modifier matching is exact over Control, Command, Shift and Option. Caps Lock,
  Fn and device-specific bits are ignored, so F9 still fires with Caps Lock on.
  The clipboard typer is the exception on purpose: it *requires* the
  device-dependent Right Control bit.
- MacBindings pairs presses with releases. When it swallows a key or button press
  it records the code and also swallows the matching release (and any drags),
  even if the modifiers were let go or shortcuts were paused in between.
  Otherwise the frontmost app would receive a release with no press.
- Key repeat never re-triggers an action, so holding F9 can't lock twice.
- Events MacBindings synthesizes (the Lock Screen shortcut) carry a marker in
  `eventSourceUserData`, so the tap passes its own output through instead of
  routing it again.
- The tap callback does as little as possible: it routes the event and captures
  the frontmost app's process ID. Accessibility calls, which can be slow, run on
  a serial worker queue with a 0.5 s messaging timeout. If macOS disables the tap
  after a timeout, the app re-enables it.
- Typed text is never logged.

## Actions

- **F6** opens `/System/Applications/Mission Control.app`, Apple's own
  [Mission Control](https://support.apple.com/guide/mac-help/mh35798/mac) view of
  windows and Spaces.
- **F9** posts Control+Command+Q, Apple's documented
  [Lock Screen shortcut](https://support.apple.com/en-us/102650). It locks; it
  doesn't log out or merely sleep the display.
- **Thirds** use the frontmost app's focused Accessibility window.

## Window geometry

- The target display is the one with the greatest overlap with the window, not
  the one under the mouse and not an assumed primary.
- The usable area is the display's current
  [`NSScreen.visibleFrame`](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe),
  which already excludes the Dock and menu bar.
- AppKit rectangles have a bottom-left origin; Accessibility uses top-left.
  Conversion is `axY = primaryScreenTop - rect.maxY`, and negative coordinates
  for monitors above or left of the primary are kept.
- Column *boundaries* are rounded, not widths, so three thirds of an odd-width
  screen meet with no gap and no overlap.
- The window is resized, moved, then resized again (for cross-display size
  limits), and its real bounds are read back. If an app's minimum size wins, the
  menu says so instead of claiming success.

## Mouse buttons

Button numbering differs between hardware, macOS and other utilities: human
"button 5" is not zero-based Quartz button 5. Instead of guessing, the menu has a
15-second learning mode that stores the real Quartz IDs per Mac. Learning either
button when the guesses are reversed swaps them.

## Testing without touching your documents

1. Routing and geometry live in `Bindings.swift`, which has no AppKit side
   effects, so they are unit-tested: paired releases, changed modifiers, held
   keys, unknown buttons, display overlap, negative origins, odd-width rounding.
2. `live-test` drives the installed app end to end with an unsaved window of its
   own. Before each injected event it checks that its window is still frontmost
   and stops otherwise, so it can't move another app's window.
3. Injected mouse events are placed *inside* the test window, in Quartz
   coordinates. With events at the existing cursor position outside the window,
   focus returned to the terminal after the first move; moving the injection
   point inside fixed it without any listener change.
4. It compares measured bounds with expected ones. Routing tests alone don't
   prove that another process's window moved.
5. It restores the cursor position and the previously active app.
6. Mission Control is checked visually, and a real lock/unlock is left to a person
   at the keyboard.

## Installation and distribution

- A proper menu-bar `.app` bundle (`LSUIElement`) with a stable identifier, so
  permissions attach to something that persists across launches.
- Both architecture slices are compiled and joined with `lipo`, then the bundle
  is signed and verified. Ad hoc signing works for local builds; a changed binary
  may need its permissions approved again. Compiling an Intel slice isn't the
  same as testing on Intel hardware.
- A per-user GUI LaunchAgent with `KeepAlive = { SuccessfulExit = false }`
  restarts crashes but leaves an intentional Quit stopped until the next login.
- Installed, listening-with-permissions and working-on-real-hardware are three
  different states. A matching hash, a valid signature or a running process
  doesn't prove the permissions were granted; each Mac needs its owner to
  approve Accessibility (and possibly Input Monitoring). Never copy or edit the
  privacy database.
- Keep an old hotkey utility available until the replacement has its
  permissions, then turn off the old one's launch at login so they don't compete
  after a reboot.
