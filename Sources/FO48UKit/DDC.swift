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

/// Ergebnis von `Monitor.write`.
public enum WriteResult: Equatable, Sendable {
    /// Der Monitor hat den Wert zurückgemeldet.
    case confirmed
    /// Gesendet, aber nichts zurücklesbar (z. B. nach Eingangswechsel).
    case unconfirmed
    /// Nicht angenommen; `actual` ist der zuletzt zurückgelesene Wert.
    case rejected(actual: Int?)

    /// Paket ging raus und wurde nicht widerlegt.
    public var sent: Bool { if case .rejected = self { return false }; return true }
}

public final class Monitor: @unchecked Sendable {
    private var service: AVService
    /// IOService-Pfad des gewählten Dienstes: Neu-Suche akzeptiert nur denselben Anschluss.
    private let path: String

    /// Alle extern angeschlossenen DDC-Dienste samt Registry-Pfad.
    private static func externalServices() -> [(AVService, String)] {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &it) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }
        var found: [(AVService, String)] = []
        var entry = IOIteratorNext(it)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(it) }
            let loc = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            guard loc == "External", let s = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) else { continue }
            let buf = UnsafeMutablePointer<CChar>.allocate(capacity: 512)
            defer { buf.deallocate() }
            buf[0] = 0
            _ = IORegistryEntryGetPath(entry, kIOServicePlane, buf)
            found.append((s.takeRetainedValue(), String(cString: buf)))
        }
        return found
    }

    /// Ein Dienst gilt als Zielmonitor, wenn Helligkeit, Eingang und Bildmodus beantwortet werden
    /// (die Herstellerregister `0xE0/0x2D` und `0xE0/0x2C` kennt nicht jeder Monitor).
    private static func isTarget(_ s: AVService) -> Bool {
        [Control.brightness, .input, .pictureMode].allSatisfy { transact(s, $0) != nil }
    }

    /// Erster extern angeschlossener Zielmonitor (`nil`, wenn keiner da ist).
    public init?() {
        guard let (s, p) = Self.externalServices().first(where: { Self.isTarget($0.0) }) else { return nil }
        service = s
        path = p
    }

    private static func write(_ s: AVService, _ payload: [UInt8]) -> Bool {
        var pkt: [UInt8] = [UInt8(0x80 | payload.count)] + payload
        var chk: UInt8 = 0x6E ^ 0x51
        for b in pkt { chk ^= b }
        pkt.append(chk)
        return IOAVServiceWriteI2C(s, 0x37, 0x51, &pkt, UInt32(pkt.count)) == KERN_SUCCESS
    }

    private static func request(_ c: Control) -> [UInt8] { c.vendor ? [0x01, 0xE0, c.code] : [0x01, c.code] }

    /// Liest und prüft die Antwort auf `request(c)`: Länge, Ergebniscode, angefragter Code, Prüfsumme.
    private static func receive(_ s: AVService, _ c: Control) -> Reading? {
        var rx = [UInt8](repeating: 0, count: 12)
        guard IOAVServiceReadI2C(s, 0x37, 0x51, &rx, 12) == KERN_SUCCESS,
              rx[0] == 0x6E, rx[1] == 0x88, rx[2] == 0x02, rx[3] == 0x00,
              rx[4] == (c.vendor ? 0xE0 : c.code), !c.vendor || rx[5] == c.code,
              rx[10] == rx[0..<10].reduce(0x50, ^) else { return nil }
        return Reading(max: Int(rx[6]) << 8 | Int(rx[7]), current: Int(rx[8]) << 8 | Int(rx[9]))
    }

    private static func transact(_ s: AVService, _ c: Control) -> Reading? {
        guard write(s, request(c)) else { return nil }
        usleep(60_000)
        return receive(s, c)
    }

    private func send(_ payload: [UInt8]) -> Bool {
        if Self.write(service, payload) { return true }
        // Nach Eingangswechsel/Neuverbindung ist der Dienst veraltet: neu suchen, aber nur am selben Anschluss.
        guard let (s, _) = Self.externalServices().first(where: { $0.1 == path }) else { return false }
        service = s
        return Self.write(service, payload)
    }

    public func read(_ c: Control) -> Reading? {
        guard send(Self.request(c)) else { return nil }
        usleep(60_000)
        return Self.receive(service, c)
    }

    /// Schreibt und liest zurück; bis zu 3 Versuche (siehe `WriteResult`).
    @discardableResult
    public func write(_ c: Control, _ value: Int) -> WriteResult {
        let v = UInt8(clamping: value)
        let payload: [UInt8] = c.vendor ? [0x03, 0xE0, c.code, 0x00, v] : [0x03, c.code, 0x00, v]
        var actual: Int?
        for attempt in 0..<3 {
            if attempt > 0 { usleep(150_000) }
            guard send(payload) else { continue }
            usleep(100_000)
            guard let r = read(c) else { return .unconfirmed }
            if r.current == Int(v) { return .confirmed }
            actual = r.current
        }
        return .rejected(actual: actual)
    }
}
