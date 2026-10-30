# FO48U Control

Menüleisten-App für macOS (Apple Silicon), die den **Gigabyte AORUS FO48U** per DDC/CI steuert, als Ersatz für den Windows-only „OSD Sidekick“. *English: a macOS menu bar app that controls the Gigabyte AORUS FO48U monitor over DDC/CI, replacing the Windows-only OSD Sidekick.*

> Inoffizielles Projekt, nicht mit GIGABYTE verbunden. „GIGABYTE“ und „AORUS“ sind Marken ihrer Inhaber. Nutzung auf eigene Gefahr (siehe Hinweise).

## Funktionen

Helligkeit, Kontrast, Lautstärke, Schärfe, Black eQualizer, Bildmodus, Eingang, OverDrive, Gamma, Farbtemperatur, Fadenkreuz, FreeSync, Aim Stabilizer, Refresh-Anzeige, Autostart beim Anmelden. Jeder Schreibvorgang wird zurückgelesen und bis zu dreimal wiederholt; nach einem Eingangswechsel sucht die App den DDC-Dienst neu.

## Voraussetzungen

- Apple-Silicon-Mac, macOS 14 oder neuer
- FO48U per USB-C (DisplayPort-Alt-Mode) angeschlossen
- Xcode-Kommandozeilenwerkzeuge (Swift 5.9)

## Installation

```sh
git clone https://github.com/ErkanOzd/AORUS-FO48U.git && cd AORUS-FO48U
scripts/build-app.sh                       # baut dist/FO48U Control.app (ad-hoc signiert)
cp -R "dist/FO48U Control.app" ~/Applications/
open ~/Applications/"FO48U Control.app"
```

Die App ist nicht notarisiert; beim ersten Start ggf. im Finder per Rechtsklick „Öffnen“. Autostart: Schalter „Beim Anmelden starten“ im Menü oder `FO48UControl --autostart on|off`.

Ohne App-Bundle: `swift build && .build/debug/FO48UControl`.

## Befehle

| Befehl | Wirkung |
|---|---|
| `FO48UControl --selftest` | liest alle Werte (nur lesend) |
| `FO48UControl --writetest` | schreibt Helligkeit ±10 mit Rücklesen und stellt sie zurück |
| `FO48UControl --inputtest` | schaltet kurz auf DisplayPort und zurück auf USB-C (Bild fällt kurz aus) |
| `FO48UControl --autostart [on\|off]` | Anmeldeobjekt setzen oder Status zeigen |

## Hinweise

- Die App nutzt die **private Apple-API `IOAVService`**. Sie ist nicht App-Store-tauglich und kann mit einem macOS-Update brechen.
- Der Eingangswechsel auf HDMI/DisplayPort nimmt dem Mac das Bild, bis wieder USB-C gewählt ist.
- Es werden nur die hier dokumentierten Befehle gesendet. Firmware-Flash-Funktionen des Herstellers sind bewusst nicht umgesetzt.
- Getestet nur mit einem FO48U (Firmware F06, Deutung siehe Protokoll) an einem Apple-Silicon-Mac. Andere Monitore und Mac-Modelle sind ungeprüft.
- Eagle Eye und Night Vision werden vom Monitor nicht angenommen und fehlen deshalb im Menü.

## Dokumentation

- [`docs/PROTOKOLL.md`](docs/PROTOKOLL.md): DDC/CI-Protokoll, Sub-IDs, Messwerte, Belegstufen (`[Dekompilat]`, `[gemessen]`, `[ungeprüft]`)
- [`STATUS.md`](STATUS.md): Stand, Entscheidungen, nächste Schritte
- [`CLAUDE.md`](CLAUDE.md): Projektregeln für die Arbeit mit Claude Code

## Herkunft des Protokolls

Das Protokoll wurde aus dem öffentlich erhältlichen Gigabyte-Installer (Sidekick, .NET-Assemblies) per Analyse für Interoperabilität gewonnen und am eigenen Gerät nachgemessen. Der Repository-Inhalt enthält **keine** Gigabyte-Binaries, Dekompilate oder Konfigurationsdateien; diese liegen lokal unter `_analyse/` und sind von Git ausgeschlossen.

## Lizenz

[MIT](LICENSE)
