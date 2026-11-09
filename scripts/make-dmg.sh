#!/bin/sh
# Baut dist/MonitorDeck-<Version>.dmg (App + Link auf /Applications) aus dem frischen Bundle.
# Aufruf: scripts/make-dmg.sh
# Immer ad-hoc signiert: Der öffentliche Download soll kein persönliches Zertifikat enthalten.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
SIGN_IDENTITY=- scripts/build-app.sh
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "dist/MonitorDeck.app/Contents/Info.plist")
dmg="dist/MonitorDeck-$version.dmg"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "dist/MonitorDeck.app" "$stage/MonitorDeck.app"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -volname "MonitorDeck" -srcfolder "$stage" -format UDZO "$dmg" >/dev/null
shasum -a 256 "$dmg"
echo "fertig: $dmg"
