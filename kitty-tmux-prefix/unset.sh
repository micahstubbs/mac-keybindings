#!/usr/bin/env bash
# Usage: ./unset.sh
#
# Run on the Mac. Removes the Cmd+B -> Ctrl+B kitty mapping added by set.sh,
# restoring default Cmd+B behavior. Idempotent: safe to re-run.
#
# Environment: KITTY_CONF (default: ~/.config/kitty/kitty.conf)
# Background: README.md in this directory
set -euo pipefail

CONF="${KITTY_CONF:-${HOME}/.config/kitty/kitty.conf}"
COMMENT_PREFIX='# tmux prefix: Cmd+B sends Ctrl+B'
MAPLINE='map cmd+b send_text all \x02'

if [ ! -f "$CONF" ] || ! grep -qF "$MAPLINE" "$CONF"; then
    echo "Mapping not present in $CONF; nothing to do."
    exit 0
fi

cp "$CONF" "${CONF}.backup.$(date +%Y%m%d-%H%M%S)"

TMP="$(mktemp)"
grep -vF "$MAPLINE" "$CONF" | grep -vF "$COMMENT_PREFIX" > "$TMP" || true
mv "$TMP" "$CONF"
echo "Removed from $CONF:"
echo "  $MAPLINE"

if pgrep -x kitty >/dev/null 2>&1; then
    pkill -SIGUSR1 -x kitty || true
    echo "Reloaded kitty config (SIGUSR1)."
else
    echo "kitty not running; change applies on next launch."
fi
