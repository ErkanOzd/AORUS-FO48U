#!/bin/sh
# Baut dist/MonitorDeck-<Version>.dmg (App + Link auf /Applications) aus dem frischen Bundle.
# Aufruf: scripts/make-dmg.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
scripts/build-app.sh
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "dist/MonitorDeck.app/Contents/Info.plist")
dmg="dist/MonitorDeck-$version.dmg"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -R "dist/MonitorDeck.app" "$stage/"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -volname "MonitorDeck" -srcfolder "$stage" -format UDZO -ov "$dmg" >/dev/null
shasum -a 256 "$dmg"
echo "fertig: $dmg"
