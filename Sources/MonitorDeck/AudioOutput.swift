import CoreAudio
import CoreGraphics

/// Standard-Tonausgabe des Macs (CoreAudio). Der Monitor bietet als Audiogerät keine eigene Lautstärkeregelung an,
/// macOS kann ihn also nicht regeln; das übernimmt DDC [gemessen 2026-11-09].
enum AudioOutput {
    /// EISA-Herstellerkennung „GBT“ (Gigabyte).
    static let vendor: UInt32 = 0x1C54

    /// `true`, wenn die Standard-Tonausgabe ein angeschlossener Gigabyte-Monitor ist.
    /// Die Geräte-UID beginnt mit Hersteller und Modell des Displays (`1C540048…` für Modell `0x4800`, Bytes vertauscht [gemessen 2026-11-09]);
    /// ohne diese Form zählt Hersteller „GBT“ an DisplayPort/HDMI.
    static func isMonitor() -> Bool {
        guard let dev = defaultDevice(), [kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI].contains(transport(dev)) else { return false }
        let uid = string(dev, kAudioDevicePropertyDeviceUID)?.uppercased() ?? ""
        let models = monitorModels()
        if models.contains(where: { m in [m, m.byteSwapped].contains { uid.hasPrefix(String(format: "%04X%04X", vendor, $0)) } }) { return true }
        return !models.isEmpty && string(dev, kAudioObjectPropertyManufacturer) == "GBT"
    }

    /// Name der Standard-Tonausgabe (z. B. „MacBook Air-Lautsprecher“).
    static func name() -> String? { defaultDevice().flatMap { string($0, kAudioObjectPropertyName) } }

    /// Modellnummern der angeschlossenen Gigabyte-Displays.
    private static func monitorModels() -> [UInt16] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), n: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &n) == .success else { return [] }
        return ids.prefix(Int(n)).filter { CGDisplayVendorNumber($0) == vendor }.map { UInt16(truncatingIfNeeded: CGDisplayModelNumber($0)) }
    }

    private static func address(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultDevice() -> AudioDeviceID? {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static func transport(_ dev: AudioDeviceID) -> UInt32 {
        var a = address(kAudioDevicePropertyTransportType)
        var t: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &t) == noErr ? t : 0
    }

    private static func string(_ dev: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = address(sel)
        var s: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &s) == noErr, let s else { return nil }
        return s.takeRetainedValue() as String
    }
}
