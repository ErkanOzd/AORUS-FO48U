// DDC/CI-Probe (Get VCP; `settest` schreibt, nur für Sub-IDs aus docs/PROTOKOLL.md) über IOAVService (Apple Silicon, DP-Alt-Mode).
import Foundation
import IOKit

typealias AVService = CFTypeRef
@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<AVService>?
@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ s: AVService, _ chip: UInt32, _ off: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn
@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ s: AVService, _ chip: UInt32, _ off: UInt32, _ buf: UnsafeMutableRawPointer, _ len: UInt32) -> IOReturn

func services() -> [AVService] {
    var out: [AVService] = []
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &it) == KERN_SUCCESS else { return out }
    var e = IOIteratorNext(it)
    while e != 0 {
        let loc = IORegistryEntryCreateCFProperty(e, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
        if loc == "External", let s = IOAVServiceCreateWithService(kCFAllocatorDefault, e) { out.append(s.takeRetainedValue()) }
        IOObjectRelease(e); e = IOIteratorNext(it)
    }
    return out
}

/// Sendet [len|0x80, payload..., chk] an 0x37/0x51 und liest die Antwort.
func query(_ s: AVService, _ payload: [UInt8], readLen: Int = 12) -> [UInt8]? {
    var pkt: [UInt8] = [UInt8(0x80 | payload.count)] + payload
    var chk: UInt8 = 0x6E ^ 0x51
    for b in pkt { chk ^= b }
    pkt.append(chk)
    guard IOAVServiceWriteI2C(s, 0x37, 0x51, &pkt, UInt32(pkt.count)) == KERN_SUCCESS else { return nil }
    usleep(60_000)
    var rx = [UInt8](repeating: 0, count: readLen)
    guard IOAVServiceReadI2C(s, 0x37, 0x51, &rx, UInt32(readLen)) == KERN_SUCCESS else { return nil }
    return rx
}

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }

/// Setzt einen Wert (Standard-VCP: [03 vcp 00 wert]; herstellerspezifisch: [03 E0 sub 00 wert]).
func set(_ s: AVService, _ payload: [UInt8]) -> Bool {
    var pkt: [UInt8] = [UInt8(0x80 | payload.count)] + payload
    var chk: UInt8 = 0x6E ^ 0x51
    for b in pkt { chk ^= b }
    pkt.append(chk)
    return IOAVServiceWriteI2C(s, 0x37, 0x51, &pkt, UInt32(pkt.count)) == KERN_SUCCESS
}

func cur(_ r: [UInt8]?) -> Int? { guard let r = r, r.count >= 10 else { return nil }; return Int(r[8]) << 8 | Int(r[9]) }

let args = CommandLine.arguments
let list = services()
guard let s = list.first else { print("kein externer AVService"); exit(1) }
if args.count >= 4 && args[1] == "settest" {
    // settest <sub|vcp> <wert>: schreibt Wert, liest zurück, stellt den alten Wert wieder her
    let isE0 = args[2].hasPrefix("E0/")
    // Nur Sub-IDs mit belegter Wirkung (docs/PROTOKOLL.md); alles andere könnte Firmware-Funktionen auslösen.
    let erlaubtE0: Set<UInt8> = [0x02, 0x03, 0x07, 0x09, 0x0A, 0x0C, 0x22, 0x2C, 0x2D, 0x37]
    let erlaubtStd: Set<UInt8> = [0x10, 0x12, 0x62, 0x87]
    guard let id = UInt8(args[2].replacingOccurrences(of: "E0/", with: ""), radix: 16),
          let neu = UInt8(args[3]), isE0 ? erlaubtE0.contains(id) : erlaubtStd.contains(id) else {
        print("settest: Kennung nicht erlaubt oder Wert ungültig"); exit(2)
    }
    let q: [UInt8] = isE0 ? [0x01, 0xE0, id] : [0x01, id]
    let w: (UInt8) -> [UInt8] = { isE0 ? [0x03, 0xE0, id, 0x00, $0] : [0x03, id, 0x00, $0] }
    let alt = cur(query(s, q)); print("alt:", alt as Any)
    guard let a = alt else { exit(2) }
    print("setze \(neu):", set(s, w(neu))); usleep(300_000)
    print("zurückgelesen:", cur(query(s, q)) as Any)
    print("restore \(a):", set(s, w(UInt8(truncatingIfNeeded: a)))); usleep(300_000)
    print("nach restore:", cur(query(s, q)) as Any)
    exit(0)
}
print("externe AVServices: \(list.count)")
for (i, s) in list.enumerated() {
    print("--- Service \(i)")
    print("Get VCP 0x10 (Helligkeit): ", query(s, [0x01, 0x10]).map(hex) ?? "kein Ergebnis")
    // Herstellerspezifisch (Sidekick, GetOverDrive = E0 09 usw.)
    for (name, sub) in [("OverDrive", 0x09), ("Gamma", 0x07), ("BlackEQ", 0x02), ("ColorTemp", 0x03), ("Input", 0x2D), ("PictureMode", 0x2C), ("FreeSync", 0x0C), ("Firmware", 0x38)] as [(String, UInt8)] {
        print("Get E0/\(String(format: "%02X", sub)) \(name): ", query(s, [0x01, 0xE0, sub]).map(hex) ?? "kein Ergebnis")
    }
}
