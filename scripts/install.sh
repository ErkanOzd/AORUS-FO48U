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

# Laufende Instanz beenden (nur wenn eine läuft: Auf einem Mac ohne Installation kennt AppleScript die Bundle-ID nicht).
if pgrep -x MonitorDeck >/dev/null; then
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
    i=0
    while pgrep -x MonitorDeck >/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
    if pgrep -x MonitorDeck >/dev/null; then
        echo "MonitorDeck läuft noch (offener Dialog?). Bitte beenden und erneut aufrufen." >&2
        exit 1
    fi
fi

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
