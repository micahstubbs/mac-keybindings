# MacBindings

A small native Swift menu-bar app that replaces six hotkey-utility bindings. It
has no third-party runtime dependencies and makes no network connections. The
installer builds a universal app (Apple Silicon and Intel) for **macOS 13 or newer**.

| Input | Action |
| --- | --- |
| F6 | Mission Control, including the Spaces bar |
| F9 | Lock Screen |
| Control + lower/back thumb button | Move current window to the left third |
| Command + lower/back thumb button | Middle third |
| Command + upper/forward thumb button | Right third |
| Command + Shift + lower/back thumb button | Left third |

"Current window" means the focused window of the frontmost application when the
shortcut fires. The display with the greatest overlap with that window is used,
and each third fills that display's usable height, excluding the Dock and menu
bar. Full-screen and non-resizable windows produce a status message instead of a
move. Some applications enforce minimum sizes that prevent exact thirds; the app
reads back the result and says so.

## Install

Requirements to build: Xcode Command Line Tools (`xcode-select --install`, which
provides `swiftc`, `lipo` and `codesign`) and Python 3 for the launch-agent
plist. The running app needs none of these. No `sudo` is needed.

```bash
./macbindings.sh test      # routing and display-geometry tests; no GUI actions
./macbindings.sh install   # build, archive any previous install, start at login
```

The app lands in `~/Applications/MacBindings.app` and starts at every login. Look
for **Ⅲ** in the menu bar (**Ⅲ!** while permissions are missing, **ⅢⅡ** while paused).

## Grant permissions (once per Mac)

macOS privacy permissions are local to each Mac. Copying the app or syncing
settings does not carry them over.

1. **System Settings → Privacy & Security → Accessibility**: add and enable
   `~/Applications/MacBindings.app`. The menu's **Open Accessibility settings…**
   prompts for it; `./macbindings.sh permissions` opens the pane and reveals the app.
2. The app retries every three seconds. If the menu says event access is
   unavailable, use **Open Input Monitoring settings…**, enable MacBindings, then
   **Retry permissions**.
3. If another hotkey utility (BetterTouchTool, Karabiner, etc.) binds the same
   inputs, quit it while testing so the two handlers don't compete. If
   BetterTouchTool is running, the menu offers to quit it.

After a rebuild, macOS may ask you to approve the changed binary again.

## Teach it your mouse buttons

The initial thumb-button IDs are Quartz **3** and **4** (zero-based). Other
software may call the same buttons 4/5 or 5/6. If the mouse shortcuts do nothing,
choose **Learn down button…** and click the lower/back thumb button within 15
seconds, then **Learn up button…** with the upper/forward button. Don't hold a
modifier while learning. The learned IDs are saved per Mac.

Mice without thumb buttons can use **Use scroll wheel** instead: modifier +
scroll down acts as the "down" button and scroll up as "up".

Plain clicks, unmodified thumb buttons, scrolling and unrelated shortcuts pass
through untouched. Only matched presses, and their paired releases and drags,
are swallowed.

## Function keys

On Apple keyboards set to media controls, press Fn/Globe + F6/F9, or turn on
**Use F1, F2, etc. keys as standard function keys** under System Settings →
Keyboard → Keyboard Shortcuts → Function Keys. MacBindings listens for real F6/F9
key events; it does not remap media keys. See
[Apple's keyboard shortcut guide](https://support.apple.com/en-us/102650).

Secure Input (password fields, some terminals) and other input remappers can stop
any app from seeing global shortcuts.

## Commands

```bash
./macbindings.sh test            # routing/state and display geometry tests
./macbindings.sh live-test       # move a temporary test window through the running app
./macbindings.sh build           # universal, signed app in a fresh build directory
./macbindings.sh install         # build, archive previous install, start login agent
./macbindings.sh install-bundle /path/to/MacBindings.app   # install a signed prebuilt bundle
./macbindings.sh status          # process, launchd state, recent log lines
./macbindings.sh permissions     # open Accessibility settings and reveal the app
./macbindings.sh stop            # stop now; keeps the login agent
./macbindings.sh start           # start again
./macbindings.sh disable-login   # stop and archive the login agent
./macbindings.sh uninstall       # stop and archive the app and login agent
```

**Pause shortcuts** in the menu persists across restarts. **Quit MacBindings**
exits cleanly; launchd restarts crashes but not an intentional quit. The next
login starts it again unless the login agent was archived.

`live-test` needs the installed app running with permissions, and the terminal
that launches the test needs Accessibility permission to post events. It opens an
unsaved test window, sends each mouse binding inside that window, compares the
measured bounds with the expected third, and stops if the window loses focus. It
never tests F9, so it can't lock your session.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `MACBINDINGS_BUNDLE_ID` | `io.github.micahstubbs.macbindings` | Bundle identifier, launch-agent label and defaults domain |
| `MACBINDINGS_SIGN_IDENTITY` | `-` (ad hoc) | `codesign` identity used by `build` |

Menu choices are stored in the defaults domain (`downButton`, `upButton`,
`mouseMode`, `paused`).

To change which keys do what, edit `BindingRouter.route` in
`Sources/Bindings.swift` (F6 is virtual key code 97, F9 is 101) and add a case to
`Tests/RoutingTests.swift`.

## Files

| Path | Purpose |
| --- | --- |
| `Sources/Bindings.swift` | Pure routing state machine and thirds geometry (unit-tested) |
| `Sources/main.swift` | Event tap, Accessibility window moves, menu-bar UI |
| `Tests/RoutingTests.swift` | 32 routing and geometry checks |
| `Tests/LiveTest.swift` | End-to-end check against the installed app |
| `~/Applications/MacBindings.app` | Installed app |
| `~/Library/LaunchAgents/<bundle id>.plist` | Login agent |
| `~/Library/Logs/MacBindings.log` | Actions and status only; typed text is never logged |
| `~/Library/Application Support/MacBindings/` | Builds, test binaries, archived installs |

Installs never delete: the previous app and plist move together into a unique
archive directory before the new ones go in.

## Installing on several Macs

Build once, then give the other Macs the finished bundle so they don't each need
the Command Line Tools:

```bash
./macbindings.sh build                       # prints the bundle path
# copy MacBindings.app to the other Mac, then on that Mac:
./macbindings.sh install-bundle /path/to/MacBindings.app
```

`install-bundle` checks the bundle identifier and code signature, copies it to a
fresh staging directory, verifies it again, then installs. It needs Python 3 but
not a Swift compiler. The login agent needs a logged-in desktop session
(`launchctl bootstrap gui/<uid>`), so installing over SSH works only while that
user is logged in at the Mac. Grant permissions and learn the thumb buttons on
each Mac separately.

See [the design notes](../docs/design-notes.md) for how the event tap, window
geometry and tests fit together.
