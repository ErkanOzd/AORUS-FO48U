import Foundation
import IOKit
import FO48UKit

// Private Apple-API (Apple Silicon): Temperatursensoren ohne Admin-Rechte. Siehe docs/PROTOKOLL.md, Abschnitt „Dashboard“.
private typealias HIDClient = CFTypeRef
@_silgen_name("IOHIDEventSystemClientCreate") private func IOHIDEventSystemClientCreate(_ a: CFAllocator?) -> Unmanaged<HIDClient>?
@_silgen_name("IOHIDEventSystemClientSetMatching") private func IOHIDEventSystemClientSetMatching(_ c: HIDClient, _ m: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices") private func IOHIDEventSystemClientCopyServices(_ c: HIDClient) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty") private func IOHIDServiceClientCopyProperty(_ s: CFTypeRef, _ k: CFString) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDServiceClientCopyEvent") private func IOHIDServiceClientCopyEvent(_ s: CFTypeRef, _ t: Int64, _ o: Int32, _ opt: Int64) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetFloatValue") private func IOHIDEventGetFloatValue(_ e: CFTypeRef, _ f: Int32) -> Double

/// Liest Mac-Systemwerte für das Monitor-Dashboard. Nicht lesbare Werte sind `nil` und werden nicht gesendet.
final class SystemStats: @unchecked Sendable {
    private var prevTicks: [Int]?
    private var client: HIDClient?   // muss leben, solange die Sensoren benutzt werden
    private var sensors: [CFTypeRef] = []

    /// Felder, für die der Mac eine Quelle hat (Lüfter/Takt: keine; MacBook Air ohne Lüfter, Takt ungeprüft).
    static let available: [DashField] = [.cpuTemp, .cpuLoad, .gpuTemp, .gpuLoad]

    init() {
        guard let c = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        client = c
        _ = IOHIDEventSystemClientSetMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let all = IOHIDEventSystemClientCopyServices(c)?.takeRetainedValue() as? [CFTypeRef] ?? []
        // SoC-Temperatur: Sensoren „PMU tdie…“; CPU und GPU sind darin nicht getrennt belegt.
        sensors = all.filter { (IOHIDServiceClientCopyProperty($0, "Product" as CFString)?.takeRetainedValue() as? String)?.contains("tdie") == true }
        prevTicks = Self.ticks()
    }

    private static func ticks() -> [Int] {
        var info = host_cpu_load_info()
        var n = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &n) } }
        guard r == KERN_SUCCESS else { return [] }
        return [Int(info.cpu_ticks.0), Int(info.cpu_ticks.1), Int(info.cpu_ticks.2), Int(info.cpu_ticks.3)]
    }

    /// CPU-Auslastung in Prozent seit dem letzten Aufruf (Index 2 = CPU_STATE_IDLE).
    private func cpuLoad() -> Int? {
        let now = Self.ticks()
        defer { prevTicks = now }
        guard let prev = prevTicks, prev.count == 4, now.count == 4 else { return nil }
        let d = zip(now, prev).map { $0 - $1 }
        let total = d.reduce(0, +)
        return total > 0 ? (total - d[2]) * 100 / total : nil
    }

    private func gpuLoad() -> Int? {
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

    /// Höchste SoC-Temperatur in °C.
    private func temperature() -> Int? {
        let temps = sensors.compactMap { s -> Double? in
            guard let e = IOHIDServiceClientCopyEvent(s, 15, 0, 0)?.takeRetainedValue() else { return nil }
            let t = IOHIDEventGetFloatValue(e, Int32(15 << 16))
            return t > 0 && t < 150 ? t : nil
        }
        return temps.max().map { Int($0.rounded()) }
    }

    func value(_ f: DashField) -> Int? {
        switch f {
        case .cpuLoad: return cpuLoad()
        case .gpuLoad: return gpuLoad()
        case .cpuTemp, .gpuTemp: return temperature()
        default: return nil
        }
    }
}
