# Funktionen und Prüfstand

Stand 2026-10-30. Geprüft wurde bisher **nur ein AORUS FO48U** (Firmware F06, Deutung siehe `docs/PROTOKOLL.md`, Abschnitt „Sub-IDs für `0xE0`“) per USB-C (DisplayPort-Alt-Mode) an einem Apple-Silicon-Mac. Alle anderen Monitore, Anschlüsse und Mac-Modelle sind ungeprüft.

Belegstufen: **Lesen** = Wert vom Monitor abgefragt und plausibel; **Schreiben** = Wert gesetzt und vom Monitor zurückgelesen (`Monitor.write`); **Menü** = in der Menüleisten-App bedient. Antworten werden auf Sub-ID, Länge und Prüfsumme geprüft. Die Schreibtests von Schärfe, Farbtemperatur, Gamma, Aim Stabilizer, Refresh-Anzeige und Fadenkreuz liefen vor dieser Prüfung; mit ihr wurden nur Helligkeit und Eingang erneut getestet. Nichts davon ist am Monitor-OSD gegengelesen, soweit nicht anders vermerkt.

## Im Menü enthalten

| Funktion | Lesen | Schreiben | Anmerkung |
|---|---|---|---|
| Helligkeit | ja | ja (`--writetest`, 75→65→75) | |
| Kontrast, Lautstärke | ja | nicht einzeln geprüft | |
| Schärfe (0–10) | ja | ja | |
| Black eQualizer (0–20) | ja | nicht einzeln geprüft | |
| Bildmodus | ja | ja (Zielwert stand am Ende, ein Rücksetzlauf war inkonsistent) | Namen aus Dekompilat |
| Eingang | ja | ja (`--inputtest` und Menü, Umschalten bestätigt) | Wechsel weg von USB-C nimmt dem Mac das Bild |
| OverDrive | ja | ja | Stufennamen ungeprüft |
| Gamma | ja | ja | Zuordnung 1.8 … 2.6 am OSD ungeprüft |
| Farbtemperatur | ja | ja | nur Kalt/Normal/Warm benannt; Stufen 3 und 4 ungeprüft |
| Fadenkreuz, Aim Stabilizer, Refresh-Anzeige | ja | ja | |
| FreeSync | ja | nicht einzeln geprüft | |
| Autostart beim Anmelden | n. a. | `--autostart on` meldet „an“ | Start nach Neuanmeldung ungeprüft |

## Nicht im Menü

| Funktion | Grund |
|---|---|
| Eagle Eye, Night Vision, OSD-Größe | Der Monitor beantwortet diese Abfragen nicht (liefert nur ein Echo der vorherigen Antwort). Ob der FO48U sie unterstützt, ist offen; Details in `docs/PROTOKOLL.md`. |
| PIP/PBP, OSD-Größe, KVM, Timer | bewusst nicht aufgenommen, ungeprüft |
| RGB-Verstärkung, Farbsättigung, HDR, Local Dimming u. a. | Sub-IDs stehen in `docs/PROTOKOLL.md`, am FO48U nicht geprüft, ob unterstützt |

## Bekannte Grenzen

- Nutzt die private Apple-API `IOAVService`: nicht App-Store-tauglich, kann mit macOS-Updates brechen.
- Die App ist nicht notarisiert (ad-hoc signiert).
- Menü-Klickbedienung: Quellenwechsel und Regler sind vom Entwickler von Hand geprüft; die übrigen Menüelemente sind nur über die Kernschicht (`--selftest`, `--writetest`) belegt.
