#!/bin/zsh
# Build PadPilot.app into ~/Applications, (re)install the login LaunchAgent, restart it.
set -euo pipefail
cd "$(dirname "$0")"
APP=~/Applications/PadPilot.app
mkdir -p "$APP/Contents/MacOS" ~/Library/LaunchAgents
swiftc -O -o "$APP/Contents/MacOS/PadPilot" src/main.swift
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.padpilot</string>
<key>CFBundleName</key><string>PadPilot</string>
<key>CFBundleExecutable</key><string>PadPilot</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSUIElement</key><true/>
<key>GCSupportsControllerUserInteraction</key><true/>
<key>NSMicrophoneUsageDescription</key><string>PadPilot listens while you hold the touchpad and types what you say.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>PadPilot turns your speech into text in the focused field.</string>
</dict></plist>
EOF
# Sign with a stable identity if you have one (keeps the Accessibility grant across rebuilds), else ad-hoc.
IDENTITY="${PADPILOT_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then IDENTITY="Apple Development"; fi
codesign --force --sign "${IDENTITY:--}" --identifier local.padpilot "$APP"

# First run: install the example config.
CFG=~/.config/padpilot/config.json
if [[ ! -f "$CFG" ]]; then mkdir -p ~/.config/padpilot; cp config.example.json "$CFG"; echo "installed config: $CFG"; fi

PL=~/Library/LaunchAgents/local.padpilot.plist
cat > "$PL" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.padpilot</string>
<key>ProgramArguments</key><array><string>$APP/Contents/MacOS/PadPilot</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ProcessType</key><string>Interactive</string>
</dict></plist>
EOF
launchctl bootout gui/$(id -u)/local.padpilot 2>/dev/null || true
for i in 1 2 3 4 5; do launchctl bootstrap gui/$(id -u) "$PL" 2>/dev/null && break; sleep 1; done
echo "built + started. log: ~/Library/Logs/padpilot.log"
