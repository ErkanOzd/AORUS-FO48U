import SwiftUI
import ServiceManagement
import FO48UKit

let modes = ["Standard", "FPS", "RTS/RPG", tr("Film", "Movie"), tr("Lesen", "Reading"), "sRGB", "Custom 1", "Custom 2", "Custom 3"]
let inputNames = ["HDMI 1", "HDMI 2", "DisplayPort", "USB-C"]
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

    /// Vergisst den Monitor; der nächste Auftrag sucht an allen Anschlüssen neu (nach Abstecken oder Umstecken).
    func reset() { queue.async { self.monitor = nil } }
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
    /// Name der Tonausgabe, wenn der Ton nicht über den Monitor läuft (dann regeln die Lautstärketasten den Mac).
    @Published var audioElsewhere: String?
    static let shared = Model()

    nonisolated static let shown: [Control] = [.brightness, .contrast, .volume, .sharpness, .pictureMode, .input, .overDrive, .gamma, .blackEQ, .colorTemp, .freeSync, .aimStabilizer, .crosshair, .refreshOSD]

    /// Zählt Schreibvorgänge je Wert: ein Lesewert, der vor dem Schreiben angefragt wurde, überschreibt die Anzeige nicht.
    private var epoch: [Control: Int] = [:]
    /// Gerade gezogene Schieberegler: Neulesen lässt sie in Ruhe.
    var dragging: Set<Control> = []

    /// Liest `controls` nacheinander, je Wert ein eigener Auftrag auf der DDC-Queue (ein Schreibwunsch wartet höchstens einen Lesevorgang).
    /// Antwortet kein einziger Wert, gilt der Monitor als getrennt und wird beim nächsten Durchlauf an allen Anschlüssen neu gesucht.
    func refresh(_ controls: [Control], clearStatus: Bool = true) async {
        let snapshot = epoch
        let elsewhere = AudioOutput.isMonitorCached() ? nil : AudioOutput.name() ?? tr("anderes Gerät", "another device")
        if audioElsewhere != elsewhere { audioElsewhere = elsewhere }
        let found = await withCheckedContinuation { cont in worker.run { cont.resume(returning: $0 != nil) } }
        if connected != found { connected = found }
        guard found else { return }
        if clearStatus, status != nil { status = nil }
        var answered = 0
        for c in controls {
            if Task.isCancelled { return }
            let r = await withCheckedContinuation { cont in worker.run { cont.resume(returning: $0?.read(c)) } }
            if r != nil { answered += 1 }
            guard let r, epoch[c] == snapshot[c], !dragging.contains(c) else { continue }
            if values[c] != r.current { values[c] = r.current }
            if maxes[c] != r.max { maxes[c] = r.max }
            if c == .brightness || c == .volume { KeyJobs.shared.remember(c, r.current, r.max) }
        }
        if !controls.isEmpty, answered == 0, !Task.isCancelled {
            worker.reset()
            connected = false
        }
    }

    /// Einen Wert neu lesen (z. B. nach einem fehlgeschlagenen Tastendruck).
    func reread(_ c: Control) {
        epoch[c, default: 0] += 1
        Task { await refresh([c], clearStatus: false) }
    }

    // MARK: Live-Aktualisierung

    /// Pause zwischen zwei Lesedurchläufen, solange etwas Werte anzeigt.
    private static let pollPause: Duration = .seconds(1)
    /// Sichtbare Oberflächen (Menü, Einstellungen) und die Werte, die sie zeigen.
    private var watchers: [String: @MainActor () -> [Control]] = [:]
    private var poll: Task<Void, Never>?

    /// Meldet eine Oberfläche als sichtbar oder verdeckt; `controls` liefert die Werte, die sie zeigt. Beim Sichtbarwerden wird sofort gelesen,
    /// danach laufend; ohne sichtbare Oberfläche liest die App nicht.
    func watch(_ id: String, visible: Bool, _ controls: @escaping @MainActor () -> [Control]) {
        let added = visible && watchers[id] == nil
        watchers[id] = visible ? controls : nil
        if watchers.isEmpty || added { poll?.cancel(); poll = nil }
        guard !watchers.isEmpty, poll == nil else { return }
        poll = Task {
            var first = true
            while !Task.isCancelled {
                var seen = Set<Control>()
                let list = watchers.values.flatMap { $0() }.filter { seen.insert($0).inserted }
                await refresh(list, clearStatus: first)
                first = false
                try? await Task.sleep(for: Self.pollPause)
            }
        }
    }

    /// Wert, den die Tastensteuerung gerade gesetzt hat: sofort anzeigen; ältere Lesewerte überschreiben ihn nicht.
    func external(_ c: Control, _ value: Int, _ max: Int) {
        epoch[c, default: 0] += 1
        if values[c] != value { values[c] = value }
        if maxes[c] != max { maxes[c] = max }
    }

    /// Schreibt `v` mit Rücklesen. Angezeigt wird, was der Monitor meldet; bei Ablehnung der zurückgelesene Wert.
    func set(_ c: Control, _ v: Int) {
        let old = values[c]
        values[c] = v
        epoch[c, default: 0] += 1
        worker.run { m in
            // Regel aus CLAUDE.md: erst Ist-Wert lesen, bei Ablehnung darauf zurückspringen.
            let before = m?.read(c)?.current
            let result = m?.write(c, v) ?? .rejected(actual: nil)
            if case .rejected(let actual) = result, let b = before, actual != b { m?.write(c, b) }
            Task { @MainActor in
                switch result {
                case .confirmed:
                    self.status = nil
                    if c == .brightness || c == .volume { KeyJobs.shared.remember(c, v, self.maxes[c] ?? 100) }
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
                model.set(.volume, KeyJobs.shared.toggleMute(current: v))
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
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("AORUS FO48U").font(.headline)
                        Label(tr("Verbunden", "Connected") + (model.values[.input].flatMap { $0 >= 0 && $0 < inputNames.count ? " · " + inputNames[$0] : nil } ?? ""), systemImage: "circle.fill").font(.callout).foregroundStyle(.secondary)
                            .labelStyle(DotLabelStyle())
                    }
                    Spacer()
                }
                .padding(.bottom, 4)
                volumeRow
                if let out = model.audioElsewhere {
                    Text(tr("Ton läuft über „\(out)“, die Lautstärketasten regeln den Mac.", "Sound plays through “\(out)”; the volume keys control the Mac."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.bottom, 4)
                }
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
        .background(WindowVisibility { visible in
            model.watch("menu", visible: visible) { [.volume, .brightness, .contrast, .sharpness, .input] + PinItem.all.map(\.control).filter { Pins.shared.isPinned($0) } }
        })
    }
}

/// Meldet, ob das Fenster dieser View auf dem Bildschirm sichtbar ist (Menü offen, Einstellungen nicht verdeckt oder minimiert).
struct WindowVisibility: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void
    func makeNSView(context: Context) -> Probe { Probe(onChange) }
    func updateNSView(_ view: Probe, context: Context) {}
    /// Wird die View entfernt, ohne vorher das Fenster zu verlassen, gilt sie als unsichtbar (sonst liefe das Lesen weiter).
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.detach() }

    final class Probe: NSView {
        private let onChange: @MainActor (Bool) -> Void
        private var token: NSObjectProtocol?
        private var last: Bool?
        init(_ onChange: @escaping @MainActor (Bool) -> Void) { self.onChange = onChange; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = window.map { w in
                NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.update() }
                }
            }
            update()
        }

        func detach() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            if last == true { last = false; onChange(false) }
        }

        private func update() {
            let visible = window?.occlusionState.contains(.visible) ?? false
            guard visible != last else { return }
            last = visible
            onChange(visible)
        }
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
    alert.informativeText = tr("Helligkeitstasten steuern den Monitor, solange der Mauszeiger darauf steht, Lautstärketasten, solange der Ton über ihn läuft. Dafür braucht die App die Berechtigung „Bedienungshilfen“; macOS fragt gleich danach. Die Einstellung lässt sich jederzeit im Tab „Mac“ ändern.", "Brightness keys control the monitor while the pointer is on it, volume keys while sound plays through it. This needs the “Accessibility” permission; macOS asks right after. You can change this at any time in the “Mac” tab.")
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
