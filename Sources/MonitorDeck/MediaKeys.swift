import AppKit
import ApplicationServices
import FO48UKit

/// Leitet Helligkeits- und Lautstärketasten an den Monitor um, solange der Mauszeiger auf ihm steht.
/// Braucht die Berechtigung „Bedienungshilfen“ (aktiver `CGEventTap`, nur so lassen sich Tasten abfangen).
@MainActor
final class MediaKeys: ObservableObject {
    static let shared = MediaKeys()
    private static let key = "mediaKeysEnabled"
    /// Schrittweite pro Tastendruck (0–100).
    private static let step = 5
    /// EISA-Herstellerkennung „GBT“ (Gigabyte): (7<<10)|(2<<5)|20.
    private static let vendor: UInt32 = 7252

    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: MediaKeys.key)
    @Published private(set) var note: String?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    // Nx-Tastencodes (IOKit `ev_keymap.h`).
    private enum Code: Int { case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7 }

    func start() {
        guard tap == nil else { return }
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            note = tr("Berechtigung nötig: Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen, dann erneut einschalten.", "Permission needed: System Settings → Privacy & Security → Accessibility, then switch on again.")
            set(false); return
        }
        let mask = CGEventMask(1 << 14)   // NSEvent.EventType.systemDefined
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async { MediaKeys.shared.reenable() }
                return Unmanaged.passUnretained(event)
            }
            // Das Ereignis wird synchron auf dem Main-Thread (Run-Loop des Taps) behandelt.
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

    func stop() {
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
        guard let event = NSEvent(cgEvent: cg), event.subtype.rawValue == 8 else { return false }
        let data = event.data1
        let flags = data & 0xFFFF
        guard let code = Code(rawValue: (data & 0xFFFF0000) >> 16), onMonitor() else { return false }
        // Nur Tastendruck (0xA) auslösen, Loslassen aber ebenfalls verschlucken.
        if (flags & 0xFF00) >> 8 == 0xA { KeyJobs.shared.add(code == .mute ? .mute : (code == .soundUp || code == .soundDown ? .volume : .brightness),
                                                            delta: code == .soundUp || code == .brightnessUp ? Self.step : (code == .mute ? 0 : -Self.step)) }
        return true
    }

    private func onMonitor() -> Bool {
        let p = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
        return CGDisplayVendorNumber(id) == Self.vendor
    }
}

/// Fasst schnelle Tastendrücke (Wiederholung) zusammen und führt sie auf der DDC-Queue mit Rücklesen aus.
final class KeyJobs: @unchecked Sendable {
    static let shared = KeyJobs()
    enum Kind { case brightness, volume, mute }
    private let lock = NSLock()
    private var pending: [Kind: Int] = [:]
    private var scheduled = false
    private var volumeBeforeMute: Int?

    func add(_ kind: Kind, delta: Int) {
        lock.lock()
        pending[kind, default: 0] += kind == .mute ? 1 : delta
        let start = !scheduled
        scheduled = true
        lock.unlock()
        if start { ddcWorker.run { self.drain($0) } }
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
                guard let cur = m.read(.volume)?.current else { continue }
                if cur > 0 { volumeBeforeMute = cur; m.write(.volume, 0) } else { m.write(.volume, volumeBeforeMute ?? 5); volumeBeforeMute = nil }
            }
        }
    }

    private func adjust(_ m: Monitor, _ c: Control, _ delta: Int) {
        guard let r = m.read(c) else { return }
        let new = min(max(r.current + delta, 0), r.max)
        if new != r.current { m.write(c, new) }
    }
}
