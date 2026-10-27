import SwiftUI

enum SliderFill {
  case fromStart   // minimum to thumb (volume)
  case full        // whole track (balance)
  case fromCenter  // center value to thumb (EQ gains)
}

/// Flat slider with a dark track, accent fill and a white thumb.
/// Double-click returns to `defaultValue` when one is given.
struct NeonSlider: View {
  @Environment(\.theme) private var theme
  @Binding var value: Double
  let range: ClosedRange<Double>
  var vertical = false
  var fill: SliderFill = .fromStart
  var centerValue: Double?
  var defaultValue: Double?
  var thickness: CGFloat = 6
  var thumb: CGFloat = 18
  var onChange: (Double) -> Void = { _ in }

  private func fraction (_ v: Double) -> CGFloat {
    CGFloat(min(1, max(0, (v - range.lowerBound) / (range.upperBound - range.lowerBound))))
  }

  var body: some View {
    GeometryReader { geometry in
      let length = vertical ? geometry.size.height : geometry.size.width
      let usable = length - thumb
      let position = fraction(value) * usable
      let center = fraction(centerValue ?? range.lowerBound) * usable
      let (fillStart, fillEnd): (CGFloat, CGFloat) = switch fill {
      case .fromStart: (0, position)
      case .full: (0, usable)
      case .fromCenter: (min(center, position), max(center, position))
      }

      ZStack(alignment: vertical ? .bottom : .leading) {
        // Track
        Capsule().fill(theme.track)
          .frame(width: vertical ? thickness : nil, height: vertical ? nil : thickness)
          .padding(vertical ? .vertical : .horizontal, thumb / 2)
        // Fill
        Capsule().fill(theme.accent)
          .frame(width: vertical ? thickness : fillEnd - fillStart, height: vertical ? fillEnd - fillStart : thickness)
          .offset(x: vertical ? 0 : thumb / 2 + fillStart, y: vertical ? -(thumb / 2 + fillStart) : 0)
        // Center tick
        if let centerValue, fill != .fromStart {
          let c = fraction(centerValue) * usable + thumb / 2
          Rectangle().fill(theme.tick)
            .frame(width: vertical ? thickness + 10 : 2, height: vertical ? 2 : thickness + 10)
            .offset(x: vertical ? 0 : c - 1, y: vertical ? -(c - 1) : 0)
        }
        // Thumb
        Circle().fill(.white)
          .frame(width: thumb, height: thumb)
          .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
          .offset(x: vertical ? 0 : position, y: vertical ? -position : 0)
      }
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: vertical ? .bottom : .leading)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { drag in
            let point = vertical ? length - drag.location.y : drag.location.x
            let t = Double(min(1, max(0, (point - thumb / 2) / usable)))
            value = range.lowerBound + t * (range.upperBound - range.lowerBound)
            onChange(value)
          }
      )
      .onTapGesture(count: 2) {
        if let defaultValue {
          value = defaultValue
          onChange(value)
        }
      }
    }
    .frame(width: vertical ? max(thumb, thickness) : nil, height: vertical ? nil : max(thumb, thickness))
  }
}
