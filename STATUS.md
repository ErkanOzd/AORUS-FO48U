# Status – AORUS FO48U

**Stand:** 2026-10-30

## Aktueller Fokus / Phase
- Ziel: Gigabyte-Sidekick (Monitor-Steuerung) für macOS nachbauen. Die Gigabyte-Suite im ZIP dient nur als Analysequelle.
- Phase 1 (Analyse) abgeschlossen, Phase 2 begonnen: Lesen und Schreiben am echten Monitor belegt, Menüleisten-App `MonitorDeck` läuft. Details: `docs/PROTOKOLL.md`.

## Monitor-Fakten (Quelle: `ioreg`/`system_profiler`/CoreGraphics am Mac, 2026-10-30)
- Modell AORUS FO48U, Hersteller-ID `GBT`, Baujahr 2022 (Woche 7).
- Anschluss: USB-C, DisplayPort 1.4 (DP-Alt-Mode), EDID komplett in `ioreg`.
- Bild: 70 × 39 cm (48 Zoll, 16:9), nativ 3840 × 2160, Refresh laut EDID 24–120 Hz.
- macOS-Modi: bei 4K nur 60 und 24 Hz (alle Skalierungen); 120 Hz nur bis 2560 × 1440. EDID `MaxTotalPixelRate` 594 MHz (4K60). Ursache offen (Kabel, Port oder EDID, nicht getrennt getestet).
- USB-Seite: Realtek-HID-Gerät VID 3034 / PID 4352 am Mac sichtbar (Vendor-Usage-Page `0xFFDA`, 192-Byte-Reports). Für die Steuerung nicht nötig.

## Zuletzt erledigt
- Protokoll geklärt: DDC/CI (`0x6E`/`0x51`), Standard-VCP plus herstellerspezifisch `0xE0` mit Sub-ID; Wertetabellen für Bildmodus, Eingang und Schalter aus dem Dekompilat gezogen (`docs/PROTOKOLL.md`).
- Schreibzugriff belegt: Helligkeit und OverDrive gesetzt, zurückgelesen, Ausgangswert wiederhergestellt.
- Swift-Package `MonitorDeck`: `FO48UKit` (DDC über `IOAVService`) und Menüleisten-App (Funktionsumfang: `docs/FUNKTIONEN.md`). Schreiben nur über Bindings, nicht beim Neulesen. Bedienung im Menü vom Nutzer bestätigt (2026-10-30).
- `Monitor.write` liest nach jedem Schreiben zurück (bis 3 Versuche) und sucht den DDC-Dienst bei Fehlschlag neu (nach Quellenwechsel). `--writetest` belegt das für Helligkeit (75→65→75, bestätigt). `--inputtest` (USB-C → DisplayPort → USB-C, nur Kernschicht): Rückschalten gelang nach 7 Versuchen (~7 s) über dieselbe `Monitor`-Instanz, Eingang danach 3 (belegt). Quellenwechsel über die Menü-UI: vom Nutzer geprüft, Regler funktionieren danach weiter (Stand 2026-10-30).
- Erststart-Abfrage „Beim Anmelden starten?“ (`askAutostartOnce`, einmalig per `UserDefaults`; Dialog am Bildschirm belegt, Klick auf „Beim Anmelden starten“ unverifiziert).
- App-Icon (`Resources/AppIcon.icns`, gezeichnet per `scripts/make-icon.swift`: Monitor mit drei farbigen Reglern) und `scripts/make-dmg.sh` (DMG mit Applications-Link, Signatur im gemounteten Image geprüft; Installation per Ziehen unverifiziert, Release auf GitHub noch nicht angelegt).
- `scripts/build-app.sh` baut `dist/MonitorDeck.app` (LSUIElement, ad-hoc signiert); aus `~/Applications` gestartet läuft sie ohne Dock-Symbol (belegt). Autostart über `SMAppService`: `--autostart on` meldet „an“ (belegt); tatsächlicher Start nach Neuanmeldung unverifiziert.
- Repo für Veröffentlichung vorbereitet (MIT-Lizenz, README, keine Gigabyte-Dateien, keine Seriennummer).
- OverDrive-Stufen 0–4 = Aus, Smart OD, Bildqualität, Ausgewogen, Geschwindigkeit (Namen aus `OSD.cs`, Anzahl passt zu max 4, Zuordnung ungeprüft); Gamma/Farbtemperatur: Namen aus `OSD.cs` (siehe `docs/PROTOKOLL.md`), am OSD noch nicht gegengelesen.
- Menü: Eingangswechsel weg von USB-C fragt nach; Picker bieten alle gemeldeten Stufen (unbenannte als „Stufe N“); Regler ohne gelesenen Wert sind deaktiviert; Schreiben liest vorher den Ist-Wert und springt bei Ablehnung zurück (Build ok, `--selftest`/`--writetest` belegt; vom Nutzer in der UI bestätigt, 2026-10-30: Popover öffnet, Rückfrage beim Eingangswechsel erscheint, Picker zeigen die Stufen, Zurückschalten auf USB-C über das Menü gelingt. Nicht geprüft: Verhalten bei Wahl von „Abbrechen“ und die Stufe-N-Anzeige für unbenannte Werte einzeln).
- Oberfläche zweisprachig (`tr(de, en)` in `FO48UKit`, Systemsprache; Englisch als Fallback): Build und `--selftest` in beiden Sprachen belegt (`-AppleLanguages`); am Bildschirm (Release-Build, `-AppleLanguages "(en)"`) belegt: Popover, Beschriftungen, Picker Bildmodus („Level 9“ für die unbenannte Stufe) und Eingang (Liste) und Eingangs-Dialog („Switch input to HDMI 1?“, „Cancel“ lässt USB-C stehen; `--selftest` danach: Eingang 3/3). „Switch“ in englischer UI nicht ausgelöst.
- Menü (früher): Schärfe, Farbtemperatur, Fadenkreuz, Aim Stabilizer, Refresh-Anzeige; Schreiben mit Rücklesen am Monitor belegt. Eagle Eye/Night Vision nicht im Menü (Monitor beantwortet die Abfrage nicht, siehe `docs/PROTOKOLL.md`). PIP/PBP, OSD-Größe, KVM bewusst nicht aufgenommen (ungeprüft).
- Entpackte Gigabyte-Dateien (ca. 1,7 GB) gelöscht, `_analyse/sidekick` (96 MB) bleibt; alles aus dem ZIP reproduzierbar. Keine Windows-VM nötig gewesen.

- Review-Blocker behoben (2026-10-30): Zielmonitor-Wahl mit Pfad-Bindung bei Neu-Suche (K1, nur mit einem Monitor getestet), DDC auf eigener Queue und Slider schreiben beim Loslassen (K2), `WriteResult` statt „Erfolg bei fehlendem Rücklesen“ (H1), Antwortprüfung auf Sub-ID und Prüfsumme (H2). `--writetest` und `--inputtest` liefen erfolgreich; Slider-Ziehen in der UI vom Nutzer bestätigt („Regler funktionieren“, 2026-10-30). Offen aus dem Review: Mittel- und Niedrig-Befunde.
- App umbenannt in „MonitorDeck“ (generischer, vermeidet „Sidekick“ als Gigabyte-Produktname); Executable, Swift-Targets, Bundle-ID und Repo-Name unverändert. `docs/FUNKTIONEN.md` legt Funktionsumfang und Prüfstand offen; README lädt zum Testen mit anderen AORUS-Modellen ein.

## Nächste Schritte (priorisiert)
1. Gamma (1.8…2.6) und Farbtemperatur (Kalt/Normal/Warm) am Monitor-OSD gegenlesen; Eagle Eye/Night Vision: klären, ob der FO48U sie überhaupt hat.
2. Weitere Funktionen prüfen (PIP/PBP, OSD-Größe, KVM, Timer).
3. Eingangswechsel mit Vorsicht testen: Wechsel weg von USB-C trennt das Bild des Macs.
4. Funktionsumfang festlegen (Crosshair, Timer, KVM, PIP/PBP?) und prüfen, ob davon etwas nur über das USB-HID-Gerät läuft.
5. Notarisierung entfällt wegen privater API (ad-hoc signiert).

## Offene Entscheidungen / Blocker
- Gewünschter Funktionsumfang des Nachbaus.
- `IOAVService` ist eine private Apple-API: nicht App-Store-tauglich, kann mit macOS-Updates brechen.
