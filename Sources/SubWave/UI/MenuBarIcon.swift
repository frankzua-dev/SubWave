import AppKit

/// Menu bar version of the app icon: a glowing purple speaker ring with a
/// cone in the middle and a wave sweeping through it.
enum MenuBarIcon {
  static let image: NSImage = {
    let size = NSSize(width: 22, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
      draw(in: rect)
      return true
    }
    // Keep the purple instead of letting macOS flatten it to black/white
    image.isTemplate = false
    image.accessibilityDescription = "SubWave"
    return image
  }()

  private static let purple = NSColor(srgbRed: 0.69, green: 0.15, blue: 1, alpha: 1)        // #B026FF
  private static let lightPurple = NSColor(srgbRed: 0.85, green: 0.62, blue: 1, alpha: 1)   // wave highlight
  private static let deepPurple = NSColor(srgbRed: 0.38, green: 0.08, blue: 0.62, alpha: 1)

  static func draw (in rect: NSRect) {
    let center = NSPoint(x: rect.midX, y: rect.midY)
    let ringRadius = min(rect.width, rect.height) / 2 - 1.6

    NSGraphicsContext.current?.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = purple.withAlphaComponent(0.8)
    glow.shadowBlurRadius = 2
    glow.set()

    // Speaker ring
    let ring = NSBezierPath(ovalIn: NSRect(x: center.x - ringRadius, y: center.y - ringRadius,
                                           width: ringRadius * 2, height: ringRadius * 2))
    ring.lineWidth = 1.6
    purple.setStroke()
    ring.stroke()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Cone (dome) in the middle
    let coneRadius = ringRadius * 0.42
    let cone = NSBezierPath(ovalIn: NSRect(x: center.x - coneRadius, y: center.y - coneRadius + 0.6,
                                           width: coneRadius * 2, height: coneRadius * 2))
    NSGradient(starting: lightPurple, ending: deepPurple)?.draw(in: cone, relativeCenterPosition: NSPoint(x: -0.3, y: 0.4))

    // Wave sweeping across, in front of the speaker
    let wave = NSBezierPath()
    let steps = 40
    for i in 0...steps {
      let t = CGFloat(i) / CGFloat(steps)
      let x = rect.minX + 0.5 + (rect.width - 1) * t
      // Rises on the left, dips under the speaker, rises again on the right (as in the app icon)
      let y = center.y - 0.8 + sin(t * 2 * .pi * 1.2 - 0.69) * 2.8
      i == 0 ? wave.move(to: NSPoint(x: x, y: y)) : wave.line(to: NSPoint(x: x, y: y))
    }
    wave.lineCapStyle = .round
    wave.lineJoinStyle = .round

    NSGraphicsContext.current?.saveGraphicsState()
    let waveGlow = NSShadow()
    waveGlow.shadowColor = purple
    waveGlow.shadowBlurRadius = 2.5
    waveGlow.set()
    wave.lineWidth = 2.2
    purple.setStroke()
    wave.stroke()
    NSGraphicsContext.current?.restoreGraphicsState()

    wave.lineWidth = 1
    lightPurple.setStroke()
    wave.stroke()
  }
}
