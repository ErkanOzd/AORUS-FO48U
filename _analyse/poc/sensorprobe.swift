// Sensor-Probe (nur lesend): Temperatursensoren über IOHIDEventSystemClient (private API, Apple Silicon, ohne Admin-Rechte).
import Foundation
import IOKit

typealias HIDClient = CFTypeRef
typealias HIDService = CFTypeRef
typealias HIDEvent = CFTypeRef
@_silgen_name("IOHIDEventSystemClientCreate") func IOHIDEventSystemClientCreate(_ a: CFAllocator?) -> Unmanaged<HIDClient>?
@_silgen_name("IOHIDEventSystemClientSetMatching") func IOHIDEventSystemClientSetMatching(_ c: HIDClient, _ m: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices") func IOHIDEventSystemClientCopyServices(_ c: HIDClient) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty") func IOHIDServiceClientCopyProperty(_ s: HIDService, _ k: CFString) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDServiceClientCopyEvent") func IOHIDServiceClientCopyEvent(_ s: HIDService, _ t: Int64, _ o: Int32, _ opt: Int64) -> Unmanaged<HIDEvent>?
@_silgen_name("IOHIDEventGetFloatValue") func IOHIDEventGetFloatValue(_ e: HIDEvent, _ f: Int32) -> Double

let kTemperature: Int64 = 15
guard let c = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { print("kein HID-Client"); exit(1) }
_ = IOHIDEventSystemClientSetMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
guard let arr = IOHIDEventSystemClientCopyServices(c)?.takeRetainedValue() as? [CFTypeRef] else { print("keine Dienste"); exit(1) }
print("Temperatursensoren: \(arr.count)")
for s in arr {
    let name = IOHIDServiceClientCopyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String ?? "?"
    guard let e = IOHIDServiceClientCopyEvent(s, kTemperature, 0, 0)?.takeRetainedValue() else { continue }
    let t = IOHIDEventGetFloatValue(e, Int32(kTemperature << 16))
    print(String(format: "%6.1f °C  %@", t, name))
}
