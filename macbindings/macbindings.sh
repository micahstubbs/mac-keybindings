#!/bin/bash
# Build, install and manage MacBindings, a native window/shortcut menu-bar app.
#
# Usage: ./macbindings.sh {build|test|live-test|install|install-bundle APP|start|stop|status|permissions|disable-login|uninstall}
#
# Environment:
#   MACBINDINGS_BUNDLE_ID      Bundle identifier and launch-agent label
#                              (default: io.github.micahstubbs.macbindings)
#   MACBINDINGS_SIGN_IDENTITY  codesign identity (default: "-", ad hoc)
set -euo pipefail
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P -- "$(dirname -- "$SOURCE")" && pwd)"
  TARGET="$(readlink "$SOURCE")"
  case "$TARGET" in /*) SOURCE="$TARGET" ;; *) SOURCE="$DIR/$TARGET" ;; esac
done
ROOT="$(cd -P -- "$(dirname -- "$SOURCE")" && pwd)"
LABEL="${MACBINDINGS_BUNDLE_ID:-io.github.micahstubbs.macbindings}"
APP="$HOME/Applications/MacBindings.app"
SUPPORT="$HOME/Library/Application Support/MacBindings"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/MacBindings.log"
COMMAND="${1:-status}"

build() {
  mkdir -p "$SUPPORT/builds"
  BUILD="$(mktemp -d "$SUPPORT/builds/build.XXXXXXXX")"
  BUNDLE="$BUILD/MacBindings.app"
  mkdir -p "$BUNDLE/Contents/MacOS"
  # Build both architectures so the same bundle can run on Intel and Apple Silicon.
  for arch in arm64 x86_64; do
    xcrun swiftc -O -target "$arch-apple-macosx13.0" \
      "$ROOT/Sources/Bindings.swift" "$ROOT/Sources/main.swift" -o "$BUILD/MacBindings-$arch"
  done
  xcrun lipo -create "$BUILD/MacBindings-arm64" "$BUILD/MacBindings-x86_64" -output "$BUNDLE/Contents/MacOS/MacBindings"
  /usr/bin/plutil -create xml1 "$BUNDLE/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string "$LABEL" "$BUNDLE/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleName -string MacBindings "$BUNDLE/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleExecutable -string MacBindings "$BUNDLE/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundlePackageType -string APPL "$BUNDLE/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleShortVersionString -string 1.0.0 "$BUNDLE/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleVersion -string 1 "$BUNDLE/Contents/Info.plist"
  /usr/bin/plutil -insert LSMinimumSystemVersion -string 13.0 "$BUNDLE/Contents/Info.plist"
  /usr/bin/plutil -insert LSUIElement -bool true "$BUNDLE/Contents/Info.plist"
  /usr/bin/codesign --force --sign "${MACBINDINGS_SIGN_IDENTITY:--}" --identifier "$LABEL" "$BUNDLE"
  /usr/bin/codesign --verify --deep --strict "$BUNDLE"
  echo "Built: $BUNDLE"
}

case "$COMMAND" in
  build) build ;;
  test|live-test)
    mkdir -p "$SUPPORT/test-builds"
    TEST_BUILD="$(mktemp -d "$SUPPORT/test-builds/test.XXXXXXXX")"
    TEST_SOURCE="$ROOT/Tests/RoutingTests.swift"
    if [ "$COMMAND" = live-test ]; then TEST_SOURCE="$ROOT/Tests/LiveTest.swift"; fi
    cp "$TEST_SOURCE" "$TEST_BUILD/main.swift"
    xcrun swiftc "$ROOT/Sources/Bindings.swift" "$TEST_BUILD/main.swift" -o "$TEST_BUILD/tests"
    "$TEST_BUILD/tests"
    ;;
  install|install-bundle)
    if [ "$COMMAND" = install ]; then
      build
    else
      PREBUILT="${2:?Usage: macbindings.sh install-bundle /path/to/MacBindings.app}"
      if [ ! -f "$PREBUILT/Contents/MacOS/MacBindings" ]; then echo "Not a MacBindings bundle: $PREBUILT" >&2; exit 1; fi
      if [ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$PREBUILT/Contents/Info.plist")" != "$LABEL" ]; then
        echo "Unexpected bundle identifier; refusing installation." >&2; exit 1
      fi
      /usr/bin/codesign --verify --deep --strict "$PREBUILT"
      mkdir -p "$SUPPORT/builds"
      BUILD="$(mktemp -d "$SUPPORT/builds/prebuilt.XXXXXXXX")"
      BUNDLE="$BUILD/MacBindings.app"
      /usr/bin/ditto "$PREBUILT" "$BUNDLE"
      /usr/bin/codesign --verify --deep --strict "$BUNDLE"
    fi
    # Prepare and validate the new login agent before stopping/replacing an existing install.
    python3 - "$BUILD/agent.plist" "$APP" "$LABEL" "$LOG" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'xb') as output:
    plistlib.dump({
        'Label': sys.argv[3],
        'ProgramArguments': [sys.argv[2] + '/Contents/MacOS/MacBindings'],
        'RunAtLoad': True,
        'KeepAlive': {'SuccessfulExit': False},
        'LimitLoadToSessionType': 'Aqua',
        'ThrottleInterval': 10,
        'StandardOutPath': sys.argv[4],
        'StandardErrorPath': sys.argv[4],
    }, output)
PY
    /usr/bin/plutil -lint "$BUILD/agent.plist"
    mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" "$SUPPORT/archive"
    ARCHIVE="$(mktemp -d "$SUPPORT/archive/install.XXXXXXXX")"
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    # Gracefully stop a manually opened instance too; do not touch BetterTouchTool.
    if pgrep -x MacBindings >/dev/null; then
      pkill -TERM -x MacBindings
      for _ in 1 2 3 4 5; do
        if ! pgrep -x MacBindings >/dev/null; then break; fi
        sleep 1
      done
      if pgrep -x MacBindings >/dev/null; then echo "MacBindings did not stop; installation aborted." >&2; exit 1; fi
    fi
    if [ -e "$APP" ]; then mv "$APP" "$ARCHIVE/MacBindings.app"; fi
    if [ -e "$PLIST" ]; then mv "$PLIST" "$ARCHIVE/$LABEL.plist"; fi
    mv "$BUNDLE" "$APP"
    mv "$BUILD/agent.plist" "$PLIST"
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "Installed and started $APP"
    echo "Use the Ⅲ menu to grant Accessibility and learn your two thumb buttons."
    echo "Previous installs are preserved in $ARCHIVE"
    ;;
  start)
    if [ ! -f "$PLIST" ]; then echo "Run ./macbindings.sh install first." >&2; exit 1; fi
    if ! launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then launchctl bootstrap "gui/$(id -u)" "$PLIST"; fi
    launchctl kickstart "gui/$(id -u)/$LABEL"
    ;;
  stop)
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    if pgrep -x MacBindings >/dev/null; then pkill -TERM -x MacBindings; fi
    echo "Stopped for this login session."
    ;;
  disable-login)
    "$SOURCE" stop
    if [ -f "$PLIST" ]; then
      mkdir -p "$SUPPORT/archive"
      ARCHIVE="$(mktemp -d "$SUPPORT/archive/disabled.XXXXXXXX")"
      mv "$PLIST" "$ARCHIVE/$LABEL.plist"
      echo "Archived login agent to $ARCHIVE"
    fi
    ;;
  uninstall)
    # Nothing is deleted: the app and login agent move into a unique archive directory.
    "$SOURCE" stop
    mkdir -p "$SUPPORT/archive"
    ARCHIVE="$(mktemp -d "$SUPPORT/archive/uninstalled.XXXXXXXX")"
    if [ -e "$APP" ]; then mv "$APP" "$ARCHIVE/MacBindings.app"; fi
    if [ -e "$PLIST" ]; then mv "$PLIST" "$ARCHIVE/$LABEL.plist"; fi
    echo "Moved MacBindings.app and its login agent to $ARCHIVE"
    echo "Settings remain in the defaults domain $LABEL; remove them with: defaults delete $LABEL"
    ;;
  status)
    if [ -d "$APP" ]; then echo "Installed: $APP"; else echo "Not installed"; fi
    pgrep -lx MacBindings || true
    launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | sed -n '1,22p' || true
    if [ -f "$LOG" ]; then tail -n 8 "$LOG"; fi
    ;;
  permissions)
    open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
    open -R "$APP"
    ;;
  *) echo "Usage: macbindings.sh {build|test|live-test|install|install-bundle APP|start|stop|status|permissions|disable-login|uninstall}"; exit 1 ;;
esac
