import SwiftUI
import ServiceManagement
import FO48UKit

let modes = ["Standard", "FPS", "RTS/RPG", "Film", "Lesen", "sRGB", "Custom 1", "Custom 2", "Custom 3"]
let inputNames = ["HDMI 1", "HDMI 2", "DisplayPort", "USB-C"]
let crosshairNames = ["Aus", "1", "2", "3", "4"]
let gammaNames = ["Aus", "1.8", "2.0", "2.2", "2.4", "2.6"]
let colorTempNames = ["Kalt", "Normal", "Warm"]
let overDriveNames = ["Aus", "Smart OD", "Bildqualität", "Ausgewogen", "Geschwindigkeit"]

let knownFlags = ["--selftest", "--writetest", "--inputtest", "--autostart"]
let cliArgs = Array(CommandLine.arguments.dropFirst())
if let bad = cliArgs.first(where: { $0.hasPrefix("-") && !knownFlags.contains($0) })
    ?? (cliArgs.firstIndex(of: "--autostart").flatMap { i in cliArgs.dropFirst(i + 1).first.flatMap { ["on", "off"].contains($0) ? nil : $0 } }) {
    print("Unbekanntes Argument: \(bad)\nAufruf: MonitorDeck [--selftest | --writetest | --inputtest | --autostart [on|off]]")
    exit(2)
}

if CommandLine.arguments.contains("--selftest") {
    guard let m = Monitor() else { print("kein Monitor"); exit(1) }
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
    } catch { print("Fehler: \(error.localizedDescription)"); exit(1) }
    print("Autostart:", SMAppService.mainApp.status == .enabled ? "an" : "aus (Status \(SMAppService.mainApp.status.rawValue))")
    exit(0)
}

if CommandLine.arguments.contains("--writetest") {
    // Schreibt Helligkeit mit Rücklesen und stellt den Altwert wieder her.
    guard let m = Monitor(), let alt = m.read(.brightness)?.current else { print("kein Monitor"); exit(1) }
    let neu = alt >= 50 ? alt - 10 : alt + 10
    let ok1 = m.write(.brightness, neu) == .confirmed, jetzt = m.read(.brightness)?.current
    let ok2 = m.write(.brightness, alt) == .confirmed, danach = m.read(.brightness)?.current
    print("alt \(alt) → neu \(neu): \(ok1), gelesen \(jetzt.map(String.init) ?? "–"); zurück: \(ok2), gelesen \(danach.map(String.init) ?? "–")")
    exit(ok1 && ok2 && danach == alt ? 0 : 1)
}

if CommandLine.arguments.contains("--inputtest") {
    // Schaltet kurz auf DisplayPort und versucht bis zu 30 s, auf USB-C zurückzuschalten.
    guard let m = Monitor(), m.read(.input)?.current == 3 else { print("kein Monitor oder Eingang nicht USB-C"); exit(1) }
    print("auf DisplayPort:", m.write(.input, 2).sent); sleep(3)
    for i in 1...30 {
        if m.write(.input, 3).sent, m.read(.input)?.current == 3 { print("zurück auf USB-C nach Versuch \(i)"); exit(0) }
        sleep(1)
    }
    print("Rückschalten fehlgeschlagen"); exit(1)
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

/// Hält die Werte; geschrieben wird nur über `set`, nie beim Neulesen.
@MainActor
final class Model: ObservableObject {
    private let worker = Worker()
    @Published var values: [Control: Int] = [:]
    @Published var maxes: [Control: Int] = [:]
    @Published var connected: Bool?   // nil = Suche läuft
    @Published var status: String?

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
                case .unconfirmed: self.status = "\(c.name): gesendet, vom Monitor nicht bestätigt"
                case .rejected(let actual):
                    self.values[c] = before ?? actual ?? old
                    self.status = "\(c.name): vom Monitor nicht angenommen"
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
                alert.messageText = "Eingang auf \(inputNames[v]) umschalten?"
                alert.informativeText = "Der Mac verliert das Bild, bis am Monitor wieder USB-C gewählt ist (Monitor-Menü oder Eingangstaste)."
                alert.addButton(withTitle: "Umschalten")
                alert.addButton(withTitle: "Abbrechen")
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
    @StateObject private var model = Model()
    @State private var autostart = SMAppService.mainApp.status == .enabled
    @State private var autostartNote: String?

    private func updateAutostart() {
        let st = SMAppService.mainApp.status
        autostart = st == .enabled
        if st == .requiresApproval { autostartNote = "Freigabe nötig: Systemeinstellungen → Allgemein → Anmeldeobjekte." }
    }

    private func setAutostart(_ on: Bool) {
        autostartNote = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            autostartNote = "Autostart: \(error.localizedDescription)"
        }
        updateAutostart()
    }

    private func slider(_ c: Control, max: Int = 100) -> some View {
        let b = model.dragBinding(c)
        return Slider(value: Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0) }), in: 0...Double(model.maxes[c] ?? max), step: 1) {
            Text(c.name)
        } onEditingChanged: { editing in
            if !editing { model.set(c, b.wrappedValue) }
        }
        .disabled(model.values[c] == nil)
    }

    /// Alle vom Monitor gemeldeten Stufen; unbenannte erscheinen als „Stufe N“.
    private func picker(_ c: Control, _ names: [String], selection: Binding<Int>? = nil) -> some View {
        let top = model.maxes[c] ?? names.count - 1
        return Picker(c.name, selection: selection ?? model.binding(c)) {
            ForEach(0...Swift.max(top, 0), id: \.self) { Text($0 < names.count ? names[$0] : "Stufe \($0)").tag($0) }
        }
        .disabled(model.values[c] == nil)
    }

    private func toggle(_ c: Control) -> some View {
        let b = model.binding(c)
        return Toggle(c.name, isOn: Binding(get: { b.wrappedValue == 1 }, set: { b.wrappedValue = $0 ? 1 : 0 }))
            .disabled(model.values[c] == nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.connected == nil {
                Text("Suche Monitor …")
            } else if model.connected == false {
                Text("Kein passender Monitor gefunden")
                Button("Erneut suchen") { model.refresh() }
            } else {
                slider(.brightness)
                slider(.contrast)
                slider(.volume)
                slider(.sharpness, max: 10)
                slider(.blackEQ, max: 20)
                picker(.pictureMode, modes)
                picker(.input, inputNames, selection: model.inputBinding())
                picker(.overDrive, overDriveNames)
                picker(.gamma, gammaNames)
                picker(.colorTemp, colorTempNames)
                picker(.crosshair, crosshairNames)
                toggle(.freeSync)
                toggle(.aimStabilizer)
                toggle(.refreshOSD)
                Divider()
                Button("Werte neu lesen") { model.refresh() }
                if let status = model.status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            Toggle("Beim Anmelden starten", isOn: Binding(get: { autostart }, set: setAutostart))
            if let note = autostartNote { Text(note).font(.caption).foregroundStyle(.secondary) }
            Button("Beenden") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear { model.refresh(); updateAutostart() }
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
    alert.messageText = "MonitorDeck beim Anmelden starten?"
    alert.informativeText = "Die App legt sich in die Menüleiste. Die Einstellung lässt sich jederzeit im Menü ändern."
    alert.addButton(withTitle: "Beim Anmelden starten")
    alert.addButton(withTitle: "Nicht jetzt")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    do { try SMAppService.mainApp.register() } catch {
        let fail = NSAlert()
        fail.alertStyle = .warning
        fail.messageText = "Autostart konnte nicht eingerichtet werden"
        fail.informativeText = error.localizedDescription
        fail.runModal()
    }
}

struct FO48UApp: App {
    init() { DispatchQueue.main.async { askAutostartOnce() } }
    var body: some Scene {
        MenuBarExtra("MonitorDeck", systemImage: "display") { MenuView() }
            .menuBarExtraStyle(.window)
    }
}
FO48UApp.main()
