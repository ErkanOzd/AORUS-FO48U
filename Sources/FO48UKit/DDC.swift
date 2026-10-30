import Foundation
import IOKit

// Private Apple-API (Apple Silicon): DDC/CI über DisplayPort-AUX. Siehe docs/PROTOKOLL.md.
private typealias AVService = CFTypeRef
@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<AVService>?
@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(_ s: AVService, _ chip: UInt32, _ off: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn
@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(_ s: AVService, _ chip: UInt32, _ off: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn

/// Ein steuerbarer Wert: Standard-VCP oder herstellerspezifisch (`0xE0` + Sub-ID).
public struct Control: Hashable, Sendable {
    public let name: String
    public let code: UInt8
    public let vendor: Bool
    public init(_ name: String, _ code: UInt8, vendor: Bool = true) {
        self.name = name; self.code = code; self.vendor = vendor
    }

    public static let brightness = Control("Helligkeit", 0x10, vendor: false)
    public static let contrast = Control("Kontrast", 0x12, vendor: false)
    public static let volume = Control("Lautstärke", 0x62, vendor: false)
    public static let sharpness = Control("Schärfe", 0x87, vendor: false)
    public static let pictureMode = Control("Bildmodus", 0x2C)
    public static let input = Control("Eingang", 0x2D)
    public static let overDrive = Control("OverDrive", 0x09)
    public static let gamma = Control("Gamma", 0x07)
    public static let blackEQ = Control("Black eQualizer", 0x02)
    public static let colorTemp = Control("Farbtemperatur", 0x03)
    public static let freeSync = Control("FreeSync", 0x0C)
    public static let aimStabilizer = Control("Aim Stabilizer", 0x0A)
    public static let crosshair = Control("Fadenkreuz", 0x37)
    public static let refreshOSD = Control("Refresh-Anzeige", 0x22)
    public static let eagleEye = Control("Eagle Eye", 0x39)
    public static let nightVision = Control("Night Vision", 0x49)
    public static let pipPbp = Control("PIP/PBP", 0x0E)
    public static let osdSize = Control("OSD-Größe", 0x3A)
}

public struct Reading: Sendable { public let max: Int; public let current: Int }

public final class Monitor {
    private var service: AVService

    /// Erster extern angeschlossener DDC-Dienst (`nil`, wenn keiner da ist).
    private static func findService() -> AVService? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var entry = IOIteratorNext(it)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(it) }
            let loc = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            if loc == "External", let s = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) {
                return s.takeRetainedValue()
            }
        }
        return nil
    }

    /// Erster extern angeschlossener Monitor mit DDC-Dienst (`nil`, wenn keiner da ist).
    public init?() {
        guard let s = Self.findService() else { return nil }
        service = s
    }

    private func send(_ payload: [UInt8]) -> Bool {
        var pkt: [UInt8] = [UInt8(0x80 | payload.count)] + payload
        var chk: UInt8 = 0x6E ^ 0x51
        for b in pkt { chk ^= b }
        pkt.append(chk)
        if IOAVServiceWriteI2C(service, 0x37, 0x51, &pkt, UInt32(pkt.count)) == KERN_SUCCESS { return true }
        // Nach Eingangswechsel/Neuverbindung ist der Dienst veraltet: neu suchen, einmal wiederholen.
        guard let s = Self.findService() else { return false }
        service = s
        return IOAVServiceWriteI2C(service, 0x37, 0x51, &pkt, UInt32(pkt.count)) == KERN_SUCCESS
    }

    public func read(_ c: Control) -> Reading? {
        guard send(c.vendor ? [0x01, 0xE0, c.code] : [0x01, c.code]) else { return nil }
        usleep(60_000)
        var rx = [UInt8](repeating: 0, count: 12)
        guard IOAVServiceReadI2C(service, 0x37, 0x51, &rx, 12) == KERN_SUCCESS, rx[0] == 0x6E, rx[2] == 0x02, rx[3] == 0x00 else { return nil }
        return Reading(max: Int(rx[6]) << 8 | Int(rx[7]), current: Int(rx[8]) << 8 | Int(rx[9]))
    }

    /// Schreibt und liest zurück; bis zu 3 Versuche. `true`, wenn der Monitor den Wert bestätigt.
    /// Lässt sich nichts zurücklesen (z. B. nach Eingangswechsel), zählt das gesendete Paket.
    @discardableResult
    public func write(_ c: Control, _ value: Int) -> Bool {
        let v = UInt8(clamping: value)
        let payload: [UInt8] = c.vendor ? [0x03, 0xE0, c.code, 0x00, v] : [0x03, c.code, 0x00, v]
        for _ in 0..<3 {
            guard send(payload) else { continue }
            usleep(100_000)
            guard let r = read(c) else { return true }
            if r.current == Int(v) { return true }
        }
        return false
    }
}
