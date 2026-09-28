#!/bin/bash
# Install, inspect or remove the Right Control+V clipboard typer as a per-user login agent.
#
# Usage: ./install.sh {install|uninstall|status|check-access|match-test|plist PATH}
#
# Environment:
#   CLIPBOARD_TYPER_LABEL  launch-agent label (default: io.github.micahstubbs.clipboard-typer)
#
# Nothing is deleted. Reinstalling or uninstalling moves the previous binary and
# plist into a unique directory under ~/Library/Application Support/ClipboardTyper/archive.
set -euo pipefail
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P -- "$(dirname -- "$SOURCE")" && pwd)"
  TARGET="$(readlink "$SOURCE")"
  case "$TARGET" in /*) SOURCE="$TARGET" ;; *) SOURCE="$DIR/$TARGET" ;; esac
done
ROOT="$(cd -P -- "$(dirname -- "$SOURCE")" && pwd)"
LABEL="${CLIPBOARD_TYPER_LABEL:-io.github.micahstubbs.clipboard-typer}"
SUPPORT="$HOME/Library/Application Support/ClipboardTyper"
BIN="$SUPPORT/bin/right-control-v-daemon"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/ClipboardTyper.log"
COMMAND="${1:-status}"

# Write the launch-agent plist for BIN to the given path. Kept separate so tests can check it on any OS.
write_plist() {
  python3 - "$1" "$LABEL" "$BIN" "$LOG" <<'PY'
import plistlib, sys
path, label, binary, log = sys.argv[1:5]
with open(path, 'xb') as output:
    plistlib.dump({
        'Label': label,
        'ProgramArguments': [binary],
        'RunAtLoad': True,
        'KeepAlive': {'SuccessfulExit': False},
        'LimitLoadToSessionType': 'Aqua',
        'ThrottleInterval': 10,
        'StandardOutPath': log,
        'StandardErrorPath': log,
    }, output)
PY
}

archive_existing() {
  mkdir -p "$SUPPORT/archive"
  ARCHIVE="$(mktemp -d "$SUPPORT/archive/$1.XXXXXXXX")"
  if [ -e "$BIN" ]; then mv "$BIN" "$ARCHIVE/"; fi
  if [ -e "$PLIST" ]; then mv "$PLIST" "$ARCHIVE/"; fi
  echo "Previous files (if any) are in $ARCHIVE"
}

case "$COMMAND" in
  install)
    mkdir -p "$SUPPORT/builds"
    BUILD="$(mktemp -d "$SUPPORT/builds/build.XXXXXXXX")"
    xcrun swiftc -O "$ROOT/right-control-v-daemon.swift" -o "$BUILD/right-control-v-daemon"
    "$BUILD/right-control-v-daemon" --match-test >/dev/null
    write_plist "$BUILD/agent.plist"
    /usr/bin/plutil -lint "$BUILD/agent.plist"
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    archive_existing install
    mkdir -p "$SUPPORT/bin" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
    mv "$BUILD/right-control-v-daemon" "$BIN"
    mv "$BUILD/agent.plist" "$PLIST"
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "Installed and started $LABEL"
    echo "Grant $BIN both Input Monitoring and Accessibility in"
    echo "System Settings > Privacy & Security, then run: $0 status"
    ;;
  uninstall)
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    archive_existing uninstalled
    ;;
  status)
    if [ -x "$BIN" ]; then echo "Installed: $BIN"; "$BIN" --check-access || true; else echo "Not installed"; fi
    launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | sed -n '1,12p' || true
    if [ -f "$LOG" ]; then tail -n 8 "$LOG"; fi
    ;;
  check-access) exec /usr/bin/swift "$ROOT/right-control-v-daemon.swift" --check-access ;;
  match-test) exec /usr/bin/swift "$ROOT/right-control-v-daemon.swift" --match-test ;;
  plist) write_plist "${2:?Usage: install.sh plist PATH}" ;;
  *) echo "Usage: install.sh {install|uninstall|status|check-access|match-test|plist PATH}"; exit 1 ;;
esac
