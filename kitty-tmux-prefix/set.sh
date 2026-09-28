#!/usr/bin/env bash
# Usage: ./set.sh
#
# Run on the Mac. Adds a kitty key mapping so Cmd+B sends Ctrl+B (byte 0x02),
# so the tmux prefix sits where Ctrl sits on a PC keyboard when you SSH into a
# Linux box. Idempotent: safe to re-run. Backs up kitty.conf before changing it.
#
# Environment: KITTY_CONF (default: ~/.config/kitty/kitty.conf)
# Undo with: ./unset.sh
# Background: README.md in this directory
set -euo pipefail

CONF="${KITTY_CONF:-${HOME}/.config/kitty/kitty.conf}"
COMMENT='# tmux prefix: Cmd+B sends Ctrl+B (0x02) — same physical position as Ctrl on a PC keyboard'
MAPLINE='map cmd+b send_text all \x02'

mkdir -p "$(dirname "$CONF")"
touch "$CONF"

if grep -qF "$MAPLINE" "$CONF"; then
    echo "Already set in $CONF:"
    echo "  $MAPLINE"
else
    cp "$CONF" "${CONF}.backup.$(date +%Y%m%d-%H%M%S)"
    printf '\n%s\n%s\n' "$COMMENT" "$MAPLINE" >> "$CONF"
    echo "Added to $CONF:"
    echo "  $MAPLINE"
fi

if pgrep -x kitty >/dev/null 2>&1; then
    pkill -SIGUSR1 -x kitty || true
    echo "Reloaded kitty config (SIGUSR1)."
else
    echo "kitty not running; mapping applies on next launch."
fi

echo "Verify: in an SSH'd tmux session, press Cmd+B then c — a new tmux window should open."
