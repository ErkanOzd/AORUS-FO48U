# Funktionen und Prüfstand

Stand 2026-11-03. Geprüft wurde bisher **nur ein AORUS FO48U** (Firmware vermutlich F06; Deutung, siehe `docs/PROTOKOLL.md`, Abschnitt „Sub-IDs für `0xE0`“) per USB-C (DisplayPort-Alt-Mode) an einem Apple-Silicon-Mac. Alle anderen Monitore, Anschlüsse und Mac-Modelle sind ungeprüft.

Belegstufen: **Lesen** = Wert vom Monitor abgefragt und plausibel; **Schreiben** = Wert gesetzt und vom Monitor zurückgelesen (`Monitor.write`); **Menü** = in der Menüleisten-App bedient. Antworten werden auf Sub-ID, Länge und Prüfsumme geprüft. Die Schreibtests von Schärfe, Farbtemperatur, Gamma, Aim Stabilizer, Refresh-Anzeige und Fadenkreuz liefen vor dieser Prüfung; mit ihr wurden nur Helligkeit und Eingang erneut getestet. Nichts davon ist am Monitor-OSD gegengelesen, soweit nicht anders vermerkt.

## Bedienung

Die Menü-Kopfzeile zeigt „Verbunden · <aktiver Eingang>“ (aus VCP 0x60); der Tab Allgemein zeigt zusätzlich die Zeile „Verbindung“. Das Menü zeigt immer Lautstärke (mit Stumm), Helligkeit, Kontrast und Schärfe. Alle anderen Einstellungen liegen im Einstellungsfenster (⌘,) in den Tabs Bild, Gaming, Mac und Allgemein; in Bild und Gaming lässt sich jede Einstellung per Pin zusätzlich im Menü anzeigen (Standard: nichts angepinnt; gespeichert in den Benutzer-Vorgaben). Menü und Einstellungen (Karten, 44-pt-Zeilen, Pin je Zeile, Systemfarben) am 2026-11-03 gegen den Design-Entwurf abgenommen; Aufbau am Test-Mac mit Screenshot geprüft (Menü, Tab Bild, Pin an/aus gespeichert); Funktionen anderer Tabs und Pins auf Gaming-Einträge einzeln ungeprüft.

## Im Menü bzw. in den Einstellungen

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
| Fadenkreuz, Aim Stabilizer, Refresh-Anzeige | ja | ja | Fadenkreuz als Ein/Aus-Schalter (Motive 1–4 sind laut Nutzer identisch); Ein schreibt 1 |
| FreeSync | ja | nicht einzeln geprüft | |
| Systemwerte im Dashboard | n. a. | ja: CPU-/GPU-Last und SoC-Temperatur alle 2 s; Sichtprüfung am Monitor bestätigt (MacBook Air M5) | Takt/Lüfter nicht lesbar und am Monitor ausgeblendet; Macs mit Lüfter ungeprüft |
| Tasten steuern Monitor | n. a. | ja: Helligkeits- und Lautstärketasten (Schritt 1–10, getrennt für Helligkeit und Lautstärke, im Tab „Mac“ der Einstellungen (⌘,), Standard 5; Stumm = 0 und zurück; Helligkeitstasten wählbar: „Systemtasten“ mit Sonnen-Symbol (Standard, fängt Medientasten und F14 / F15 ab) oder Medientasten), Helligkeit nur wenn der Mauszeiger auf dem Monitor steht, Lautstärke und Stumm unabhängig von der Mausposition, aber nur, wenn die Standard-Tonausgabe des Macs der Monitor ist (sonst gehen die Tasten an macOS, das Menü zeigt „Ton läuft über …“); jede Taste zeigt ein eigenes OSD (siehe „Tonausgabe und OSD“); mit echten Tasten bestätigt (2026-11-03, MacBook Air, ein FO48U), Kopplung an die Tonausgabe, Stumm-Wiederherstellung und OSD mit simulierten Tastenereignissen belegt (2026-11-09: Ausgabe FO48U 0 → 5 → Stumm 0 → 5 → 0; Ausgabe MacBook-Lautsprecher: Mac-Lautstärke änderte sich, Monitor nicht) | Berechtigung „Bedienungshilfen“ nötig (Erststart-Abfrage fragt einmal, sonst Schalter im Tab „Mac“); Notebook-Display-Verhalten nicht einzeln geprüft; bei ad-hoc-Signatur muss die Berechtigung nach jedem Neubau neu erteilt werden, mit Zertifikat „Apple Development“ nicht (README, „Selbst bauen“) |
| Autostart beim Anmelden | n. a. | `--autostart on` meldet „an“ | Start nach Neuanmeldung ungeprüft |


## Tonausgabe und OSD

Der FO48U erscheint am Mac als eigenes Audiogerät (Name „AORUS FO48U“, Hersteller „GBT“, Anschluss DisplayPort) ohne Lautstärke- und Stummregelung; macOS kann seinen Ton also nicht selbst regeln [gemessen 2026-11-09, CoreAudio]. Die Geräte-UID beginnt mit Display-Hersteller und -Modell (`1C540048…` bei Modell `0x4800`, Bytes vertauscht; ein Gerät geprüft); daran erkennt die App, ob der Ton über den Monitor läuft (`AudioOutput.isMonitor`). Das Umschalten der Tonausgabe auf den Monitor und zurück lässt das Display nicht aussetzen (gemessen über je 15 s).

Das System-OSD steht für den Monitor nicht zur Verfügung: Unter macOS 27.2 zeichnet das Kontrollzentrum das OSD (Regler oben rechts), die ältere private Schnittstelle `OSDManager` nimmt Aufrufe an, zeigt aber nichts (3 Versuche mit Bildschirmaufnahme). Die App zeigt deshalb ein eigenes OSD im gleichen Stil (Glas-Kapsel oben rechts auf dem Monitor, 16 Segmente; Maße, Farben und Symbolgrenzen am System-OSD vermessen und pixelgenau angeglichen, Werte im Kopfkommentar von `OSD.swift`): sofort mit dem erwarteten Wert, wenn ein höchstens 10 s alter Wert bekannt ist, danach mit dem vom Monitor bestätigten [Sichtprüfung per Bildschirmaufnahme 2026-11-09].

## Nicht im Menü

| Funktion | Grund |
|---|---|
| Eagle Eye, Night Vision, OSD-Größe | Der Monitor beantwortet diese Abfragen nicht (liefert nur ein Echo der vorherigen Antwort). Ob der FO48U sie unterstützt, ist offen; Details in `docs/PROTOKOLL.md`. |
| PIP/PBP, KVM, Timer | bewusst nicht aufgenommen, ungeprüft |
| RGB-Verstärkung, Farbsättigung, HDR, Local Dimming u. a. | Sub-IDs stehen in `docs/PROTOKOLL.md`, am FO48U nicht geprüft, ob unterstützt |

## Bekannte Grenzen

- Nutzt die private Apple-API `IOAVService`: nicht App-Store-tauglich, kann mit macOS-Updates brechen.
- Die App ist nicht notarisiert (Release-Image ad-hoc signiert).
- Menü-Klickbedienung: Quellenwechsel und Regler sind vom Entwickler von Hand geprüft; die übrigen Menüelemente sind nur über die Kernschicht (`--selftest`, `--writetest`) belegt.
