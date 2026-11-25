#!/bin/zsh
# Add PadPilot's Claude Code hooks (light + rumble when Claude needs you / finishes).
# Red alert only for real permission/question prompts, not the 60s idle reminder.
# Idempotent, keeps your existing hooks, backs up settings.json first. Requires jq.
set -euo pipefail
S=~/.claude/settings.json
B="$HOME/Applications/PadPilot.app/Contents/MacOS/PadPilot"
mkdir -p ~/.claude; [[ -f "$S" ]] || echo '{}' > "$S"
if grep -q "PadPilot --notify" "$S"; then echo "hooks already installed"; exit 0; fi
cp "$S" "$S.padpilot-backup"
# The hook never fails: missing app or no controller still exits 0.
A="[ -x $B ] && $B --notify attention --stdin >/dev/null 2>&1; exit 0"
D="[ -x $B ] && $B --notify done --stdin >/dev/null 2>&1; exit 0"
W="[ -x $B ] && $B --notify working --stdin >/dev/null 2>&1; exit 0"
jq --arg a "$A" --arg d "$D" --arg w "$W" '
  .hooks.Notification = ((.hooks.Notification // []) + [{"matcher":"permission_prompt|elicitation_dialog","hooks":[{"type":"command","command":$a,"timeout":5}]}]) |
  .hooks.Stop = ((.hooks.Stop // []) + [{"hooks":[{"type":"command","command":$d,"timeout":5}]}]) |
  .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{"hooks":[{"type":"command","command":$w,"timeout":5}]}]) |
  .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{"matcher":"*","hooks":[{"type":"command","command":$w,"timeout":5}]}])' "$S.padpilot-backup" > "$S"
echo "hooks installed (backup: $S.padpilot-backup)"
echo "For per-session Terminal tab colours, add this to your status line script right after it reads stdin into \$input:"
echo '  ( "$HOME/Applications/PadPilot.app/Contents/MacOS/PadPilot" --notify "view|$(printf %s "$input" | jq -r "[(.session_id//\"\"),(.workspace.current_dir//.cwd//\"\")]|join(\"|\")")|$(ps -o tty= -p $$ | tr -d " ")" >/dev/null 2>&1 & )'
