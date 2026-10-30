// Zeichnet das App-Icon und schreibt Resources/AppIcon.icns.
// Aufruf: swiftc -O scripts/make-icon.swift -o $TMPDIR/make-icon && $TMPDIR/make-icon Resources/AppIcon.icns
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = s / 1024
    func rr(_ r: CGRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad * u, yRadius: rad * u) }
    func c(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
    }

    // Plakette (macOS-Raster: 824 pt Fläche in 1024)
    let tile = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let tilePath = rr(tile, 185)
    NSGraphicsContext.current!.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = c(0x000000, 0.45); shadow.shadowBlurRadius = 24 * u; shadow.shadowOffset = NSSize(width: 0, height: -10 * u)
    shadow.set(); c(0x1a1a22).setFill(); tilePath.fill()
    NSGraphicsContext.current!.restoreGraphicsState()
    NSGradient(colors: [c(0x2b2b36), c(0x121218)])!.draw(in: tilePath, angle: -90)

    // Bildschirm: tiefschwarzes OLED-Panel, 16:9, schmaler Rand
    let scr = CGRect(x: 190 * u, y: 330 * u, width: 644 * u, height: 362 * u)
    let scrPath = rr(scr, 30)
    c(0x050507).setFill(); scrPath.fill()
    c(0x555568).setStroke(); scrPath.lineWidth = 5 * u; scrPath.stroke()
    // Standfuß
    c(0x3a3a48).setFill()
    rr(CGRect(x: 462 * u, y: 262 * u, width: 100 * u, height: 70 * u), 8).fill()
    rr(CGRect(x: 380 * u, y: 238 * u, width: 264 * u, height: 36 * u), 18).fill()

    // Drei Schieberegler als Bildinhalt
    let rows: [(CGFloat, CGFloat, UInt32, UInt32)] = [  // y, Position 0…1, Farbe links, Farbe rechts
        (610, 0.74, 0xffb020, 0xff5a1f),
        (511, 0.38, 0xff3d8b, 0xb04bff),
        (412, 0.58, 0x2de2e6, 0x3a86ff),
    ]
    let x0 = 262 * u, x1 = 762 * u
    for (y, p, a, b) in rows {
        let ty = y * u
        c(0xffffff, 0.10).setFill()
        rr(CGRect(x: x0, y: ty - 9 * u, width: x1 - x0, height: 18 * u), 9).fill()
        let kx = x0 + (x1 - x0) * p
        let fill = rr(CGRect(x: x0, y: ty - 9 * u, width: kx - x0, height: 18 * u), 9)
        NSGradient(colors: [c(a), c(b)])!.draw(in: fill, angle: 0)
        // Glühen + Knopf
        let glow = NSGradient(colors: [c(b, 0.55), c(b, 0)])!
        glow.draw(fromCenter: CGPoint(x: kx, y: ty), radius: 0, toCenter: CGPoint(x: kx, y: ty), radius: 48 * u, options: [])
        c(0xffffff).setFill()
        NSBezierPath(ovalIn: CGRect(x: kx - 21 * u, y: ty - 21 * u, width: 42 * u, height: 42 * u)).fill()
        c(b).setFill()
        NSBezierPath(ovalIn: CGRect(x: kx - 9 * u, y: ty - 9 * u, width: 18 * u, height: 18 * u)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.icns"
let dir = NSTemporaryDirectory() + "AppIcon-\(getpid()).iconset"
try? FileManager.default.removeItem(atPath: dir)
try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base).png"))
    try render(base * 2).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)@2x.png"))
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", dir, "-o", out]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(atPath: dir)
// Vorschau (nur bei Bedarf): PNG in 1024 neben die icns legen
if CommandLine.arguments.count > 2 { try render(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[2])) }
print("geschrieben:", out, p.terminationStatus == 0 ? "ok" : "Fehler")
