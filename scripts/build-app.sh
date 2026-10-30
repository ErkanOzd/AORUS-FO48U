#!/bin/sh
# Baut "FO48U Control.app" (Release, ad-hoc signiert) nach dist/.
# Aufruf: scripts/build-app.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/dist/FO48U Control.app"
cd "$root"
swift build -c release
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/FO48UControl "$app/Contents/MacOS/FO48UControl"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.erkanozd.fo48ucontrol</string>
  <key>CFBundleName</key><string>FO48U Control</string>
  <key>CFBundleExecutable</key><string>FO48UControl</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
echo "fertig: $app"
