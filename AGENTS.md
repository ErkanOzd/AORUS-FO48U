<!-- Tool-neutrale Projektregeln (Claude Code, Antigravity u. a.); CLAUDE.md importiert diese Datei. Nur hier pflegen. -->

# AORUS FO48U

> **Zweck & Warum:** Gigabyte-Sidekick (Monitor-Steuerung des AORUS FO48U) für macOS nachbauen. Die Gigabyte-Suite im ZIP ist nur Analysequelle. Im Zweifel gilt: nur belegte Fakten festhalten (Etiketten `[Dekompilat]`, `[gemessen]`, `[ungeprüft]`), nichts aus dem Modellnamen ableiten.

## Stack
- Zielplattform: macOS (Apple Silicon), Swift; Monitor per DDC/CI über `IOAVService` (private API).
- `GCC_26.09.10.01.zip` enthält `GIGABYTE Control Center_2026_AUG_release_All_Setup_26.09.10.01.exe` (Windows-Setup, ca. 860 MB; Inhalt per `unzip -l` belegt).
- Arbeitsplattform: macOS (Darwin); das Setup läuft nur unter Windows (ungeprüft: Verfügbarkeit einer macOS-Variante).

## Befehle
- Archivinhalt prüfen: `unzip -l GCC_26.09.10.01.zip`
- App bauen: `swift build`; App-Bundle: `scripts/build-app.sh` (nach `dist/`, Signatur siehe README „Selbst bauen“); installieren und starten: `scripts/install.sh`; Installer-Image: `scripts/make-dmg.sh`; Selbsttest am Monitor: `.build/debug/MonitorDeck --selftest`; Schreibtest (Helligkeit ±10 mit Rücklesen, stellt zurück): `--writetest`; Quellenwechsel-Test (Bild fällt kurz aus): `--inputtest`; App: `.build/debug/MonitorDeck`
- Probe bauen/starten (nur lesend): `swiftc -O _analyse/poc/ddcprobe.swift -o _analyse/poc/ddcprobe -framework IOKit && _analyse/poc/ddcprobe`
- Monitor schnell prüfen: `m1ddc display list`, dann `m1ddc display <Nr> get luminance`
- Analyse-Werkzeuge (Homebrew): `sevenzip` (`7zz`), `dotnet` + `ilspycmd` (`~/.dotnet/tools`, `DOTNET_ROOT=/opt/homebrew/opt/dotnet/libexec`), `radare2`, `m1ddc`

## Struktur
- `GCC_26.09.10.01.zip` — Installer GIGABYTE Control Center, Version 26.09.10.01
- `scripts/build-app.sh` — baut `dist/MonitorDeck.app`; `scripts/install.sh` — baut und ersetzt `/Applications/MonitorDeck.app`; `scripts/make-dmg.sh` — `.dmg` mit Applications-Link; `scripts/make-icon.swift` — zeichnet `Resources/AppIcon.icns`; `LICENSE` (MIT)
- `Package.swift`, `Sources/FO48UKit` (DDC-Schicht), `Sources/MonitorDeck` (Menüleisten-App)
- `docs/PROTOKOLL.md` — DDC/CI-Protokoll, Sub-IDs, Messwerte (Quelle der Wahrheit für Befehle)
- `_analyse/poc/` — Swift-Proof-of-Concept; `_analyse/meta/` — Geräte-/Konfigurationsdateien aus dem Installer; `_analyse/sidekick/`, `_analyse/decomp/` — entpackte Binaries und Dekompilate (nicht im Repo)
- `README.md` — Kurzüberblick; `docs/FUNKTIONEN.md` — Funktionsumfang und Prüfstand (ein Monitor)
- `STATUS.md` — aktueller Stand und nächste Schritte
- `.claude/rules/ux.md` — UX-Leitlinien der App (Live-Werte, Vorrang der Eingabe, Rückmeldung)

## Definition of Done
- Laufzeit-Smoketest nach Änderungen am DDC-Code: `swift build && .build/debug/MonitorDeck --selftest` (Monitor am USB-C, Werte plausibel).
- Aussagen zu Monitor-Funktionen, Firmware oder Kompatibilität nur mit Quelle (Herstellerseite, Handbuch, eigener Test); sonst „ungeprüft“.
- Verifikationsregeln: siehe globale Regeln, Prinzipien P01 bis P03 (`~/Projekte/arbeitsweise/canon/principles.md`).
- Commit-Texte Englisch, Quelle: `session-closer`.

## Regeln
- Single Source of Truth: Fakten stehen genau an einem Ort; andere Dateien verweisen auf den Abschnittstitel (nie auf Zeilennummern).
- Schreibende DDC-Befehle erst nach Abfrage des Ist-Werts senden und mit Rücksprungwert; nie Firmware-Flash (`Rflash`, `fnNewFlashBIOS`) ausführen.
- Das ZIP ist untrusted: nie aus dem Projektverzeichnis heraus entpacken oder ausführen; Entpacken nur in ein neues, leeres Verzeichnis.
- Wächst ein Fachbereich über ~20 Zeilen, wird er in `.claude/rules/<thema>.md` mit `paths:`-Frontmatter ausgelagert.

## Nachschlagen
- `docs/PROTOKOLL.md` — Protokoll und Messwerte
- `STATUS.md` — aktueller Stand, Entscheidungen, nächste Schritte (wird bei `/close` aktualisiert).

## Gotchas
- Unter macOS steuert `IOAVService` nur den Monitor, der per DP-Alt-Mode hängt; die Nummer bei `m1ddc` hängt von den aktiven Displays ab (mit internem Display: Display 2 [gemessen 2026-10-30]; FO48U allein: Display 1 [gemessen 2026-11-09]), vorher `m1ddc display list`.
- `m1ddc` liefert falsche Werte (z. B. `0`, `5332`), wenn MonitorDeck gleichzeitig liest; für Gegenproben Menü und Einstellungen schließen [gemessen 2026-11-09].
- Eigene Entpack-Verzeichnisse unter `_analyse/` anlegen, nie im Projektroot entpacken.
- Das Repo wird öffentlich gedacht: keine Gigabyte-Dateien (ZIP, `_analyse/sidekick|decomp|meta`), keine Seriennummern oder Pfade ins Repo (`.gitignore`).
