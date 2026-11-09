import AppKit
import ApplicationServices
import FO48UKit

/// Leitet Helligkeits- (Mauszeiger auf dem Monitor) und Lautstärketasten (Tonausgabe ist der Monitor) an den Monitor um und zeigt ein OSD.
/// Braucht die Berechtigung „Bedienungshilfen“ (aktiver `CGEventTap`, nur so lassen sich Tasten abfangen).
@MainActor
final class MediaKeys: ObservableObject {
    static let shared = MediaKeys()
    private static let key = "mediaKeysEnabled"
    private static let brightnessStepKey = "mediaKeysBrightnessStep"
    private static let volumeStepKey = "mediaKeysVolumeStep"
    /// Gespeicherten Wert lesen (übernimmt den früheren gemeinsamen Schlüssel), auf 1–10 begrenzen, Standard 5.
    private static func storedStep(_ key: String) -> Int {
        let d = UserDefaults.standard
        let v = d.integer(forKey: key) != 0 ? d.integer(forKey: key) : d.integer(forKey: "mediaKeysStep")
        return v == 0 ? 5 : min(max(v, 1), 10)
    }
    private static let fKeysKey = "mediaKeysBrightnessF"
    /// EISA-Herstellerkennung „GBT“ (Gigabyte): (7<<10)|(2<<5)|20.
    private static let vendor: UInt32 = 7252

    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: MediaKeys.key)
    @Published private(set) var note: String?
    /// Schrittweite pro Tastendruck (1–10, Standard 5), getrennt für Helligkeit und Lautstärke.
    @Published var brightnessStep = MediaKeys.storedStep(MediaKeys.brightnessStepKey) { didSet { UserDefaults.standard.set(brightnessStep, forKey: Self.brightnessStepKey) } }
    @Published var volumeStep = MediaKeys.storedStep(MediaKeys.volumeStepKey) { didSet { UserDefaults.standard.set(volumeStep, forKey: Self.volumeStepKey) } }
    /// `true`: Helligkeit über F14/F15 (so liefert sie die Tastatur am Test-Mac [gemessen]); `false`: über Medientasten (Nx-Ereignis).
    @Published var brightnessViaF: Bool = UserDefaults.standard.object(forKey: MediaKeys.fKeysKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(brightnessViaF, forKey: Self.fKeysKey) }
    }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    // Nx-Tastencodes (IOKit `ev_keymap.h`).
    private enum Code: Int { case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7 }

    func start() {
        guard tap == nil else { return }
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            note = tr("Berechtigung nötig: Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen → MonitorDeck einschalten. Die Steuerung startet danach automatisch.", "Permission needed: System Settings → Privacy & Security → Accessibility → switch MonitorDeck on. Control starts automatically afterwards.")
            set(false); waitForPermission(); return
        }
        permissionTimer?.invalidate(); permissionTimer = nil
        let mask = CGEventMask((1 << 14) | (1 << 10) | (1 << 11))   // systemDefined, keyDown, keyUp
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async { MediaKeys.shared.reenable() }
                return Unmanaged.passUnretained(event)
            }
            // Das Ereignis wird synchron auf dem Main-Thread (Run-Loop des Taps) behandelt.
            if type == .keyDown || type == .keyUp {
                return MainActor.assumeIsolated { MediaKeys.shared.handleKey(event, down: type == .keyDown) } ? nil : Unmanaged.passUnretained(event)
            }
            let swallow = MainActor.assumeIsolated { MediaKeys.shared.handle(event) }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: nil) else {
            note = tr("Tasten-Abfang konnte nicht gestartet werden.", "Could not start the key tap.")
            set(false); return
        }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        note = nil
        set(true)
    }

    private var permissionTimer: Timer?
    /// Prüft jede Sekunde, ob die Berechtigung erteilt wurde, und startet dann die Steuerung selbst.
    private func waitForPermission() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                let m = MediaKeys.shared
                if AXIsProcessTrusted() { m.permissionTimer?.invalidate(); m.permissionTimer = nil; m.start() }
            }
        }
    }

    func stop() {
        permissionTimer?.invalidate(); permissionTimer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil; source = nil; note = nil
        set(false)
    }

    private func set(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.key)
    }

    fileprivate func reenable() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }

    /// `true`, wenn die Taste verschluckt wird (Mauszeiger auf dem Monitor).
    fileprivate func handle(_ cg: CGEvent) -> Bool {
        guard let event = NSEvent(cgEvent: cg) else { return false }
        guard event.subtype.rawValue == 8 else { return false }
        let data = event.data1
        let flags = data & 0xFFFF
        guard let code = Code(rawValue: (data & 0xFFFF0000) >> 16) else { return false }
        // Lautstärke und Stumm nur, wenn der Ton über den Monitor läuft (sonst regelt macOS selbst); Helligkeit nur bei Zeiger auf dem Monitor.
        switch code {
        case .mute, .soundUp, .soundDown: guard AudioOutput.isMonitor() else { return false }
        case .brightnessUp, .brightnessDown: guard onMonitor() else { return false }
        }
        // Nur Tastendruck (0xA) auslösen, Loslassen aber ebenfalls verschlucken.
        if (flags & 0xFF00) >> 8 == 0xA {
            // „Systemtasten“ fängt Nx- und F14/F15-Helligkeit ab; sendet eine Tastatur beides, zählt nur die erste Quelle.
            if (code == .brightnessUp || code == .brightnessDown) && brightnessViaF && recentlyHandled(.fKey) { return true }
            if code == .brightnessUp || code == .brightnessDown { lastBrightness = (.nx, CACurrentMediaTime()) }
            switch code {
            case .mute: KeyJobs.shared.add(.mute, delta: 0)
            case .soundUp: KeyJobs.shared.add(.volume, delta: volumeStep)
            case .soundDown: KeyJobs.shared.add(.volume, delta: -volumeStep)
            case .brightnessUp: KeyJobs.shared.add(.brightness, delta: brightnessStep)
            case .brightnessDown: KeyJobs.shared.add(.brightness, delta: -brightnessStep)
            }
        }
        return true
    }

    /// Helligkeitstasten laufen auf manchen Tastaturen als F14 (runter, 107) / F15 (hoch, 113) statt als Nx-Ereignis [gemessen].
    fileprivate func handleKey(_ cg: CGEvent, down: Bool) -> Bool {
        let code = cg.getIntegerValueField(.keyboardEventKeycode)
        guard brightnessViaF, code == 107 || code == 113, onMonitor() else { return false }
        if down, !recentlyHandled(.nx) {
            lastBrightness = (.fKey, CACurrentMediaTime())
            KeyJobs.shared.add(.brightness, delta: code == 113 ? brightnessStep : -brightnessStep)
        }
        return true
    }

    private enum Source { case nx, fKey }
    private var lastBrightness: (Source, CFTimeInterval)?
    /// `true`, wenn dieselbe Helligkeitstaste gerade (< 60 ms) über die andere Quelle ausgelöst wurde.
    private func recentlyHandled(_ other: Source) -> Bool {
        guard let l = lastBrightness, l.0 == other else { return false }
        return CACurrentMediaTime() - l.1 < 0.06
    }

    private func onMonitor() -> Bool {
        let p = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
        return CGDisplayVendorNumber(id) == Self.vendor
    }
}

/// Fasst schnelle Tastendrücke (Wiederholung) zusammen und führt sie auf der DDC-Queue mit Rücklesen aus.
/// Das OSD zeigt sofort den erwarteten Wert und danach den vom Monitor bestätigten.
final class KeyJobs: @unchecked Sendable {
    static let shared = KeyJobs()
    enum Kind { case brightness, volume, mute }
    private let lock = NSLock()
    private var pending: [Kind: Int] = [:]
    private var scheduled = false
    /// Zuletzt bestätigte Werte für die sofortige OSD-Anzeige; älter als `knownFor` gilt als unbekannt (Wert kann im Monitor-OSD geändert worden sein).
    private var known: [Kind: (current: Int, max: Int, at: Date)] = [:]
    private static let knownFor: TimeInterval = 10
    private var _volumeBeforeMute: Int?
    /// Lautstärke vor „Stumm“; gemeinsam für Menü und Tasten (thread-sicher).
    var volumeBeforeMute: Int? {
        get { lock.lock(); defer { lock.unlock() }; return _volumeBeforeMute }
        set { lock.lock(); _volumeBeforeMute = newValue; lock.unlock() }
    }

    func add(_ kind: Kind, delta: Int) {
        lock.lock()
        pending[kind, default: 0] += kind == .mute ? 1 : delta
        let start = !scheduled
        scheduled = true
        // Erwarteten Wert sofort anzeigen, wenn ein frischer Ist-Wert bekannt ist.
        let key: Kind = kind == .brightness ? .brightness : .volume
        var preview: (Int, Int)?
        if let k = known[key], Date().timeIntervalSince(k.at) < Self.knownFor {
            let new = kind == .mute ? (k.current > 0 ? 0 : _volumeBeforeMute ?? 5) : min(max(k.current + delta, 0), k.max)
            known[key] = (new, k.max, k.at)
            preview = (new, k.max)
        }
        lock.unlock()
        if let preview { Self.showOSD(key, preview.0, preview.1) }
        if start { ddcWorker.run { self.drain($0) } }
    }

    private static func showOSD(_ kind: Kind, _ value: Int, _ max: Int) {
        Task { @MainActor in OSD.show(kind == .brightness ? .brightness : .volume, value: value, max: max) }
    }

    /// Merkt den bestätigten Wert und zeigt ihn, sofern inzwischen kein weiterer Tastendruck wartet (sonst springt das OSD zurück).
    private func confirm(_ kind: Kind, _ value: Int, _ max: Int) {
        lock.lock()
        let newer = pending[kind] != nil || (kind == .volume && pending[.mute] != nil)
        if !newer { known[kind] = (value, max, Date()) }
        lock.unlock()
        if !newer { Self.showOSD(kind, value, max) }
    }

    private func drain(_ m: Monitor?) {
        lock.lock(); let jobs = pending; pending = [:]; scheduled = false; lock.unlock()
        guard let m else { return }
        // Regel aus CLAUDE.md: erst Ist-Wert lesen, dann mit Rücklesen schreiben.
        for (kind, delta) in jobs where delta != 0 {
            switch kind {
            case .brightness: adjust(m, .brightness, delta)
            case .volume: adjust(m, .volume, delta)
            case .mute:
                guard let r = m.read(.volume) else { continue }
                let target = r.current > 0 ? 0 : volumeBeforeMute ?? 5
                if r.current > 0 { volumeBeforeMute = r.current } else { volumeBeforeMute = nil }
                confirm(.volume, Self.shown(m.write(.volume, target), target, r.current), r.max)
            }
        }
    }

    private func adjust(_ m: Monitor, _ c: Control, _ delta: Int) {
        guard let r = m.read(c) else { return }
        let new = min(max(r.current + delta, 0), r.max)
        let shown = new == r.current ? new : Self.shown(m.write(c, new), new, r.current)
        confirm(c == .brightness ? .brightness : .volume, shown, r.max)
    }

    /// Wert, den der Monitor nach dem Schreiben hat: bei Ablehnung der zurückgelesene, sonst der geschriebene.
    private static func shown(_ result: WriteResult, _ new: Int, _ old: Int) -> Int {
        if case .rejected(let actual) = result { return actual ?? old }
        return new
    }
}
