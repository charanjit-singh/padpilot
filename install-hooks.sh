#!/bin/zsh
# Add PadPilot's Claude Code hooks (light + rumble when Claude needs you / finishes).
# Idempotent, keeps your existing hooks, backs up settings.json first. Requires jq.
set -euo pipefail
S=~/.claude/settings.json
B="$HOME/Applications/PadPilot.app/Contents/MacOS/PadPilot"
mkdir -p ~/.claude; [[ -f "$S" ]] || echo '{}' > "$S"
if grep -q "PadPilot --notify" "$S"; then echo "hooks already installed"; exit 0; fi
cp "$S" "$S.padpilot-backup"
# The hook never fails: missing app or no controller still exits 0.
A="[ -x $B ] && $B --notify attention >/dev/null 2>&1; exit 0"
D="[ -x $B ] && $B --notify done >/dev/null 2>&1; exit 0"
jq --arg a "$A" --arg d "$D" '
  .hooks.Notification = ((.hooks.Notification // []) + [{"hooks":[{"type":"command","command":$a,"timeout":5}]}]) |
  .hooks.Stop = ((.hooks.Stop // []) + [{"hooks":[{"type":"command","command":$d,"timeout":5}]}])' "$S.padpilot-backup" > "$S"
echo "hooks installed (backup: $S.padpilot-backup)"
