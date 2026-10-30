# MonitorDeck

A macOS menu bar app (Apple Silicon) that controls the **Gigabyte AORUS FO48U** over DDC/CI. It is an alternative to the Windows-only "OSD Sidekick". German version: [`README.md`](README.md).

> **Beta (0.1.x):** feature set largely complete, but tested with one monitor and one Mac only.
>
> Unofficial project, not affiliated with GIGABYTE. "GIGABYTE" and "AORUS" are trademarks of their owners. Use at your own risk (see Notes).

## Features

Brightness, contrast, volume, sharpness, Black eQualizer, picture mode, input, OverDrive, gamma, color temperature, crosshair, FreeSync, Aim Stabilizer, refresh rate OSD, launch at login. Every write is read back and retried up to three times; if the monitor reports a different value, the UI shows the reported value and says so. After an input switch the app looks for the DDC service again on the same port. Sliders write only when released; DDC access never runs on the main thread. With several external monitors the app picks the one that answers brightness, input and picture mode (heuristic).

The UI is German on a German system and English otherwise.

## Requirements

- Apple Silicon Mac, macOS 14 or later
- FO48U connected over USB-C (DisplayPort Alt Mode)
- Xcode command line tools (Swift 5.9) if you build it yourself

## Installation

**Prebuilt image:** download `MonitorDeck-<version>.dmg` from the Releases page, open it and drag the app to Applications. The app is not notarized: on first launch choose System Settings → Privacy & Security → "Open Anyway" (on macOS 15 and later this replaces the right-click route; unverified whether `xattr -d com.apple.quarantine` is additionally needed on your version).

**Build it yourself:**

```sh
git clone https://github.com/ErkanOzd/AORUS-FO48U.git && cd AORUS-FO48U
scripts/build-app.sh                       # builds dist/MonitorDeck.app (ad-hoc signed)
cp -R "dist/MonitorDeck.app" ~/Applications/
open ~/Applications/"MonitorDeck.app"
scripts/make-dmg.sh                        # optional: builds dist/MonitorDeck-<version>.dmg
```

On first launch the app asks once whether it should start at login. You can change this with the "Launch at login" switch in the menu or with `MonitorDeck.app/Contents/MacOS/MonitorDeck --autostart on|off` (must run from the app bundle). After a rebuild or after moving the app the login item may need to be set again (unverified).

Without an app bundle: `swift build && .build/debug/MonitorDeck`.

## Commands

| Command | Effect |
|---|---|
| `MonitorDeck --selftest` | reads all values (read-only) |
| `MonitorDeck --writetest` | writes brightness ±10 with read-back and restores it |
| `MonitorDeck --inputtest` | briefly switches to DisplayPort and back to USB-C (the picture drops for a moment) |
| `MonitorDeck --autostart [on\|off]` | set the login item or show its status |

## Notes

- The app uses the **private Apple API `IOAVService`**. It is not App Store material and may break with a macOS update.
- Switching the input to HDMI/DisplayPort takes the picture away from the Mac until USB-C is selected again; the app asks first. Switching back from the app's menu worked in testing (one monitor, one Mac).
- Only the commands documented here are sent. The manufacturer's firmware flash functions are deliberately not implemented.
- Tested with **one AORUS FO48U** only (firmware probably F06, an interpretation) over USB-C on an Apple Silicon Mac. Other monitors and Mac models are untested; details in [`docs/FUNKTIONEN.md`](docs/FUNKTIONEN.md) (German).
- Eagle Eye and Night Vision are missing from the menu: the monitor does not answer these queries (see `docs/FUNKTIONEN.md`).

## Testing with other AORUS monitors

Other AORUS models (e.g. FO32U2, FI32U, FI27Q) probably use the same DDC/CI protocol; this is not verified. If you want to try one:

1. Build the app, then run `MonitorDeck --selftest` (read-only).
2. Open an issue with: monitor model, firmware, connection (USB-C, HDMI, DisplayPort), Mac model, macOS version and the `--selftest` output. Please do not post serial numbers.
3. Optionally run `--writetest` (brightness ±10, restored) and report which menu items work.

Write commands are at your own risk; firmware functions are never sent.

## Documentation (German)

- [`docs/FUNKTIONEN.md`](docs/FUNKTIONEN.md): what works, what does not, what is verified
- [`docs/PROTOKOLL.md`](docs/PROTOKOLL.md): DDC/CI protocol, sub-IDs, measurements, evidence levels (`[Dekompilat]` = decompiled, `[gemessen]` = measured, `[ungeprüft]` = unverified)
- [`STATUS.md`](STATUS.md): status, decisions, next steps

## Origin of the protocol

The FO48U's DDC/CI protocol was analysed from Gigabyte's publicly available installer (OSD Sidekick) in order to write an independent, interoperable program for macOS, and was then re-measured on the author's own device. The code in this repository is written independently in Swift; no source code, binaries, decompilations, configuration files or texts from Gigabyte are included, and any local copies are kept outside Git. Only command bytes, value ranges and measurements are documented (`docs/PROTOKOLL.md`).

## How it was made

This project was developed with the help of the AI Claude (Anthropic) via Claude Code: analysis, code and documentation were produced in dialogue, while measurements and tests ran on the real monitor. The commits carry corresponding `Co-Authored-By` lines.

## License

[MIT](LICENSE)
