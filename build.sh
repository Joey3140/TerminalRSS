#!/bin/bash
# Build and install TerminalRSS to /Applications
set -eo pipefail

cd "$(dirname "$0")"

echo "Building TerminalRSS..."
swift build -c release 2>&1

APP_DIR="build/TerminalRSS.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp .build/release/TerminalRSS "$APP_DIR/Contents/MacOS/TerminalRSS"

# Copy icon
if [ -f "TerminalRSS.icns" ]; then
  cp TerminalRSS.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TerminalRSS</string>
    <key>CFBundleIdentifier</key>
    <string>com.twentyfiftysix.terminalrss</string>
    <key>CFBundleName</key>
    <string>TerminalRSS</string>
    <key>CFBundleDisplayName</key>
    <string>TerminalRSS</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.news</string>
</dict>
</plist>
EOF

# Sign with a stable Developer ID so TCC permissions persist across rebuilds
# (an unsigned/ad-hoc bundle gets a fresh identity every build, resetting any
# consent). Falls back to ad-hoc on any machine that lacks the Developer ID cert.
SIGN_ID="Developer ID Application: Joseph Drury (4MMDJ2N969)"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
  codesign --force --sign "$SIGN_ID" --identifier com.twentyfiftysix.terminalrss \
    "$APP_DIR" 2>&1 | tail -3 || echo "codesign failed (continuing)"
else
  codesign --force --sign - --identifier com.twentyfiftysix.terminalrss \
    "$APP_DIR" 2>&1 | tail -3 || echo "codesign failed (continuing)"
fi

# Remove old version and install
rm -rf /Applications/TerminalRSS.app
cp -R "$APP_DIR" /Applications/TerminalRSS.app
echo "Installed to /Applications/TerminalRSS.app"
open /Applications/TerminalRSS.app
