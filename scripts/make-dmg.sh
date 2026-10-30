#!/bin/sh
# Baut dist/FO48U-Control-<Version>.dmg (App + Link auf /Applications) aus dem frischen Bundle.
# Aufruf: scripts/make-dmg.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
scripts/build-app.sh
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "dist/FO48U Control.app/Contents/Info.plist")
dmg="dist/FO48U-Control-$version.dmg"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -R "dist/FO48U Control.app" "$stage/"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -volname "FO48U Control" -srcfolder "$stage" -format UDZO -ov "$dmg" >/dev/null
shasum -a 256 "$dmg"
echo "fertig: $dmg"
