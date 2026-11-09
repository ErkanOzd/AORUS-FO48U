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
        PinItem(control: .crosshair, kind: .toggle),
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
    private static let defaults: [Control] = []
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
        return Slider(value: Binding(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0.rounded()) }), in: 0...Double(maxes[c] ?? max)) {
            Text(c.name)
        } onEditingChanged: { editing in
            if editing { self.dragging.insert(c) } else { self.dragging.remove(c); self.set(c, b.wrappedValue) }
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
        return Toggle(c.name, isOn: Binding(get: { b.wrappedValue != 0 }, set: { b.wrappedValue = $0 ? 1 : 0 }))
            .toggleStyle(.switch)
            .disabled(values[c] == nil)
    }

    /// Nur das Steuerelement eines Eintrags (ohne Namen); der Eingang fragt vor dem Wechsel weg von USB-C nach.
    @ViewBuilder func trailing(_ item: PinItem, sliderWidth: CGFloat? = nil) -> some View {
        switch item.kind {
        case .picker(let names):
            picker(item.control, names, selection: item.control == .input ? inputBinding() : nil).labelsHidden().fixedSize()
        case .toggle:
            toggle(item.control).labelsHidden()
        case .slider(let max):
            HStack(spacing: 10) {
                if let w = sliderWidth { slider(item.control, max: max).frame(width: w) } else { slider(item.control, max: max) }
                Text("\(values[item.control] ?? 0)").monospacedDigit().frame(width: 24, alignment: .trailing)
            }
        }
    }

    /// Angepinnte Menüzeile: Name links, Steuerelement rechts, 40 pt hoch.
    @ViewBuilder func pinnedView(_ item: PinItem) -> some View {
        HStack(spacing: 10) {
            Text(item.control.name).fixedSize()
            if case .slider = item.kind { trailing(item) } else { Spacer(minLength: 8); trailing(item) }
        }
        .frame(height: 40)
    }
}

// MARK: - Bausteine (Systemfarben, Karten wie im Design)

/// Gruppenkarte: abgerundet, Haarlinie, Trennlinien zwischen den Zeilen (jede `Row` zeichnet ihre obere Linie, die erste wird abgeschnitten).
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.top, -1)
            .frame(maxWidth: .infinity)
            .background(scheme == .dark ? Color.white.opacity(0.07) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

/// Zeile in einer Karte: Name links, Inhalt rechts, 44 pt hoch.
struct Row<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .overlay(alignment: .top) { Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1) }
    }
}

struct Footer: View {
    let text: String
    var note: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
            if let note { Text(note) }
        }
        .font(.callout).foregroundStyle(.secondary)
        .padding(.horizontal, 4).padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Schritt-Regler als „−  N  +“.
struct StepControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var body: some View {
        HStack(spacing: 8) {
            Button { value = max(range.lowerBound, value - 1) } label: { Image(systemName: "minus").frame(width: 28, height: 24) }
                .disabled(value <= range.lowerBound)
            Text("\(value)").monospacedDigit().frame(width: 20)
            Button { value = min(range.upperBound, value + 1) } label: { Image(systemName: "plus").frame(width: 28, height: 24) }
                .disabled(value >= range.upperBound)
        }
        .buttonStyle(.bordered).controlSize(.small)
    }
}

struct SettingsView: View {
    @ObservedObject var keys = MediaKeys.shared
    @ObservedObject var feeder = Feeder.shared
    @ObservedObject var model = Model.shared
    @ObservedObject var pins = Pins.shared
    @ObservedObject var autostart = Autostart.shared

    private func pinButton(_ c: Control) -> some View {
        let on = pins.isPinned(c)
        return Button { pins.binding(c).wrappedValue = !on } label: {
            Image(systemName: on ? "pin.fill" : "pin").frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? Color.accentColor : .secondary)
        .help(tr("Im Menü anzeigen", "Show in menu"))
        .accessibilityLabel(tr("\(c.name) im Menü anzeigen", "Show \(c.name) in menu"))
    }

    private func pinRow(_ item: PinItem) -> some View {
        Row(title: item.control.name) {
            model.trailing(item, sliderWidth: 130)
            pinButton(item.control)
        }
    }

    private func pinTab(_ groups: [[PinItem]]) -> some View {
        page {
            ForEach(groups.indices, id: \.self) { g in
                Card { ForEach(groups[g], id: \.control) { pinRow($0) } }
            }
            Footer(text: tr("Pin: Einstellung zusätzlich im Menü anzeigen. Lautstärke, Helligkeit, Kontrast und Schärfe sind immer im Menü.", "Pin: also show this setting in the menu. Volume, brightness, contrast and sharpness are always in the menu."))
                .padding(.top, -12)
        }
    }

    private func page<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView { VStack(spacing: 20) { content() }.padding(.horizontal, 24).padding(.vertical, 20) }
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
        .padding(.top, 30).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            switch tab {
            case .image: pinTab([Array(PinItem.image.prefix(2)), Array(PinItem.image.dropFirst(2))])
            case .gaming: pinTab([PinItem.gaming])
            case .mac: macTab
            case .general: generalTab
            }
        }
        .frame(width: 560, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .background(WindowVisibility { visible in model.watch("settings", visible: visible) { PinItem.all.map(\.control) } })
    }

    private var macTab: some View {
        page {
            VStack(spacing: 0) {
                Card {
                    Row(title: tr("Tasten steuern Monitor", "Keys control monitor")) {
                        Toggle("", isOn: Binding(get: { keys.enabled }, set: { $0 ? keys.start() : keys.stop() })).toggleStyle(.switch).labelsHidden()
                    }
                    Row(title: tr("Helligkeitstasten", "Brightness keys")) {
                        Picker("", selection: $keys.brightnessViaF) {
                            Label(tr("Systemtasten", "System keys"), systemImage: "sun.max").tag(true)
                            Text(tr("Medientasten", "Media keys")).tag(false)
                        }
                        .labelsHidden().fixedSize().disabled(!keys.enabled)
                    }
                    Row(title: tr("Schritt Helligkeit", "Brightness step")) { StepControl(value: $keys.brightnessStep, range: 1...10) }
                    Row(title: tr("Schritt Lautstärke", "Volume step")) { StepControl(value: $keys.volumeStep, range: 1...10) }
                }
                Footer(text: tr("Helligkeit wirkt nur, solange der Mauszeiger auf dem Monitor steht, Lautstärke und Stumm, solange der Ton über den Monitor läuft (sonst regelt macOS). Braucht die Berechtigung „Bedienungshilfen“. Schritte: 1–10.", "Brightness only applies while the pointer is on the monitor, volume and mute while sound plays through the monitor (otherwise macOS handles them). Needs the “Accessibility” permission. Steps: 1–10."), note: keys.note)
            }
            VStack(spacing: 0) {
                Card {
                    Row(title: tr("Systemwerte im Dashboard", "System stats on dashboard")) {
                        Toggle("", isOn: Binding(get: { feeder.enabled }, set: { $0 ? feeder.start() : feeder.stop() })).toggleStyle(.switch).labelsHidden()
                    }
                }
                Footer(text: tr("Sendet CPU- und GPU-Last sowie die SoC-Temperatur des Macs an das Dashboard des Monitors. Nicht lesbare Werte werden dort ausgeblendet.", "Sends the Mac's CPU and GPU load and SoC temperature to the monitor's dashboard. Values that cannot be read are hidden there."), note: feeder.note)
            }
        }
    }

    private var generalTab: some View {
        page {
            VStack(spacing: 0) {
                Card {
                    Row(title: tr("Beim Anmelden starten", "Launch at login")) {
                        Toggle("", isOn: Binding(get: { autostart.enabled }, set: { autostart.set($0) })).toggleStyle(.switch).labelsHidden()
                    }
                }
                if let note = autostart.note { Footer(text: note) }
            }
            Card {
                Row(title: tr("Monitor", "Monitor")) { Text("AORUS FO48U").foregroundStyle(.secondary) }
                if let c = model.connectionName { Row(title: tr("Verbindung", "Connection")) { Text(c).foregroundStyle(.secondary) } }
                Row(title: tr("Version", "Version")) { Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–").foregroundStyle(.secondary) }
            }
        }
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
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
