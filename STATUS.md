# Status – AORUS FO48U

**Stand:** 2026-11-09 · **Version:** 0.2.4 (Beta, Pre-release)

## Aktueller Fokus / Phase
- Ziel: Gigabyte-Sidekick (Monitor-Steuerung) für macOS nachbauen. Die Gigabyte-Suite im ZIP dient nur als Analysequelle.
- Phase 1 (Analyse) abgeschlossen, Phase 2 läuft: Lesen und Schreiben am echten Monitor belegt, Menüleisten-App `MonitorDeck` im Beta-Stand. Protokoll: `docs/PROTOKOLL.md`; Funktionsumfang und Prüfstand: `docs/FUNKTIONEN.md`.

## Monitor-Fakten (Quelle: `ioreg`/`system_profiler`/CoreGraphics am Mac, 2026-10-30)
- Modell AORUS FO48U, Hersteller-ID `GBT`, Baujahr 2022 (Woche 7).
- Anschluss: USB-C, DisplayPort 1.4 (DP-Alt-Mode), EDID komplett in `ioreg`.
- Bild: 70 × 39 cm (48 Zoll, 16:9), nativ 3840 × 2160, Refresh laut EDID 24–120 Hz.
- macOS-Modi: bei 4K nur 60 und 24 Hz (alle Skalierungen); 120 Hz nur bis 2560 × 1440. EDID `MaxTotalPixelRate` 594 MHz (4K60). Ursache offen (Kabel, Port oder EDID, nicht getrennt getestet).
- USB-Seite: Realtek-HID-Gerät VID `0x0BDA` / PID `0x1100` am Mac sichtbar (Vendor-Usage-Page `0xFFDA`, 192-Byte-Reports). Für die Steuerung nicht nötig.

## Zuletzt erledigt
- Protokoll geklärt (DDC/CI, Standard-VCP plus herstellerspezifisch `0xE0` mit Sub-ID), Schreiben mit Rücklesen am Monitor belegt: `docs/PROTOKOLL.md`. Tests: `--selftest`, `--writetest`, `--inputtest` (Eingangswechsel USB-C → DisplayPort → USB-C, Rückschalten nach 7 Versuchen / ca. 7 s, belegt).
- App `MonitorDeck` (`FO48UKit` + Menüleisten-App), Icon, `scripts/build-app.sh`, `scripts/make-dmg.sh`; Repo öffentlich vorbereitet (MIT, keine Gigabyte-Dateien, keine Seriennummer); Umbenennung von „Sidekick“ zu „MonitorDeck“ (Executable, Targets, Bundle-ID und Repo-Name unverändert). Zweisprachige Oberfläche (`tr(de, en)`), am Bildschirm in beiden Sprachen belegt.
- Review-Blocker vom 2026-10-30 (Zielmonitor-Wahl, DDC-Queue, `WriteResult`, Antwortprüfung) behoben, Details im Git-Log.
- Dashboard-Feed (CPU/GPU/SoC-Temperatur): Sichtprüfung vom Nutzer bestätigt (2026-10-30, ein Mac ohne Lüfter); Details `docs/PROTOKOLL.md`, Abschnitt „Dashboard“.
- Release 0.2.0 (2026-11-03): Menü und Einstellungen nach Canvas-Entwurf neu aufgebaut, vom Nutzer abgenommen.
- 0.2.1: Erststart-Abfrage „Helligkeits- und Lautstärketasten nutzen?“ (`askKeysOnce`, löst „Bedienungshilfen“ aus; vorher fragte die App nie), Auswahl „Systemtasten“.
- 0.2.2: „Systemtasten“ fängt Nx und F14/F15 ab (die interne Tastatur sendet Helligkeit als Nx-Code 2/3, eine andere Tastatur als F14/F15, Keycode 107/113 [gemessen 2026-11-03]; erste Quelle zählt, 60 ms); Zahnrad in der Menü-Kopfzeile entfernt.
- 0.2.3: Steuerung startet selbst, sobald „Bedienungshilfen“ erteilt ist (1-s-Timer).
- 0.2.4: Fadenkreuz nur Ein/Aus (Motive 1–4 identisch laut Nutzer, schreibt 1); Lautstärke und Stumm unabhängig von der Mausposition, Helligkeit nur bei Zeiger auf dem Monitor; keine Standard-Pins.
- Live-Werte (2026-11-09, noch ohne Versionsnummer): Menü und Einstellungen lesen beim Öffnen sofort und danach laufend (1 s Pause), geschlossen gar nicht; Ziehen eines Reglers wird nicht überschrieben. Knöpfe „Neu lesen“ und „Erneut suchen“ entfallen. Belegt am Monitor (Helligkeit extern geändert, Menü zog nach; `sample` zeigt keine DDC-Zugriffe bei geschlossenem Menü). UX-Leitlinien: `.claude/rules/ux.md`.
- Lautstärke-/Stummtasten nur bei Tonausgabe über den Monitor, sonst regelt macOS; eigenes OSD für Helligkeit und Lautstärke (System-OSD für DDC-Monitore nicht nutzbar). Belegt mit simulierten Tasten und Bildschirmaufnahmen (2026-11-09), Details `docs/FUNKTIONEN.md`, Abschnitt „Tonausgabe und OSD“.
- Unverifiziert: Tastenwirkung der Versionen 0.2.2–0.2.4 am Bildschirm, Stumm-Wiederherstellung, Autostart nach Neuanmeldung (Klick auf „Beim Anmelden starten“), Klickbedienung der Tabs Gaming/Mac/Allgemein.

## Nächste Schritte (priorisiert)
1. Offene Prüfpunkte abarbeiten: `docs/FUNKTIONEN.md`, Abschnitt „Nicht im Menü“ und Prüfstand; Gamma/Farbtemperatur am OSD gegenlesen.
2. Eingangswechsel mit Vorsicht testen: Wechsel weg von USB-C trennt das Bild des Macs.
3. Prüfen, ob Timer, KVM oder PIP/PBP nur über das USB-HID-Gerät laufen.

## Entscheidungen / Blocker
- Notarisierung entfällt wegen privater API. Lokale Builds signiert `build-app.sh` mit „Apple Development“, falls vorhanden (Signatur-Anforderung = Bundle-ID + Zertifikat; die Freigabe „Bedienungshilfen“ überstand einen Neubau mit geänderter Binärdatei [gemessen 2026-11-09, aktiver Event-Tap ohne neue Freigabe]); Release-Image bleibt ad-hoc, damit kein persönliches Zertifikat im Download steckt. Das Zurücksetzen von TCC-Freigaben sperrt der globale Hook `ops-guard.sh`; `install.sh` öffnet stattdessen die Seite „Bedienungshilfen“.
- `IOAVService` ist eine private Apple-API: nicht App-Store-tauglich, kann mit macOS-Updates brechen.
