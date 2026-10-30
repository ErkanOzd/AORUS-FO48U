#!/bin/sh
# Baut "MonitorDeck.app" (Release, ad-hoc signiert) nach dist/.
# Aufruf: scripts/build-app.sh
set -eu
version=0.1.1
root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/dist/MonitorDeck.app"
cd "$root"
swift build -c release
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp .build/release/MonitorDeck "$app/Contents/MacOS/MonitorDeck"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleIdentifier</key><string>io.github.erkanozd.monitordeck</string>
  <key>CFBundleName</key><string>MonitorDeck</string>
  <key>CFBundleDisplayName</key><string>MonitorDeck</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>MonitorDeck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright (c) 2026 Erkan Özdemir. MIT-Lizenz.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
echo "fertig: $app"
