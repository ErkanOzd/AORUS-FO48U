#!/bin/sh
# Baut MonitorDeck, ersetzt /Applications/MonitorDeck.app und startet die App.
# Hat sich die Signatur-Anforderung geändert, gilt eine erteilte Freigabe „Bedienungshilfen“ nicht mehr
# (der Schalter steht noch auf an, wirkt aber nicht): Dann öffnet das Skript die Seite in den Systemeinstellungen.
# Erteilen lässt sich die Freigabe nur dort.
# Aufruf: scripts/install.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
bundle_id=io.github.erkanozd.monitordeck
target=/Applications/MonitorDeck.app
cd "$root"
scripts/build-app.sh

requirement() { codesign -d -r- "$1" 2>/dev/null | sed -n 's/^designated => //p'; }
old=""
[ -d "$target" ] && old=$(requirement "$target")
new=$(requirement dist/MonitorDeck.app)

# Laufende Instanz beenden (startet die App nicht, falls sie nicht läuft).
osascript -e "if application id \"$bundle_id\" is running then tell application id \"$bundle_id\" to quit" >/dev/null
i=0
while pgrep -f "$target/Contents/MacOS/MonitorDeck" >/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done

rm -rf "$target"
ditto dist/MonitorDeck.app "$target"
echo "installiert: $target"

if [ "$old" != "$new" ]; then
    echo "Signatur geändert: In „Bedienungshilfen“ MonitorDeck aus- und wieder einschalten (oder mit „–“ entfernen"
    echo "und neu erlauben). Die Tastensteuerung startet danach von selbst."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
else
    echo "Signatur unverändert: Freigabe „Bedienungshilfen“ bleibt bestehen."
fi
open "$target"
