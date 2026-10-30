import Foundation
import FO48UKit

/// Schickt Mac-Werte (Last, Temperatur) an das Dashboard des Monitors. Nicht lesbare Felder werden nicht gesendet,
/// ihre Anzeige am Monitor wird ausgeschaltet und beim Beenden wieder eingeschaltet (Vorzustand ist nicht lesbar; vorher waren alle an).
@MainActor
final class Feeder: ObservableObject {
    static let shared = Feeder()
    private static let key = "dashboardEnabled"
    private static let interval: Duration = .seconds(2)

    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: Feeder.key)
    @Published private(set) var note: String?
    private var loop: Task<Void, Never>?
    private let stats = SystemStats()

    func start() {
        guard loop == nil else { return }
        enabled = true
        UserDefaults.standard.set(true, forKey: Self.key)
        loop = Task { [weak self] in
            var configured = false
            while !Task.isCancelled {
                guard let self else { return }
                configured = await self.tick(configured)
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        enabled = false; note = nil
        UserDefaults.standard.set(false, forKey: Self.key)
        ddcWorker.run { m in
            guard let m else { return }
            for f in SystemStats.available { m.sendDashboard(f, 0) }
            for f in DashField.allCases { m.setDashboardTitle(f.title, on: true) }
        }
    }

    /// Ein Takt auf der DDC-Queue; liefert, ob die Anzeige-Schalter gesetzt sind.
    private func tick(_ configured: Bool) async -> Bool {
        let stats = stats
        return await withCheckedContinuation { cont in
            ddcWorker.run { m in
                var ok = configured
                var message: String?
                if let m {
                    if m.read(.dashboardOn)?.current == 1 {
                        if !ok {
                            m.setDashboardTitle(DashField.mouseDPITitle, on: false)
                            for f in DashField.allCases { m.setDashboardTitle(f.title, on: SystemStats.available.contains(f)) }
                            ok = true
                        }
                        for f in SystemStats.available { if let v = stats.value(f) { m.sendDashboard(f, v) } }
                    } else {
                        message = tr("Dashboard am Monitor ist aus (im OSD einschalten).", "Dashboard is off on the monitor (switch it on in the OSD).")
                        ok = false
                    }
                } else {
                    message = tr("Kein Monitor", "No monitor")
                }
                Task { @MainActor in self.note = message }
                cont.resume(returning: ok)
            }
        }
    }
}
