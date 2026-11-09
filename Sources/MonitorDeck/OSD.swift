import AppKit
import SwiftUI
import FO48UKit

/// Eigenes OSD im Stil des macOS-27-Systems (Glas-Kapsel oben rechts unter der Menüleiste, 16 Segmente).
/// Maße und Farben am System-OSD vermessen (Bildschirmaufnahme 2×, FO48U, 2026-11-09): Kapsel 300 × 64 pt, 9 pt unter der
/// Menüleiste, 52 pt vom rechten Rand; Symbolglyphe ab 20 pt (24 pt medium); Leiste ab 61 pt bis 30,5 pt vor dem Rand, Segmente 4 pt hoch, 0,5-pt-Fugen, runde Enden nur außen;
/// Symbol und volle Segmente RGB 209/209/212, leere ca. 19 % Weiß; 1 px heller Rand.
/// Das System-OSD lässt sich für DDC-Monitore nicht nutzen: `OSDManager` (OSD.framework) nimmt Aufrufe an, zeigt aber nichts [gemessen 2026-11-09].
@MainActor
enum OSD {
    enum Kind { case brightness, volume }

    private final class State: ObservableObject {
        @Published var kind = Kind.volume
        @Published var value = 0
        @Published var max = 100
    }

    private static let state = State()
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?
    private static let size = CGSize(width: 300, height: 64)
    private static let topGap: CGFloat = 9, rightGap: CGFloat = 52
    private static let visibleFor: Duration = .milliseconds(1500)

    /// Zeigt `value` von `max` auf dem Bildschirm des Monitors (sonst auf dem Hauptbildschirm).
    static func show(_ kind: Kind, value: Int, max: Int = 100) {
        state.kind = kind
        state.value = Swift.min(Swift.max(value, 0), Swift.max(max, 1))
        state.max = Swift.max(max, 1)
        let p = panel ?? makePanel()
        panel = p
        if let screen = NSScreen.screens.first(where: isMonitor) ?? NSScreen.main {
            let f = screen.frame, top = screen.visibleFrame.maxY
            p.setFrameOrigin(CGPoint(x: f.maxX - size.width - rightGap, y: top - size.height - topGap))
        }
        if !p.isVisible || p.alphaValue < 1 {
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 1 }
        }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: visibleFor)
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; p.animator().alphaValue = 0 }, completionHandler: {
                MainActor.assumeIsolated { if p.alphaValue == 0 { p.orderOut(nil) } }
            })
        }
    }

    private static func isMonitor(_ s: NSScreen) -> Bool {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID).map { CGDisplayVendorNumber($0) == AudioOutput.vendor } ?? false
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: Capsule_(state: state).frame(width: size.width, height: size.height))
        return p
    }

    private struct Capsule_: View {
        @ObservedObject var state: State
        private let segments = 16

        private var icon: String {
            switch state.kind {
            case .brightness: return "sun.max.fill"
            case .volume:
                let f = Double(state.value) / Double(state.max)
                // System: bei 62,5 % zwei, bei 69 % drei Wellen [gemessen]; die untere Grenze ist geschätzt.
                return f == 0 ? "speaker.slash.fill" : f < 0.34 ? "speaker.wave.1.fill" : f < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
            }
        }

        var body: some View {
            let filled = Int((Double(state.value) / Double(state.max) * Double(segments)).rounded())
            HStack(spacing: 0) {
                Image(systemName: icon).font(.system(size: 24, weight: .medium)).frame(width: 44.5, alignment: .leading)
                    .contentTransition(.symbolEffect(.replace))
                // Durchgehende Leiste mit runden Enden, Segmente durch 0,5-pt-Fugen getrennt (wie das System).
                HStack(spacing: 0.5) {
                    ForEach(0..<segments, id: \.self) { i in
                        Rectangle().fill(Color.white.opacity(i < filled ? 0.8 : 0.17))
                    }
                }
                .frame(height: 4)
                .clipShape(Capsule())
            }
            .foregroundStyle(Color.white.opacity(0.8))
            .padding(.leading, 16.5).padding(.trailing, 30.5)   // Symbolglyphe beginnt so bei 20 pt, Leiste bei 61 pt
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(Glass())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.kind == .brightness ? Control.brightness.name : Control.volume.name)
            .accessibilityValue("\(state.value)")
        }
    }

    /// Glas-Material ab macOS 26, sonst halbtransparentes Material.
    private struct Glass: ViewModifier {
        func body(content: Content) -> some View {
            if #available(macOS 26, *) {
                content.glassEffect(.regular, in: .capsule)
            } else {
                content.background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}
