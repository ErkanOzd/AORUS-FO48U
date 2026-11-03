import SwiftUI
import ServiceManagement
import FO48UKit

let modes = ["Standard", "FPS", "RTS/RPG", tr("Film", "Movie"), tr("Lesen", "Reading"), "sRGB", "Custom 1", "Custom 2", "Custom 3"]
let inputNames = ["HDMI 1", "HDMI 2", "DisplayPort", "USB-C"]
let crosshairNames = [tr("Aus", "Off"), "1", "2", "3", "4"]
let gammaNames = [tr("Aus", "Off"), "1.8", "2.0", "2.2", "2.4", "2.6"]
let colorTempNames = [tr("Kalt", "Cool"), "Normal", tr("Warm", "Warm")]
let overDriveNames = [tr("Aus", "Off"), "Smart OD", tr("Bildqualität", "Picture Quality"), tr("Ausgewogen", "Balanced"), tr("Geschwindigkeit", "Speed")]

let knownFlags = ["--selftest", "--writetest", "--inputtest", "--autostart"]
let cliArgs = Array(CommandLine.arguments.dropFirst())
if let bad = cliArgs.first(where: { $0.hasPrefix("--") && !knownFlags.contains($0) })
    ?? (cliArgs.firstIndex(of: "--autostart").flatMap { i in cliArgs.dropFirst(i + 1).first.flatMap { ["on", "off"].contains($0) ? nil : $0 } }) {
    print(tr("Unbekanntes Argument", "Unknown argument") + ": \(bad)\n" + tr("Aufruf", "Usage") + ": MonitorDeck [--selftest | --writetest | --inputtest | --autostart [on|off]]")
    exit(2)
}

if CommandLine.arguments.contains("--selftest") {
    guard let m = Monitor() else { print(tr("kein Monitor", "no monitor")); exit(1) }
    var gelesen = 0
    for c in [Control.brightness, .contrast, .volume, .sharpness, .pictureMode, .input, .overDrive, .gamma, .blackEQ, .colorTemp, .freeSync, .aimStabilizer, .crosshair, .refreshOSD, .eagleEye, .nightVision, .pipPbp, .osdSize] {
        let r = m.read(c)
        if r != nil { gelesen += 1 }
        print(c.name, r.map { "\($0.current)/\($0.max)" } ?? "–")
    }
    exit(gelesen > 0 ? 0 : 1)
}

if let i = CommandLine.arguments.firstIndex(of: "--autostart") {
    // --autostart on|off: Anmeldeobjekt setzen; ohne Argument nur den Status ausgeben.
    let arg = CommandLine.arguments.dropFirst(i + 1).first
    do {
        if arg == "on" { try SMAppService.mainApp.register() }
        if arg == "off" { try SMAppService.mainApp.unregister() }
    } catch { print(tr("Fehler", "Error") + ": \(error.localizedDescription)"); exit(1) }
    print(tr("Autostart:", "Launch at login:"), SMAppService.mainApp.status == .enabled ? tr("an", "on") : tr("aus (Status \(SMAppService.mainApp.status.rawValue))", "off (status \(SMAppService.mainApp.status.rawValue))"))
    exit(0)
}

if CommandLine.arguments.contains("--writetest") {
    // Schreibt Helligkeit mit Rücklesen und stellt den Altwert wieder her.
    guard let m = Monitor(), let alt = m.read(.brightness)?.current else { print(tr("kein Monitor", "no monitor")); exit(1) }
    let neu = alt >= 50 ? alt - 10 : alt + 10
    let ok1 = m.write(.brightness, neu) == .confirmed, jetzt = m.read(.brightness)?.current
    let ok2 = m.write(.brightness, alt) == .confirmed, danach = m.read(.brightness)?.current
    print(tr("alt \(alt) → neu \(neu): \(ok1), gelesen \(jetzt.map(String.init) ?? "–"); zurück: \(ok2), gelesen \(danach.map(String.init) ?? "–")", "old \(alt) → new \(neu): \(ok1), read \(jetzt.map(String.init) ?? "–"); back: \(ok2), read \(danach.map(String.init) ?? "–")"))
    exit(ok1 && ok2 && danach == alt ? 0 : 1)
}

if CommandLine.arguments.contains("--inputtest") {
    // Schaltet kurz auf DisplayPort und versucht bis zu 30 s, auf USB-C zurückzuschalten.
    guard let m = Monitor(), m.read(.input)?.current == 3 else { print(tr("kein Monitor oder Eingang nicht USB-C", "no monitor or input is not USB-C")); exit(1) }
    print("auf DisplayPort:", m.write(.input, 2).sent); sleep(3)
    for i in 1...30 {
        if m.write(.input, 3).sent, m.read(.input)?.current == 3 { print(tr("zurück auf USB-C nach Versuch \(i)", "back on USB-C after attempt \(i)")); exit(0) }
        sleep(1)
    }
    print(tr("Rückschalten fehlgeschlagen", "switching back failed")); exit(1)
}

/// Serialisiert alle DDC-Zugriffe auf einer eigenen Queue (nie auf dem Main-Thread) und sucht den Monitor bei Bedarf neu.
final class Worker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ddc")
    private var monitor: Monitor?

    func run(_ work: @escaping @Sendable (Monitor?) -> Void) {
        queue.async {
            if self.monitor == nil { self.monitor = Monitor() }
            work(self.monitor)
        }
    }
}

/// Gemeinsame DDC-Queue für Menü und Dashboard (nie zwei Zugriffe gleichzeitig).
let ddcWorker = Worker()

/// Hält die Werte; geschrieben wird nur über `set`, nie beim Neulesen.
@MainActor
final class Model: ObservableObject {
    private let worker = ddcWorker
    @Published var values: [Control: Int] = [:]
    @Published var maxes: [Control: Int] = [:]
    @Published var connected: Bool?   // nil = Suche läuft
    @Published var status: String?
    static let shared = Model()

    nonisolated static let shown: [Control] = [.brightness, .contrast, .volume, .sharpness, .pictureMode, .input, .overDrive, .gamma, .blackEQ, .colorTemp, .freeSync, .aimStabilizer, .crosshair, .refreshOSD]

    init() { refresh() }

    func refresh() {
        worker.run { m in
            var read: [Control: Int] = [:], max: [Control: Int] = [:]
            if let m { for c in Self.shown { if let r = m.read(c) { read[c] = r.current; max[c] = r.max } } }
            let found = m != nil
            Task { @MainActor in
                self.connected = found
                self.values.merge(read) { _, new in new }
                self.maxes.merge(max) { _, new in new }
                if found { self.status = nil }
            }
        }
    }

    /// Schreibt `v` mit Rücklesen. Angezeigt wird, was der Monitor meldet; bei Ablehnung der zurückgelesene Wert.
    func set(_ c: Control, _ v: Int) {
        let old = values[c]
        values[c] = v
        worker.run { m in
            // Regel aus CLAUDE.md: erst Ist-Wert lesen, bei Ablehnung darauf zurückspringen.
            let before = m?.read(c)?.current
            let result = m?.write(c, v) ?? .rejected(actual: nil)
            if case .rejected(let actual) = result, let b = before, actual != b { m?.write(c, b) }
            Task { @MainActor in
                switch result {
                case .confirmed: self.status = nil
                case .unconfirmed: self.status = tr("\(c.name): gesendet, vom Monitor nicht bestätigt", "\(c.name): sent, not confirmed by the monitor")
                case .rejected(let actual):
                    self.values[c] = before ?? actual ?? old
                    self.status = tr("\(c.name): vom Monitor nicht angenommen", "\(c.name): rejected by the monitor")
                }
            }
        }
    }

    func binding(_ c: Control) -> Binding<Int> {
        Binding(get: { self.values[c] ?? 0 }, set: { self.set(c, $0) })
    }

    /// Eingang: Wechsel weg von USB-C nimmt dem Mac das Bild, daher erst nachfragen.
    func inputBinding() -> Binding<Int> {
        Binding(get: { self.values[.input] ?? 0 }, set: { v in
            if self.values[.input] == 3, v != 3 {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = tr("Eingang auf \(inputNames[v]) umschalten?", "Switch input to \(inputNames[v])?")
                alert.informativeText = tr("Der Mac verliert das Bild, bis am Monitor wieder USB-C gewählt ist (Monitor-Menü oder Eingangstaste).", "The Mac loses the picture until USB-C is selected again on the monitor (monitor menu or input button).")
                alert.addButton(withTitle: tr("Umschalten", "Switch"))
                alert.addButton(withTitle: tr("Abbrechen", "Cancel"))
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            self.set(.input, v)
        })
    }

    /// Für Slider: während des Ziehens nur anzeigen, beim Loslassen schreiben.
    func dragBinding(_ c: Control) -> Binding<Int> {
        Binding(get: { self.values[c] ?? 0 }, set: { self.values[c] = $0 })
    }
}

struct MenuView: View {
    @ObservedObject private var model = Model.shared
    @ObservedObject private var keys = MediaKeys.shared
    @ObservedObject private var pins = Pins.shared

    private var pinned: [PinItem] { PinItem.all.filter { pins.isPinned($0.control) } }

    private func divider() -> some View { Divider().padding(.horizontal, -16).padding(.vertical, 4) }

    private func sliderRow(_ c: Control, icon: String, max: Int = 100) -> some View {
        HStack(spacing: 10) {
            Group {
                if icon == "sharpness" { SharpnessIcon().stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)).frame(width: 15, height: 15) }
                else { Image(systemName: icon) }
            }
            .frame(width: 20).foregroundStyle(.secondary).help(c.name)
            model.slider(c, max: max)
            Text("\(model.values[c] ?? 0)").monospacedDigit().frame(width: 30, alignment: .trailing)
        }
        .frame(height: 44)
    }

    private var volumeRow: some View {
        let v = model.values[.volume] ?? 0
        return HStack(spacing: 10) {
            Button {
                if v > 0 { KeyJobs.shared.volumeBeforeMute = v; model.set(.volume, 0) } else { model.set(.volume, KeyJobs.shared.volumeBeforeMute ?? 5); KeyJobs.shared.volumeBeforeMute = nil }
            } label: {
                Image(systemName: v == 0 ? "speaker.slash" : "speaker.wave.2").frame(width: 20)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(tr("Stumm (0 und zurück)", "Mute (0 and back)"))
            .disabled(model.values[.volume] == nil)
            model.slider(.volume)
            Text("\(v)").monospacedDigit().frame(width: 30, alignment: .trailing)
        }
        .frame(height: 44)
    }

    private func footerRow(_ title: String, _ key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); Text(key).font(.callout).foregroundStyle(.secondary) }
                .frame(height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.connected == nil {
                Text(tr("Suche Monitor …", "Looking for monitor …")).padding(.vertical, 8)
            } else if model.connected == false {
                Text(tr("Kein passender Monitor gefunden", "No matching monitor found")).padding(.vertical, 8)
                Button(tr("Erneut suchen", "Search again")) { model.refresh() }.padding(.bottom, 8)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("AORUS FO48U").font(.headline)
                        Label(tr("Verbunden", "Connected") + (model.values[.input].flatMap { $0 >= 0 && $0 < inputNames.count ? " · " + inputNames[$0] : nil } ?? ""), systemImage: "circle.fill").font(.callout).foregroundStyle(.secondary)
                            .labelStyle(DotLabelStyle())
                    }
                    Spacer()
                    Button { SettingsWindow.show() } label: { Image(systemName: "gearshape").font(.system(size: 15)).frame(width: 32, height: 32).contentShape(Rectangle()) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(tr("Einstellungen (⌘,)", "Settings (⌘,)"))
                }
                .padding(.bottom, 4)
                volumeRow
                sliderRow(.brightness, icon: "sun.max")
                sliderRow(.contrast, icon: "circle.righthalf.filled")
                sliderRow(.sharpness, icon: "sharpness", max: 10)
                if !pinned.isEmpty {
                    divider()
                    Text(tr("Angepinnt", "Pinned")).font(.caption).foregroundStyle(.secondary).textCase(.uppercase).padding(.vertical, 2)
                    ForEach(pinned, id: \.control) { item in model.pinnedView(item) }
                }
                if let note = keys.note { Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 4) }
                if let status = model.status { Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 4) }
            }
            divider()
            footerRow(tr("Einstellungen …", "Settings …"), "⌘,") { SettingsWindow.show() }.keyboardShortcut(",")
            footerRow(tr("Beenden", "Quit"), "⌘Q") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
        .frame(width: 300)
        .focusEffectDisabled()
        .onAppear { model.refresh() }
    }
}

/// Schärfe-Symbol wie im Design: Dreieck mit senkrechter Mittellinie.
struct SharpnessIcon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
        p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}

struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Circle().fill(.green).frame(width: 7, height: 7)
            configuration.title
        }
    }
}

/// Einmalige Abfrage beim ersten Start des App-Bundles, ob die App beim Anmelden starten soll.
@MainActor func askAutostartOnce() {
    let key = "autostartAsked"
    guard Bundle.main.bundleIdentifier != nil, !UserDefaults.standard.bool(forKey: key),
          SMAppService.mainApp.status == .notRegistered else { return }
    UserDefaults.standard.set(true, forKey: key)
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = tr("MonitorDeck beim Anmelden starten?", "Launch MonitorDeck at login?")
    alert.informativeText = tr("Die App legt sich in die Menüleiste. Die Einstellung lässt sich jederzeit im Menü ändern.", "The app lives in the menu bar. You can change this at any time in the menu.")
    alert.addButton(withTitle: tr("Beim Anmelden starten", "Launch at login"))
    alert.addButton(withTitle: tr("Nicht jetzt", "Not now"))
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    do { try SMAppService.mainApp.register() } catch {
        let fail = NSAlert()
        fail.alertStyle = .warning
        fail.messageText = tr("Autostart konnte nicht eingerichtet werden", "Could not set up launch at login")
        fail.informativeText = error.localizedDescription
        fail.runModal()
    }
}

/// Einmalige Abfrage beim ersten Start, ob die Tasten den Monitor steuern sollen; „Aktivieren“ löst die Systemabfrage „Bedienungshilfen“ aus.
@MainActor func askKeysOnce() {
    let key = "keysAsked"
    guard Bundle.main.bundleIdentifier != nil, !UserDefaults.standard.bool(forKey: key), !MediaKeys.shared.enabled else { return }
    UserDefaults.standard.set(true, forKey: key)
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = tr("Helligkeits- und Lautstärketasten für den Monitor nutzen?", "Use brightness and volume keys for the monitor?")
    alert.informativeText = tr("Die Tasten steuern den Monitor, solange der Mauszeiger darauf steht. Dafür braucht die App die Berechtigung „Bedienungshilfen“; macOS fragt gleich danach. Die Einstellung lässt sich jederzeit im Tab „Mac“ ändern.", "The keys control the monitor while the pointer is on it. This needs the “Accessibility” permission; macOS asks right after. You can change this at any time in the “Mac” tab.")
    alert.addButton(withTitle: tr("Aktivieren", "Enable"))
    alert.addButton(withTitle: tr("Nicht jetzt", "Not now"))
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    MediaKeys.shared.start()
}

struct FO48UApp: App {
    init() { DispatchQueue.main.async { askAutostartOnce(); askKeysOnce(); if Feeder.shared.enabled { Feeder.shared.start() }; if MediaKeys.shared.enabled { MediaKeys.shared.start() } } }
    var body: some Scene {
        MenuBarExtra("MonitorDeck", systemImage: "display") { MenuView() }
            .menuBarExtraStyle(.window)
    }
}
FO48UApp.main()
