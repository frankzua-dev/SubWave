import SwiftUI

/// Rotary knob: tick marks, a glowing arc from `arcOrigin` (the default value,
/// unless given) to the current value, and a dark cap with an accent dot.
/// Drag up/right to increase, double-click to return to `defaultValue`.
struct ArcKnob: View {
  @Environment(\.theme) private var theme
  @Binding var value: Double
  let range: ClosedRange<Double>
  var defaultValue = 0.0
  var arcOrigin: Double?
  var resetsOnDoubleClick = true
  var size: CGFloat = 104
  var onChange: () -> Void = {}

  private let sweep = 135.0 // degrees each side of straight up
  @State private var dragStart: Double?

  private func angle (for value: Double) -> Double {
    let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    return -sweep + min(1, max(0, t)) * 2 * sweep
  }

  var body: some View {
    let current = angle(for: value)
    let center = angle(for: min(max(arcOrigin ?? defaultValue, range.lowerBound), range.upperBound))
    ZStack {
      // Ticks
      ForEach(0..<11) { i in
        Capsule()
          .fill(theme.tick)
          .frame(width: 2.2, height: size * 0.035)
          .offset(y: -size * 0.48)
          .rotationEffect(.degrees(-sweep + Double(i) * 2 * sweep / 10))
      }
      // Track ring
      Circle()
        .stroke(theme.track, lineWidth: size * 0.045)
        .frame(width: size * 0.84, height: size * 0.84)
      // Value arc
      ArcShape(start: min(center, current), end: max(center, current))
        .stroke(theme.accent, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
        .frame(width: size * 0.84, height: size * 0.84)
        .shadow(color: theme.accent.opacity(0.5), radius: 3)
      // Bezel and cap
      Circle()
        .fill(theme.bezel)
        .frame(width: size * 0.74, height: size * 0.74)
        .shadow(color: .black.opacity(0.6), radius: 5, y: 4)
      Circle()
        .fill(RadialGradient(colors: [theme.capTop, theme.capBottom],
                             center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: size * 0.42))
        .overlay(Circle().strokeBorder(.white.opacity(0.07), lineWidth: 1))
        .frame(width: size * 0.66, height: size * 0.66)
      Circle()
        .strokeBorder(.black.opacity(0.25))
        .frame(width: size * 0.54, height: size * 0.54)
      // Indicator dot
      Circle()
        .fill(theme.accent)
        .frame(width: size * 0.07, height: size * 0.07)
        .shadow(color: theme.accent.opacity(0.8), radius: 2)
        .offset(y: -size * 0.23)
        .rotationEffect(.degrees(current))
    }
    .frame(width: size, height: size)
    .contentShape(Circle())
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { drag in
          if dragStart == nil { dragStart = value }
          let delta = (drag.translation.width - drag.translation.height) / 220
          let span = range.upperBound - range.lowerBound
          value = min(range.upperBound, max(range.lowerBound, dragStart! + delta * span))
          onChange()
        }
        .onEnded { _ in dragStart = nil }
    )
    .onTapGesture(count: 2) {
      guard resetsOnDoubleClick else { return }
      value = defaultValue
      onChange()
    }
  }
}

/// Arc between two angles (degrees, 0 = up, clockwise).
struct ArcShape: Shape {
  var start: Double
  var end: Double

  func path (in rect: CGRect) -> Path {
    var path = Path()
    guard end - start > 0.01 else { return path }
    path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                startAngle: .degrees(start - 90), endAngle: .degrees(end - 90), clockwise: false)
    return path
  }
}
