# Sidekick-Protokoll (AORUS FO48U)

Belegetiketten: **[Dekompilat]** aus GCC 26.09.10.01 / Sidekick 26.08.04.01 (lokal erzeugt unter `_analyse/decomp`, nicht im Repo; `RTKCmd_x64.dll`, `RtHIDlib.dll`), **[gemessen]** am Mac mit `_analyse/poc/ddcprobe.swift` (2026-10-30; `settest` schreibt), **[ungeprüft]** weder gemessen noch belegt.

## Kernaussage
Der Sidekick steuert den FO48U per DDC/CI (I²C-Adresse `0x6E`, Quelle `0x51`). Unter Windows läuft das über ein Realtek-USB-HID-Gerät (VID `0x0BDA`, PID `0x1100`, Vendor-Usage-Page `0xFFDA`, 192-Byte-Reports ohne Report-ID) [Dekompilat; HID-Gerät am Mac per `ioreg` sichtbar]. Am Mac braucht es das nicht: DDC/CI über die DisplayPort-Verbindung (`IOAVService`, Chip `0x37`, Offset `0x51`) beantwortet dieselben Befehle [gemessen].

## Befehle
Paket Mac-Seite (`IOAVServiceWriteI2C`, Chip `0x37`, Offset `0x51`): `[0x80|n, Payload…, Prüfsumme]`, Prüfsumme = `0x6E ^ 0x51 ^` alle Bytes davor [gemessen: Antworten kommen].

| Zweck | Payload |
|---|---|
| Standard-VCP lesen | `01 <vcp>` |
| Standard-VCP setzen | `03 <vcp> 00 <wert>` |
| Herstellerspezifisch lesen | `01 E0 <sub>` |
| Herstellerspezifisch setzen | `03 E0 <sub> 00 <wert>` [Dekompilat; Schreiben gemessen, siehe „Schreiben samt Rücklesen“] |

Antwort (`6E 88 02 00 <vcp> <typ|sub> <maxHi> <maxLo> <curHi> <curLo> <chk>`): Beispiel Helligkeit `… 10 00 00 64 00 4B` = Maximum 100, aktuell 75 [gemessen]. Bei `0xE0` steht die Sub-ID an der Typ-Stelle; die Lesart `max`/`cur` ist aus den Messwerten abgeleitet, nicht aus dem Code belegt (Firmware `0x38` liefert `FF FF 46 06`, Deutung siehe Tabelle `0x38`).

Unterschied Windows-Pfad: Im Dekompilat der HID-Variante wird die Prüfsumme ohne `0x6E` gebildet (`51^84^03^10`), die Brücke ergänzt vermutlich die Adresse [Dekompilat, ungeprüft]. Für den Mac-Weg gilt die Standardform oben.

## Standard-VCP-Codes des Sidekick [Dekompilat]
`0x10` Helligkeit, `0x12` Kontrast, `0x62` Lautstärke, `0x87` Schärfe.

## Gemessene Werte FO48U [gemessen]
| Sub / VCP | Funktion | max | aktuell |
|---|---|---|---|
| `0x10` | Helligkeit | 100 | 75 |
| `E0/09` | OverDrive | 4 | 0 |
| `E0/07` | Gamma | 5 | 3 |
| `E0/02` | Black eQualizer | 20 | 11 |
| `E0/03` | Farbtemperatur | 4 | 0 |
| `E0/2D` | Eingang | 3 | 3 |
| `E0/2C` | Bildmodus | 9 | 4 |
| `E0/0C` | FreeSync | 1 | 0 |

`m1ddc display 2 get …` bestätigt Helligkeit 75, Kontrast 60, Eingang 16, Lautstärke 8 [gemessen]. `m1ddc` zeigt für USB-C den Rohwert 16, der Herstellerbefehl `E0/2D` liefert 3; die Zuordnung ist nicht weiter untersucht.

## Schreiben und Werte
Schreiben getestet (Helligkeit 75→80→75, OverDrive 0→1→0, jeweils zurückgelesen und wiederhergestellt) [gemessen]. Die Windows-Pakete tragen als letztes Byte die Prüfsumme ohne `0x6E` (`51^85^03^E0^sub^00^wert`); am Mac gilt die Standardform mit `0x6E` [Dekompilat / gemessen].

Wertetabellen (Gigabyte-Variante, FO48U hat `AOR_GBT_Flag = 0`) [Dekompilat; Eingang Type-C passt zur gemessenen `3`]:

| Sub | Funktion | Werte |
|---|---|---|
| `0x2C` | Bildmodus | 0 Standard, 1 FPS, 2 RTS/RPG, 3 Film, 4 Lesen, 5 sRGB, 6 Custom 1, 7 Custom 2, 8 Custom 3 |
| `0x2D` | Eingang | 0 HDMI 1, 1 HDMI 2, 2 DisplayPort, 3 USB-C |
| `0x0C` | FreeSync | 0 aus, 1 an |
| `0x0A` | Aim Stabilizer | 0 aus, 1 an |
| `0x37` | Fadenkreuz | 0 aus, 1–4 Motiv |
| `0x22` | Bildwiederholrate einblenden | 0 aus, 1 an |
| `0x39` | Eagle Eye | 0 aus, 1 an |
| `0x49` | Night Vision | 0 aus, 1 an |
| `0x0E` | PIP/PBP | 0 aus, 1 PIP, 2 PBP |
| `0x3A` | OSD-Größe | 1 = 1×, 2 = 2× |
| `0x69` | KVM | 0 = B, 1 = C (Zuordnung ungeprüft) |
| `0x07` | Gamma (max 5) | 0 Aus, 1 = 1.8, 2 = 2.0, 3 = 2.2, 4 = 2.4, 5 = 2.6 [Dekompilat: `OSD.cs`, Default-Zweig, da `ext & 0xF == 0` für `FO48U`]; Zuordnung am OSD ungeprüft |
| `0x03` | Farbtemperatur (max 4) | 0 Kalt, 1 Normal, 2 Warm [Dekompilat: `OSD.cs`, Zweig ohne Flag `0x40`]; 3 und 4 im Sidekick nicht benannt (ungeprüft) |
| `0x87` | Schärfe (Standard-VCP) | 0–10 [gemessen: max 10] |
| `0x09` / `0x02` | OverDrive / Black eQ | Stufen 0…max aus der Abfrage; Namen der Stufen ungeprüft |

Schreiben samt Rücklesen [gemessen 2026-10-30]: Schärfe, Farbtemperatur, Gamma, Aim Stabilizer, Refresh-Anzeige und Fadenkreuz wurden bestätigt (mit der damals schwächeren Antwortprüfung; mit der neuen Prüfung nur Helligkeit und Eingang erneut gelaufen). Eagle Eye (`0x39`) und Night Vision (`0x49`) blieben nach dem Schreiben auf 0. **Korrektur 2026-10-30:** Der Monitor beantwortet Leseanfragen für `E0/39`, `E0/49` und `E0/3A` gar nicht, sondern liefert die Antwort der vorherigen Anfrage erneut (Echo mit der Sub-ID `0x22` bzw. `0x0E`) [gemessen mit Debug-Ausgabe der Rohantwort]. Die frühere Lesart „0/1“ war die Antwort der Refresh-Anzeige, die Aussage „wird nicht angenommen“ ein Messartefakt der damals zu schwachen Antwortprüfung. Ob der FO48U diese Funktionen überhaupt hat, ist offen. Die Antwortprüfung (Sub-ID, Länge, Prüfsumme `0x50 ^ rx[0…9]`) fängt das jetzt ab. Zur Einordnung: Das Dekompilat (`SetEagleEyeON` / `SetNightVisionON` in `RTKCmd_x64.dll`) sendet exakt dasselbe Paket (`03 E0 39 00 01` bzw. `03 E0 49 00 01`) und wartet 150 ms; im Sidekick-Code (`OSD_Interface.cs`, Schnellschalter) steht keine Vorbedingung. Das Web lieferte nichts: Gigabyte-Seiten blockieren Abrufe (HTTP 403), Suchtreffer nennen nur die Funktionsnamen bei anderen AORUS-Modellen (FO32U).

Einordnung durch das Handbuch ([Bedienungsanleitung Deutsch, Stand 2022-02-17](https://download.gigabyte.com/FileList/Manual/AORUS_FO48U_UM_German_20220217.pdf), 50 Seiten, Text per PDFKit gelesen): Das OSD des FO48U nennt weder Eagle Eye noch Night Vision; das Gaming-Menü kennt Aim Stabilizer, Schwarzausgleich, Hohe Auflösung, Display Modus/Position und Adaptive Sync. Das stützt die Vermutung, dass der FO48U beide Funktionen nicht hat, beweist sie aber nicht (Handbuch ≠ Firmware) [Handbuch]. Die OSD-Größe (`E0/3A`) gibt es dagegen: System → OSD Einstellungen → „Größe“ („De-/aktivieren Sie die Anpassung des OSD-Menüfensters“); der Monitor beantwortet die Leseanfrage trotzdem nicht [Handbuch + gemessen]. Die Bildmodus-Liste im OSD endet mit „sRGB, Benutzerdefiniert 1–3, Grün“; die App zeigt Index 5–8 als sRGB/Custom 1–3 und Index 9 als „Level 9“, passend wäre „Grün“ (Energiesparmodus) [ungeprüft: Zuordnung nur aus der Reihenfolge abgeleitet; die Handbuch-Liste ist im Textauszug unvollständig]. Stufennamen für Gamma (Anzeige „22“ im OSD) und Farbtemperatur („Normal“) nennt das Handbuch nicht.


Namen der Stufen stehen in den Sprachtabellen in `OSD.cs` (`Eng`: u. a. „Smart OD“, „Picture Quality“, „Balanced“, „Speed“ für OverDrive; Reihenfolge je Sub-ID ungeprüft).

## Dashboard (Systemwerte auf dem Monitor)

Der Monitor zeigt im Dashboard Werte, die der Host schickt. Am Mac läuft das über denselben DDC-Weg wie die Regler, ein Realtek-HID ist nicht nötig [gemessen 2026-10-30, `_analyse/poc/dashprobe.swift`: alle acht Felder erschienen am Dashboard].

- Status lesen: `E0/18` (an: cur 1), `E0/19` (Position). Die Anzeige-Schalter `E0/40`–`E0/48` liefern beim Lesen nur feste Bitwerte (1, 2, 4 … 128, 256), keinen Zustand [gemessen].
- Wert senden: `03 E0 <sub> hi mid lo sign` mit Wert = `hi·10000 + mid·100 + lo`, `sign` = 1 bei negativ [Dekompilat `RTKCmd_x64.dll`, `SetCPU_Temp` usw.; Schreiben gemessen]. Ganze Zahlen in °C, MHz, RPM, %.
- Sub-IDs: `0x1A` CPU-Temp, `0x1B` CPU-Takt, `0x1C` CPU-Lüfter, `0x1D` CPU-Last, `0x1E` GPU-Temp, `0x1F` GPU-Takt, `0x20` GPU-Lüfter, `0x21` GPU-Last, `0x4A` Maus-DPI [Dekompilat; `0x1A`–`0x21` gemessen].
- Anzeige-Schalter setzen: `03 E0 <sub> 00 01|00` mit `sub` = `0x40`–`0x48` (an = 01, aus = 00) [Dekompilat `SetXTitleON/OFF`, alle 18 Pakete geprüft; GPU-Lüfter und übrige Felder am Monitor ausgeblendet, Nutzer-Sichtprüfung 2026-10-30, ein Monitor]. Der Zustand ist nicht lesbar; MonitorDeck schaltet beim Start nicht lesbare Felder aus (Takt, Lüfter, Maus-DPI) und beim Ausschalten des Menü-Schalters alle wieder an. Beim ersten App-Lauf blieb der GPU-Lüfter sichtbar, ein einzeln gesendetes Paket und ein weiterer App-Lauf blendeten ihn aus; Ursache ungeklärt.
- Abstand: nach jedem Paket 150 ms warten (der Sidekick tut das). Zwei Pakete direkt nacheinander zeigten nur die CPU-Last, mit 150 ms Abstand erschienen alle acht Werte [gemessen].
- Am Mac ohne Admin-Rechte lesbar: CPU- und GPU-Last (`host_statistics`, `IOAccelerator`). Temperatur: ohne Admin-Rechte über `IOHIDEventSystemClient` (private API, `_analyse/poc/sensorprobe.swift`); auf dem MacBook Air M5 liefern 47 Sensoren Werte, davon `PMU tdie1…14` / `PMU2 tdie1…10` als SoC-Chip-Temperaturen (30–36 °C im Leerlauf); eine Trennung CPU/GPU ist daraus nicht belegt [gemessen, ein Mac]. Lüfter: das MacBook Air hat keinen (kein Lüfter in der IORegistry gefunden), der Wert wäre immer 0 [gemessen, ein Mac]. Takt: [ungeprüft] (nötig wäre IOReport oder `powermetrics` mit sudo).

## Sub-IDs für `0xE0`
Quelle: `Get*`-Exporte der `RTKCmd_x64.dll` [Dekompilat]. Welche davon der FO48U wirklich unterstützt, ist offen; Modellweichen im Sidekick: `OSD.cs`/`OSD_Interface.cs` (Soc_model `FO48U`, Produkt-ID `GBT4800`, Realtek-Flash-Pfad VID 3034 / PID 4352).

| Sub | Funktion |
|---|---|
| `0x02` | BlackEQ |
| `0x03` | ColorTemperature |
| `0x04` | R |
| `0x05` | G |
| `0x06` | B |
| `0x07` | Gamma |
| `0x08` | ColorVibrance |
| `0x09` | OverDrive |
| `0x0A` | AIM |
| `0x0B` | LowBlueLight |
| `0x0C` | FreeSync |
| `0x0D` | SuperResolution |
| `0x0E` | PIP_PBP_ON_OFF |
| `0x0F` | PBPSouce |
| `0x10` | PBPDisplaySW |
| `0x13` | PBPAudioSW |
| `0x14` | PIPSize |
| `0x15` | PIPLocation |
| `0x18` | DASHOn |
| `0x19` | DASHLocation |
| `0x22` | RefreshOn |
| `0x23` | Timer_UP_DOWN |
| `0x25` | GameTimer |
| `0x27` | GameTimerPauseContinue |
| `0x28` | Counter_OnOff |
| `0x29` | Counter_value |
| `0x2B` | AorusLocation |
| `0x2C` | PictureMode |
| `0x2D` | Input |
| `0x2E` | AudioInput |
| `0x2F` | Trans |
| `0x30` | OSDDisplayTime |
| `0x31` | LEDIndicator |
| `0x32` | QuickSWUp |
| `0x33` | QuickSWDown |
| `0x34` | QuickSWRight |
| `0x35` | QuickSWLeft |
| `0x37` | Crosshair |
| `0x38` | FirmwareVer; Antwort `FF FF 46 06` = max `0xFFFF` (unbestimmt), aktuell `0x4606`: Hochbyte `0x46` = ASCII „F“, Tiefbyte `0x06` = Version → **F06** [Deutung; stützt sich auf: `GetOSD` liefert `cur = rx[8]·256 + rx[9]` (Dekompilat); Sidekick zeigt Versionen als „F“ + zweistellige Zahl (`OSD.cs`: `D2`, `"F" + text4`); Gigabyte listet für den FO48U genau eine Firmware, F06 vom 2022-09-07 ([Support-Seite](https://gigabyte.com/Monitor/AORUS-FO48U/support)). Nicht belegt: dass Sidekick selbst nur das Tiefbyte auswertet] |
| `0x39` | EagleEye |
| `0x3A` | OSDSize |
| `0x3B` | FlashBang |
| `0x3C` | FlashBangParam1 |
| `0x3D` | FlashBangParam2 |
| `0x3E` | FlashBangParam3 |
| `0x3F` | FlashBangGameTime |
| `0x40` | MouseDPITitle |
| `0x41` | CPUTempTitle |
| `0x42` | CPUFreqTitle |
| `0x43` | CPUFanTitle |
| `0x44` | CPUUsageTitle |
| `0x45` | GPUTempTitle |
| `0x46` | GPUFreqTitle |
| `0x47` | GPUFanTitle |
| `0x48` | GPUUsageTitle |
| `0x49` | NightVision |
| `0x53` | HDR |
| `0x64` | Number |
| `0x69` | KVM_BC |
| `0x6A` | KVMBC_Enable |
| `0x6B` | KVMB_Input |
| `0x6C` | KVMC_Input |
| `0x6E` | LocalDimming |
| `0x6F` | OverClock |
| `0x70` | LightEnhance |
| `0x71` | ColorEnhance |
| `0x72` | DarkEnhance |
| `0x73` | RSaturation |
| `0x74` | RHue |
| `0x75` | GSaturation |
| `0x76` | GHue |
| `0x77` | BSaturation |
| `0x78` | BHue |
| `0x79` | CSaturation |
| `0x7A` | CHue |
| `0x7B` | MSaturation |
| `0x7C` | MHue |
| `0x7D` | YSaturation |
| `0x7E` | YHue |
| `0x7F` | PanelUsingTime |
| `0x80` | PixelClearOnOff |
| `0x81` | PixelClearCount |
| `0x84` | Rotate |
