import SwiftUI
import ServiceManagement
import FO48UKit

let modes = ["Standard", "FPS", "RTS/RPG", "Film", "Lesen", "sRGB", "Custom 1", "Custom 2", "Custom 3"]
let inputs = [(0, "HDMI 1"), (1, "HDMI 2"), (2, "DisplayPort"), (3, "USB-C")]
let gammaNames = ["Aus", "1.8", "2.0", "2.2", "2.4", "2.6"]
let colorTempNames = ["Kalt", "Normal", "Warm"]
let overDriveNames = ["Aus", "Smart OD", "Bildqualität", "Ausgewogen", "Geschwindigkeit"]

if CommandLine.arguments.contains("--selftest") {
    guard let m = Monitor() else { print("kein Monitor"); exit(1) }
    for c in [Control.brightness, .contrast, .volume, .sharpness, .pictureMode, .input, .overDrive, .gamma, .blackEQ, .colorTemp, .freeSync, .aimStabilizer, .crosshair, .refreshOSD, .eagleEye, .nightVision, .pipPbp, .osdSize] {
        print(c.name, m.read(c).map { "\($0.current)/\($0.max)" } ?? "–")
    }
    exit(0)
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
    let ok1 = m.write(.brightness, neu), jetzt = m.read(.brightness)?.current
    let ok2 = m.write(.brightness, alt), danach = m.read(.brightness)?.current
    print("alt \(alt) → neu \(neu): \(ok1), gelesen \(jetzt.map(String.init) ?? "–"); zurück: \(ok2), gelesen \(danach.map(String.init) ?? "–")")
    exit(ok1 && ok2 && danach == alt ? 0 : 1)
}

if CommandLine.arguments.contains("--inputtest") {
    // Schaltet kurz auf DisplayPort und versucht bis zu 30 s, auf USB-C zurückzuschalten.
    guard let m = Monitor(), m.read(.input)?.current == 3 else { print("kein Monitor oder Eingang nicht USB-C"); exit(1) }
    print("auf DisplayPort:", m.write(.input, 2)); sleep(3)
    for i in 1...30 {
        if m.write(.input, 3), m.read(.input)?.current == 3 { print("zurück auf USB-C nach Versuch \(i)"); exit(0) }
        sleep(1)
    }
    print("Rückschalten fehlgeschlagen"); exit(1)
}

/// Hält die Werte; Schreiben passiert nur über `binding`, nie beim Neulesen.
@MainActor
final class Model: ObservableObject {
    let monitor = Monitor()
    @Published var values: [Control: Int] = [:]

    static let shown: [Control] = [.brightness, .contrast, .volume, .sharpness, .pictureMode, .input, .overDrive, .gamma, .blackEQ, .colorTemp, .freeSync, .aimStabilizer, .crosshair, .refreshOSD]

    init() { refresh() }

    func refresh() {
        guard let m = monitor else { return }
        for c in Self.shown { if let r = m.read(c) { values[c] = r.current } }
    }

    func binding(_ c: Control) -> Binding<Int> {
        Binding(get: { self.values[c] ?? 0 }, set: { v in
            self.values[c] = v
            self.monitor?.write(c, v)
        })
    }
}

struct MenuView: View {
    @StateObject private var model = Model()
    @State private var autostart = SMAppService.mainApp.status == .enabled

    private func setAutostart(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            print("Autostart: \(error.localizedDescription)")
        }
        autostart = SMAppService.mainApp.status == .enabled
    }

    private func slider(_ c: Control, max: Double = 100) -> some View {
        let b = model.binding(c)
        return Slider(value: Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0) }), in: 0...max, step: 1) { Text(c.name) }
    }

    private func picker(_ c: Control, _ items: [(Int, String)]) -> some View {
        Picker(c.name, selection: model.binding(c)) { ForEach(items, id: \.0) { Text($0.1).tag($0.0) } }
    }

    private func toggle(_ c: Control) -> some View {
        let b = model.binding(c)
        return Toggle(c.name, isOn: Binding(get: { b.wrappedValue == 1 }, set: { b.wrappedValue = $0 ? 1 : 0 }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.monitor == nil {
                Text("Kein externer Monitor gefunden")
            } else {
                slider(.brightness)
                slider(.contrast)
                slider(.volume)
                slider(.sharpness, max: 10)
                slider(.blackEQ, max: 20)
                picker(.pictureMode, modes.enumerated().map { ($0.offset, $0.element) })
                picker(.input, inputs)
                picker(.overDrive, overDriveNames.enumerated().map { ($0.offset, $0.element) })
                picker(.gamma, gammaNames.enumerated().map { ($0.offset, $0.element) })
                picker(.colorTemp, colorTempNames.enumerated().map { ($0.offset, $0.element) })
                picker(.crosshair, [(0, "Aus"), (1, "1"), (2, "2"), (3, "3"), (4, "4")])
                toggle(.freeSync)
                toggle(.aimStabilizer)
                toggle(.refreshOSD)
                Divider()
                Button("Werte neu lesen") { model.refresh() }
            }
            Toggle("Beim Anmelden starten", isOn: Binding(get: { autostart }, set: setAutostart))
            Button("Beenden") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 280)
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
    if alert.runModal() == .alertFirstButtonReturn { try? SMAppService.mainApp.register() }
}

struct FO48UApp: App {
    init() { DispatchQueue.main.async { askAutostartOnce() } }
    var body: some Scene {
        MenuBarExtra("FO48U", systemImage: "display") { MenuView() }
            .menuBarExtraStyle(.window)
    }
}
FO48UApp.main()
