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
        case .mute, .soundUp, .soundDown: guard AudioOutput.isMonitorCached() else { return false }
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
        return CGDisplayVendorNumber(id) == AudioOutput.vendor
    }
}

/// Führt Tastendrücke in Reihenfolge auf der DDC-Queue mit Rücklesen aus; direkt aufeinanderfolgende Schritte derselben Art
/// werden zusammengefasst (Tastenwiederholung). OSD und Menü zeigen sofort den erwarteten Wert und danach den bestätigten.
final class KeyJobs: @unchecked Sendable {
    static let shared = KeyJobs()
    enum Kind { case brightness, volume, mute }
    /// Lautstärke nach „Stumm aus“, wenn kein Vorwert bekannt ist.
    static let unmuteDefault = 5

    private enum Job { case step(Control, Int), setVolume(Int), toggleMute }
    private let lock = NSLock()
    private var queue: [Job] = []
    private var scheduled = false
    /// Zuletzt bekannte Werte (Helligkeit, Lautstärke) für die sofortige Anzeige; älter als `knownFor` gilt als unbekannt
    /// (der Wert kann am Monitor selbst geändert worden sein).
    private var known: [Control: (current: Int, max: Int, at: Date)] = [:]
    private static let knownFor: TimeInterval = 10
    private var volumeBeforeMute: Int?

    /// Stumm umschalten: liefert die Ziel-Lautstärke und merkt den Vorwert (atomar; Menü und Tasten teilen ihn).
    func toggleMute(current: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        return toggleMuteLocked(current)
    }

    private func toggleMuteLocked(_ current: Int) -> Int {
        if current > 0 { volumeBeforeMute = current; return 0 }
        defer { volumeBeforeMute = nil }
        return volumeBeforeMute ?? Self.unmuteDefault
    }

    func add(_ kind: Kind, delta: Int) {
        let c: Control = kind == .brightness ? .brightness : .volume
        lock.lock()
        // Erwarteten Wert sofort zeigen, wenn ein frischer Ist-Wert bekannt ist; Stumm wird dann gleich als Zielwert eingereiht.
        if let k = known[c], Date().timeIntervalSince(k.at) < Self.knownFor {
            let new = kind == .mute ? toggleMuteLocked(k.current) : min(max(k.current + delta, 0), k.max)
            known[c] = (new, k.max, k.at)
            show(c, new, k.max)
            enqueue(kind == .mute ? .setVolume(new) : .step(c, delta))
        } else {
            enqueue(kind == .mute ? .toggleMute : .step(c, delta))
        }
        let start = !scheduled
        scheduled = true
        lock.unlock()
        if start { ddcWorker.run { self.drain($0) } }
    }

    /// Hängt einen Auftrag an; ein Schritt direkt nach einem Schritt desselben Werts wird zusammengefasst. Nur unter `lock`.
    private func enqueue(_ job: Job) {
        if case .step(let c, let d) = job, case .step(let lc, let ld)? = queue.last, lc == c { queue[queue.count - 1] = .step(c, ld + d) }
        else { queue.append(job) }
    }

    /// OSD und Menü auf dem Main-Thread aktualisieren. Unter `lock` eingereiht, damit die Reihenfolge der Anzeigen
    /// der Reihenfolge der Entscheidungen entspricht (die Main-Queue arbeitet FIFO).
    private func show(_ c: Control, _ value: Int, _ max: Int) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                OSD.show(c == .brightness ? .brightness : .volume, value: value, max: max)
                Model.shared.external(c, value, max)
            }
        }
    }

    /// Vom Menü gelesener oder geschriebener Wert: Ausgangspunkt für die sofortige Anzeige, solange kein Tastendruck wartet.
    func remember(_ c: Control, _ value: Int, _ max: Int) {
        lock.lock()
        if !waiting(c) { known[c] = (value, max, Date()) }
        lock.unlock()
    }

    /// `true`, wenn ein eingereihter Auftrag diesen Wert betrifft. Nur unter `lock`.
    private func waiting(_ c: Control) -> Bool {
        queue.contains { job in
            switch job {
            case .step(let jc, _): return jc == c
            case .setVolume, .toggleMute: return c == .volume
            }
        }
    }

    /// Merkt den bestätigten Wert und zeigt ihn, sofern danach kein weiterer Auftrag für diesen Wert folgt (sonst springt die Anzeige zurück).
    private func confirm(_ c: Control, _ value: Int, _ max: Int, last: Bool) {
        lock.lock()
        if last, !waiting(c) {
            known[c] = (value, max, Date())
            show(c, value, max)
        }
        lock.unlock()
    }

    /// Fehlschlag: Vorschau verwerfen, Wert neu lesen lassen und einen Hinweis zeigen.
    private func fail(_ c: Control, _ message: String) {
        lock.lock(); known[c] = nil; lock.unlock()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                Model.shared.status = message
                Model.shared.reread(c)
            }
        }
    }

    private func drain(_ m: Monitor?) {
        lock.lock(); let jobs = queue; queue = []; scheduled = false; lock.unlock()
        for (i, job) in jobs.enumerated() {
            let c: Control
            if case .step(let jc, _) = job { c = jc } else { c = .volume }
            let last = !jobs[(i + 1)...].contains { other in
                if case .step(let oc, _) = other { return oc == c }
                return c == .volume
            }
            // Regel aus AGENTS.md: erst Ist-Wert lesen, dann mit Rücklesen schreiben, bei Ablehnung auf den Ist-Wert zurück.
            guard let m, let r = m.read(c) else {
                fail(c, tr("\(c.name): Monitor antwortet nicht", "\(c.name): monitor does not respond")); continue
            }
            let target: Int
            switch job {
            case .step(_, let d): target = min(max(r.current + d, 0), r.max)
            case .setVolume(let v): target = min(max(v, 0), r.max)
            case .toggleMute: target = toggleMute(current: r.current)
            }
            guard target != r.current else { confirm(c, target, r.max, last: last); continue }
            let result = m.write(c, target)
            if case .rejected(let actual) = result {
                if actual != r.current { m.write(c, r.current) }
                fail(c, tr("\(c.name): vom Monitor nicht angenommen", "\(c.name): rejected by the monitor"))
            } else {
                confirm(c, target, r.max, last: last)
            }
        }
    }
}
