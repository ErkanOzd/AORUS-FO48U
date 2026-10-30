// Dashboard-Probe: liest E0/18 (DASHOn) und E0/19 (DASHLocation); `send` schickt Mac-Werte an das Monitor-Dashboard.
// Paketformat aus RTKCmd_x64.dll (SetCPU_Temp usw.) [Dekompilat]: [03 E0 <sub> hi mid lo sign], Wert = hi*10000 + mid*100 + lo.
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

func packet(_ payload: [UInt8]) -> [UInt8] {
    var pkt: [UInt8] = [UInt8(0x80 | payload.count)] + payload
    var chk: UInt8 = 0x6E ^ 0x51
    for b in pkt { chk ^= b }
    pkt.append(chk)
    return pkt
}

func query(_ s: AVService, _ payload: [UInt8], readLen: Int = 12) -> [UInt8]? {
    var pkt = packet(payload)
    guard IOAVServiceWriteI2C(s, 0x37, 0x51, &pkt, UInt32(pkt.count)) == KERN_SUCCESS else { return nil }
    usleep(60_000)
    var rx = [UInt8](repeating: 0, count: readLen)
    guard IOAVServiceReadI2C(s, 0x37, 0x51, &rx, UInt32(readLen)) == KERN_SUCCESS else { return nil }
    return rx
}

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }

/// Sendet einen Dashboard-Wert (ganzzahlig, 0…2 550 000) an Sub-ID `sub`.
func sendDash(_ s: AVService, _ sub: UInt8, _ value: Int) -> Bool {
    let v = abs(value)
    var pkt = packet([0x03, 0xE0, sub, UInt8(truncatingIfNeeded: v / 10000), UInt8(truncatingIfNeeded: v % 10000 / 100), UInt8(truncatingIfNeeded: v % 100), value < 0 ? 1 : 0])
    return IOAVServiceWriteI2C(s, 0x37, 0x51, &pkt, UInt32(pkt.count)) == KERN_SUCCESS
}

func cpuTicks() -> [Int] {
    var info = host_cpu_load_info(); var n = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &n) } }
    return [Int(info.cpu_ticks.0), Int(info.cpu_ticks.1), Int(info.cpu_ticks.2), Int(info.cpu_ticks.3)]
}
var prev = cpuTicks()
/// CPU-Auslastung in Prozent seit dem letzten Aufruf (Index 2 = CPU_STATE_IDLE).
func cpuUsage() -> Int {
    let c = cpuTicks()
    let d = zip(c, prev).map { $0 - $1 }
    prev = c
    let total = d.reduce(0, +)
    return total > 0 ? (total - d[2]) * 100 / total : 0
}

/// GPU-Auslastung in Prozent aus IOAccelerator (Apple Silicon).
func gpuUsage() -> Int? {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(it) }
    var e = IOIteratorNext(it)
    while e != 0 {
        defer { IOObjectRelease(e); e = IOIteratorNext(it) }
        if let p = IORegistryEntryCreateCFProperty(e, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
           let u = p["Device Utilization %"] as? Int { return u }
    }
    return nil
}

let args = CommandLine.arguments
guard let s = services().first else { print("kein externer AVService"); exit(1) }

print("Get E0/18 DASHOn:      ", query(s, [0x01, 0xE0, 0x18]).map(hex) ?? "kein Ergebnis")
print("Get E0/19 DASHLocation:", query(s, [0x01, 0xE0, 0x19]).map(hex) ?? "kein Ergebnis")
if args.count >= 2 && args[1] == "titles" {
    // titles: liest die Anzeige-Schalter E0/40…E0/48 (Maus-DPI, CPU Temp/Takt/Lüfter/Last, GPU Temp/Takt/Lüfter/Last)
    let names = ["Maus-DPI", "CPU Temp", "CPU Takt", "CPU Lüfter", "CPU Last", "GPU Temp", "GPU Takt", "GPU Lüfter", "GPU Last"]
    for (i, n) in names.enumerated() {
        let r = query(s, [0x01, 0xE0, UInt8(0x40 + i)])
        print(String(format: "E0/%02X %@:", 0x40 + i, n), r.map(hex) ?? "kein Ergebnis", r.map { "→ aktuell \(Int($0[8]) << 8 | Int($0[9]))" } ?? "")
    }
    exit(0)
}
print("Mac: CPU \(cpuUsage())% (erster Wert seit Start unzuverlässig), GPU \(gpuUsage().map(String.init) ?? "n/a")%")

if args.count >= 2 && args[1] == "send" {
    // send [Sekunden]: sendet alle acht Felder im Sekundentakt (150 ms Abstand wie der Sidekick); CPU-/GPU-Last live, übrige Testwerte; danach alles auf 0
    let secs = args.count >= 3 ? Int(args[2]) ?? 10 : 10
    let test: [(UInt8, String, Int?)] = [(0x1A, "CPU Temp", 41), (0x1B, "CPU Takt", 3200), (0x1C, "CPU Lüfter", 1500), (0x1D, "CPU Last", nil),
                                         (0x1E, "GPU Temp", 52), (0x1F, "GPU Takt", 1400), (0x20, "GPU Lüfter", 1800), (0x21, "GPU Last", nil)]
    for _ in 0..<secs {
        for (sub, name, fixed) in test {
            let v = fixed ?? (sub == 0x1D ? cpuUsage() : gpuUsage() ?? 0)
            print("\(name) \(v) -> \(sendDash(s, sub, v))", terminator: "; ")
            usleep(150_000)
        }
        print("")
        usleep(600_000)
    }
    print("zurück auf 0:", test.map { sendDash(s, $0.0, 0) })
}
