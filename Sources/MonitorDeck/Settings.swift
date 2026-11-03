import SwiftUI
import ServiceManagement
import FO48UKit

/// Ein Eintrag, der im Menü angepinnt werden kann (Tabs „Bild“ und „Gaming“).
struct PinItem {
    enum Kind { case picker([String]), toggle, slider(Int) }
    let control: Control
    let kind: Kind

    static let image: [PinItem] = [
        PinItem(control: .pictureMode, kind: .picker(modes)),
        PinItem(control: .input, kind: .picker(inputNames)),
        PinItem(control: .gamma, kind: .picker(gammaNames)),
        PinItem(control: .colorTemp, kind: .picker(colorTempNames)),
        PinItem(control: .blackEQ, kind: .slider(20)),
    ]
    static let gaming: [PinItem] = [
        PinItem(control: .overDrive, kind: .picker(overDriveNames)),
        PinItem(control: .crosshair, kind: .picker(crosshairNames)),
        PinItem(control: .freeSync, kind: .toggle),
        PinItem(control: .aimStabilizer, kind: .toggle),
        PinItem(control: .refreshOSD, kind: .toggle),
    ]
    static let all = image + gaming
}

/// Gemerkte Auswahl der angepinnten Einstellungen (UserDefaults, Schlüssel = DDC-Code).
@MainActor
final class Pins: ObservableObject {
    static let shared = Pins()
    private static let key = "pinnedControls"
    private static let defaults: [Control] = [.pictureMode, .blackEQ, .freeSync]
    @Published private var codes: Set<Int>

    private init() {
        if let stored = UserDefaults.standard.array(forKey: Self.key) as? [Int] { codes = Set(stored) }
        else { codes = Set(Self.defaults.map { Int($0.code) }) }
    }

    func isPinned(_ c: Control) -> Bool { codes.contains(Int(c.code)) }

    func binding(_ c: Control) -> Binding<Bool> {
        Binding(get: { self.isPinned(c) }, set: { on in
            if on { self.codes.insert(Int(c.code)) } else { self.codes.remove(Int(c.code)) }
            UserDefaults.standard.set(Array(self.codes), forKey: Self.key)
        })
    }
}

/// Autostart-Zustand für den Tab „Allgemein“.
@MainActor
final class Autostart: ObservableObject {
    static let shared = Autostart()
    @Published var enabled = SMAppService.mainApp.status == .enabled
    @Published var note: String?

    func refresh() {
        let st = SMAppService.mainApp.status
        enabled = st == .enabled
        if st == .requiresApproval { note = tr("Freigabe nötig: Systemeinstellungen → Allgemein → Anmeldeobjekte.", "Approval needed: System Settings → General → Login Items.") }
    }

    func set(_ on: Bool) {
        note = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            note = tr("Autostart", "Launch at login") + ": \(error.localizedDescription)"
        }
        refresh()
    }
}

extension Model {
    /// Aktiver Eingang (gemessen, VCP 0x60); bei USB-C mit Hinweis auf den DP-Alt-Mode.
    var connectionName: String? {
        guard let v = values[.input], v >= 0, v < inputNames.count else { return nil }
        return v == 3 ? "USB-C (DP-Alt-Mode)" : inputNames[v]
    }

    func slider(_ c: Control, max: Int = 100) -> some View {
        let b = dragBinding(c)
        return Slider(value: Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0) }), in: 0...Double(maxes[c] ?? max), step: 1) {
            Text(c.name)
        } onEditingChanged: { editing in
            if !editing { self.set(c, b.wrappedValue) }
        }
        .labelsHidden()
        .disabled(values[c] == nil)
    }

    /// Alle vom Monitor gemeldeten Stufen; unbenannte erscheinen als „Stufe N“.
    func picker(_ c: Control, _ names: [String], selection: Binding<Int>? = nil) -> some View {
        let top = maxes[c] ?? names.count - 1
        return Picker(c.name, selection: selection ?? binding(c)) {
            ForEach(0...Swift.max(top, 0), id: \.self) { Text($0 < names.count ? names[$0] : tr("Stufe", "Level") + " \($0)").tag($0) }
        }
        .disabled(values[c] == nil)
    }

    func toggle(_ c: Control) -> some View {
        let b = binding(c)
        return Toggle(c.name, isOn: Binding(get: { b.wrappedValue == 1 }, set: { b.wrappedValue = $0 ? 1 : 0 }))
            .toggleStyle(.switch)
            .disabled(values[c] == nil)
    }

    /// Steuerelement eines Eintrags; der Eingang fragt vor dem Wechsel weg von USB-C nach.
    @ViewBuilder func control(_ item: PinItem, sliderWidth: CGFloat? = nil) -> some View {
        switch item.kind {
        case .picker(let names): picker(item.control, names, selection: item.control == .input ? inputBinding() : nil)
        case .toggle: toggle(item.control)
        case .slider(let max):
            HStack(spacing: 10) {
                Text(item.control.name)
                if let w = sliderWidth { slider(item.control, max: max).frame(width: w) } else { slider(item.control, max: max) }
                Text("\(values[item.control] ?? 0)").monospacedDigit().frame(width: 24, alignment: .trailing)
            }
        }
    }

    /// Menüzeile wie im Design: Name links, Auswahlfeld kompakt rechts, 40 pt hoch.
    @ViewBuilder func pinnedView(_ item: PinItem) -> some View {
        switch item.kind {
        case .picker(let names):
            HStack {
                Text(item.control.name)
                Spacer()
                picker(item.control, names, selection: item.control == .input ? inputBinding() : nil).labelsHidden().fixedSize()
            }
            .frame(height: 40)
        case .toggle:
            HStack { Text(item.control.name); Spacer(); toggle(item.control).labelsHidden() }.frame(height: 40)
        case .slider: control(item).frame(height: 40)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var keys = MediaKeys.shared
    @ObservedObject var feeder = Feeder.shared
    @ObservedObject var model = Model.shared
    @ObservedObject var pins = Pins.shared
    @ObservedObject var autostart = Autostart.shared

    private func pinRow(_ item: PinItem) -> some View {
        HStack {
            model.control(item, sliderWidth: 130)
            Toggle(isOn: pins.binding(item.control)) {
                Image(systemName: pins.isPinned(item.control) ? "pin.fill" : "pin")
            }
            .toggleStyle(.button).buttonStyle(.borderless)
            .foregroundStyle(pins.isPinned(item.control) ? Color.accentColor : .secondary)
            .help(tr("Im Menü anzeigen", "Show in menu"))
        }
    }

    private func pinTab(_ items: [PinItem]) -> some View {
        Form {
            Section {
                ForEach(items, id: \.control) { pinRow($0) }
            } footer: {
                Text(tr("Pin: Einstellung zusätzlich im Menü anzeigen. Lautstärke, Helligkeit, Kontrast und Schärfe sind immer im Menü.", "Pin: also show this setting in the menu. Volume, brightness, contrast and sharpness are always in the menu."))
            }
        }
        .formStyle(.grouped)
    }

    enum Tab: CaseIterable { case image, gaming, mac, general
        var title: String { switch self { case .image: tr("Bild", "Picture"); case .gaming: "Gaming"; case .mac: "Mac"; case .general: tr("Allgemein", "General") } }
        var icon: String { switch self { case .image: "display"; case .gaming: "scope"; case .mac: "laptopcomputer"; case .general: "slider.horizontal.3" } }
    }
    @State private var tab: Tab = .image

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 20)).frame(height: 24)
                        Text(t.title).font(.caption)
                    }
                    .frame(width: 84, height: 50)
                    .foregroundStyle(tab == t ? Color.primary : .secondary)
                    .background(RoundedRectangle(cornerRadius: 8).fill(tab == t ? Color.primary.opacity(0.12) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            Group {
            switch tab {
            case .image: pinTab(PinItem.image)
            case .gaming: pinTab(PinItem.gaming)
            case .mac: macTab
            case .general: generalTab
            }
            }
        }
        .frame(width: 560, height: 500)
    }

    private var macTab: some View {
            Form {
                Section {
                    Toggle(tr("Tasten steuern Monitor", "Keys control monitor"), isOn: Binding(get: { keys.enabled }, set: { $0 ? keys.start() : keys.stop() }))
                    Picker(tr("Helligkeitstasten", "Brightness keys"), selection: $keys.brightnessViaF) {
                        Label(tr("Systemtasten", "System keys"), systemImage: "sun.max").tag(true)
                        Text(tr("Medientasten", "Media keys")).tag(false)
                    }
                    .disabled(!keys.enabled)
                    Stepper(value: $keys.brightnessStep, in: 1...10) {
                        Text(tr("Schritt Helligkeit: \(keys.brightnessStep)", "Brightness step: \(keys.brightnessStep)"))
                    }
                    Stepper(value: $keys.volumeStep, in: 1...10) {
                        Text(tr("Schritt Lautstärke: \(keys.volumeStep)", "Volume step: \(keys.volumeStep)"))
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Wirkt nur, solange der Mauszeiger auf dem Monitor steht. Braucht die Berechtigung „Bedienungshilfen“. Schritte: 1–10.", "Only applies while the pointer is on the monitor. Needs the “Accessibility” permission. Steps: 1–10."))
                        if let note = keys.note { Text(note) }
                    }
                }
                Section {
                    Toggle(tr("Systemwerte im Dashboard", "System stats on dashboard"), isOn: Binding(get: { feeder.enabled }, set: { $0 ? feeder.start() : feeder.stop() }))
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Sendet CPU- und GPU-Last sowie die SoC-Temperatur des Macs an das Dashboard des Monitors. Nicht lesbare Werte werden dort ausgeblendet.", "Sends the Mac's CPU and GPU load and SoC temperature to the monitor's dashboard. Values that cannot be read are hidden there."))
                        if let note = feeder.note { Text(note) }
                    }
                }
            }
            .formStyle(.grouped)
    }

    private var generalTab: some View {
            Form {
                Section {
                    Toggle(tr("Beim Anmelden starten", "Launch at login"), isOn: Binding(get: { autostart.enabled }, set: { autostart.set($0) }))
                    LabeledContent(tr("Monitorwerte", "Monitor values")) {
                        Button(tr("Neu lesen", "Reload")) { model.refresh() }
                    }
                } footer: {
                    if let note = autostart.note { Text(note) }
                }
                Section {
                    LabeledContent(tr("Monitor", "Monitor"), value: "AORUS FO48U")
                    if let c = model.connectionName { LabeledContent(tr("Verbindung", "Connection"), value: c) }
                    LabeledContent(tr("Version", "Version"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                }
            }
            .formStyle(.grouped)
            .onAppear { autostart.refresh() }
    }
}

/// Eigenes Einstellungsfenster (⌘, im Menü), da die App ohne Dock-Symbol läuft.
@MainActor enum SettingsWindow {
    private static var window: NSWindow?
    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = tr("MonitorDeck Einstellungen", "MonitorDeck Settings")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
