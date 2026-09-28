#!/bin/bash
# Plain-bash test suite. Portable checks run everywhere; Swift checks run only on macOS.
#
# Usage: ./tests/run.sh
set -euo pipefail
ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSES=0

pass() { PASSES=$((PASSES + 1)); echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

# --- Shell syntax -----------------------------------------------------------
while IFS= read -r script; do
  bash -n "$script" || fail "syntax: $script"
done < <(find "$ROOT" -name '*.sh' -not -path '*/.git/*')
pass "all shell scripts parse"

for script in macbindings/macbindings.sh clipboard-typer/install.sh kitty-tmux-prefix/set.sh kitty-tmux-prefix/unset.sh tests/run.sh; do
  [ -x "$ROOT/$script" ] || fail "not executable: $script"
done
pass "entry-point scripts are executable"

# --- kitty tmux prefix --------------------------------------------------------
CONF="$WORK/kitty/kitty.conf"
mkdir -p "$(dirname "$CONF")"
printf 'font_size 13\n' > "$CONF"
KITTY_CONF="$CONF" "$ROOT/kitty-tmux-prefix/set.sh" >/dev/null
KITTY_CONF="$CONF" "$ROOT/kitty-tmux-prefix/set.sh" >/dev/null
[ "$(grep -cF 'map cmd+b send_text all \x02' "$CONF")" = 1 ] || fail "set.sh should add exactly one mapping"
pass "set.sh is idempotent"
ls "$CONF".backup.* >/dev/null 2>&1 || fail "set.sh should back up kitty.conf"
pass "set.sh backs up kitty.conf"
KITTY_CONF="$CONF" "$ROOT/kitty-tmux-prefix/unset.sh" >/dev/null
! grep -qF 'cmd+b' "$CONF" || fail "unset.sh should remove the mapping and its comment"
grep -qx 'font_size 13' "$CONF" || fail "unset.sh should keep unrelated settings"
pass "unset.sh removes only the mapping"
KITTY_CONF="$CONF" "$ROOT/kitty-tmux-prefix/unset.sh" | grep -q 'nothing to do' || fail "unset.sh should be idempotent"
pass "unset.sh is idempotent"

# --- Clipboard typer launch agent -------------------------------------------
PLIST="$WORK/agent.plist"
HOME="$WORK/home" "$ROOT/clipboard-typer/install.sh" plist "$PLIST"
python3 - "$PLIST" "$WORK/home" <<'PY' || fail "clipboard typer plist"
import plistlib, sys
plist = plistlib.load(open(sys.argv[1], 'rb'))
home = sys.argv[2]
assert plist['Label'] == 'io.github.micahstubbs.clipboard-typer', plist['Label']
assert plist['ProgramArguments'][0].startswith(home + '/Library/'), plist['ProgramArguments']
assert plist['StandardOutPath'].startswith(home + '/Library/Logs/'), plist['StandardOutPath']
assert plist['KeepAlive'] == {'SuccessfulExit': False}
PY
pass "clipboard typer plist uses the installing user's home"
CLIPBOARD_TYPER_LABEL=com.example.typer HOME="$WORK/home" "$ROOT/clipboard-typer/install.sh" plist "$WORK/custom.plist"
grep -q 'com.example.typer' "$WORK/custom.plist" || fail "CLIPBOARD_TYPER_LABEL override"
pass "clipboard typer label is configurable"

# --- MacBindings installer --------------------------------------------------
if "$ROOT/macbindings/macbindings.sh" bogus >/dev/null 2>&1; then fail "unknown command should exit non-zero"; fi
USAGE="$("$ROOT/macbindings/macbindings.sh" bogus 2>&1 || true)"
grep -q 'uninstall' <<<"$USAGE" || fail "usage should list uninstall"
pass "macbindings.sh rejects unknown commands with usage"
grep -q 'let defaultBundleIdentifier = "io.github.micahstubbs.macbindings"' "$ROOT/macbindings/Sources/Bindings.swift" \
  && grep -q 'MACBINDINGS_BUNDLE_ID:-io.github.micahstubbs.macbindings' "$ROOT/macbindings/macbindings.sh" \
  || fail "app and installer must share one default bundle identifier"
pass "app and installer share the default bundle identifier"

# --- No personal data in the tree -------------------------------------------
# Generic leak shapes: home directories, IPv4 addresses, email addresses, issue-tracker ids.
LEAKS="$(grep -rInE '/(Users|home)/[a-z][a-z0-9_-]*/|([0-9]{1,3}\.){3}[0-9]{1,3}|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}|\bbd-[a-z0-9]{3,5}\b' \
  "$ROOT" --exclude-dir=.git --exclude-dir=.beads --exclude=run.sh || true)"
[ -z "$LEAKS" ] || { echo "$LEAKS" >&2; fail "personal-data shapes found in the tree"; }
pass "no home paths, IP addresses, emails or tracker ids in the tree"

# --- macOS only: compile and run the Swift tests ----------------------------
if [ "$(uname -s)" = Darwin ] && command -v xcrun >/dev/null 2>&1; then
  "$ROOT/macbindings/macbindings.sh" test
  pass "MacBindings routing and geometry tests"
  "$ROOT/clipboard-typer/install.sh" match-test
  pass "Right Control+V flag matching"
  xcrun swiftc -typecheck "$ROOT/clipboard-typer/type-clipboard.swift"
  pass "type-clipboard type-checks"
else
  echo "SKIP: Swift tests need macOS with Xcode Command Line Tools"
fi

echo "$PASSES checks passed"
