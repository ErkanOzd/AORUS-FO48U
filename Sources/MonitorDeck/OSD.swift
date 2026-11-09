import AppKit
import SwiftUI
import FO48UKit

/// Eigenes OSD im Stil des macOS-27-Systems (Glas-Kapsel oben rechts unter der Menüleiste, 16 Segmente).
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
    private static let size = CGSize(width: 300, height: 60)
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
            p.setFrameOrigin(CGPoint(x: f.maxX - size.width - 12, y: top - size.height - 8))
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
                return f == 0 ? "speaker.slash.fill" : f < 0.34 ? "speaker.wave.1.fill" : f < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
            }
        }

        var body: some View {
            let filled = Int((Double(state.value) / Double(state.max) * Double(segments)).rounded())
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 22, weight: .medium)).frame(width: 30)
                    .contentTransition(.symbolEffect(.replace))
                HStack(spacing: 3) {
                    ForEach(0..<segments, id: \.self) { i in
                        Capsule().fill(.primary.opacity(i < filled ? 1 : 0.25)).frame(height: 4)
                    }
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(Glass())
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
