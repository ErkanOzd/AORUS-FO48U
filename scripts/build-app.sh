#!/bin/sh
# Baut "MonitorDeck.app" (Release) nach dist/.
# Signatur: SIGN_IDENTITY legt sie fest ("-" = ad-hoc); sonst die erste Identität "Apple Development" im Schlüsselbund,
# ohne sie ad-hoc. Mit Zertifikat bleibt die Signatur-Anforderung über Neubauten gleich, die Freigabe
# „Bedienungshilfen“ bleibt also erhalten; ad-hoc hängt sie am Hash jedes einzelnen Builds.
# Aufruf: scripts/build-app.sh   bzw.   SIGN_IDENTITY=- scripts/build-app.sh
set -eu
version=0.3.0
build=3
root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/dist/MonitorDeck.app"
cd "$root"
# Pfade des Build-Rechners nicht ins Binary schreiben (öffentlicher Download): Quellpfade umschreiben, Debug-Symbole entfernen.
swift build -c release -Xswiftc -file-prefix-map -Xswiftc "$root=."
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp .build/release/MonitorDeck "$app/Contents/MacOS/MonitorDeck"
strip -S -x "$app/Contents/MacOS/MonitorDeck"
if LC_ALL=C grep -a -q -e "$HOME" -e "$root" "$app/Contents/MacOS/MonitorDeck"; then echo "Fehler: Binary enthält noch Pfade des Build-Rechners" >&2; exit 1; fi
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
  <key>CFBundleVersion</key><string>$build</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright (c) 2026 Erkan Özdemir. MIT-Lizenz.</string>
</dict>
</plist>
PLIST
identity=${SIGN_IDENTITY-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"Apple Development: /{print $2; exit}')}
identity=${identity:--}
codesign --force --sign "$identity" "$app"
if [ "$identity" = "-" ]; then echo "signiert: ad-hoc"; else echo "signiert: Apple Development"; fi
echo "fertig: $app"
