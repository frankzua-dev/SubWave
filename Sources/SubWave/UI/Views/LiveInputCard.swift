import SwiftUI

/// Signal status, L/R level meters and a scrolling waveform of what SubWave is playing.
struct LiveInputCard: View {
  @EnvironmentObject private var app: AppState

  var body: some View {
    LiveInputContent(levels: app.levels)
  }
}

private struct LiveInputContent: View {
  @ObservedObject var levels: LiveLevels
  @Environment(\.theme) private var theme

  private static let segments = 16

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 14) {
        Text("LIVE INPUT").font(.system(size: 14, weight: .semibold)).kerning(0.4).foregroundStyle(theme.textPrimary)
        HStack(spacing: 8) {
          Circle()
            .fill(levels.signalDetected ? theme.accent : theme.switchKnobOff)
            .frame(width: 10, height: 10)
            .shadow(color: levels.signalDetected ? theme.accent.opacity(0.8) : .clear, radius: 3)
          Text(levels.signalDetected ? "Signal detected" : "No signal")
            .font(.system(size: 13))
            .foregroundStyle(levels.signalDetected ? theme.accent : theme.textSecondary)
        }
        Spacer()
        VStack(spacing: 4) {
          meter("L", levels.rms.0)
          meter("R", levels.rms.1)
        }
      }
      .padding(EdgeInsets(top: 9, leading: 16, bottom: 8, trailing: 16))
      Divider1()
      Waveform(history: levels.history, accent: theme.accent, accentLight: theme.accentLight)
        .frame(minHeight: 66, maxHeight: .infinity)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(LinearGradient(colors: [.black.opacity(theme.isLight ? 0.02 : 0.12), .black.opacity(theme.isLight ? 0.05 : 0.22)],
                                   startPoint: .top, endPoint: .bottom))
    }
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .card()
  }

  private func meter (_ label: String, _ level: Float) -> some View {
    let lit = Self.litSegments(level)
    return HStack(spacing: 1.5) {
      Text(label).font(.system(size: 10)).foregroundStyle(theme.textSecondary).frame(width: 12, alignment: .leading)
      ForEach(0..<Self.segments, id: \.self) { i in
        RoundedRectangle(cornerRadius: 1)
          .fill(i < lit ? theme.accent : theme.meterOff)
          .frame(width: 4, height: 9)
          .shadow(color: i < lit ? theme.accent.opacity(0.6) : .clear, radius: 1.5)
      }
    }
  }

  /// -60 dBFS ... 0 dBFS across the segments
  private static func litSegments (_ level: Float) -> Int {
    guard level > 0 else { return 0 }
    let db = 20 * log10(Double(level))
    return max(0, min(segments, Int(((db + 60) / 60 * Double(segments)).rounded())))
  }
}

private struct Waveform: View {
  let history: [Float]
  let accent: Color
  let accentLight: Color

  var body: some View {
    Canvas { context, size in
      let barWidth: CGFloat = 2
      let gap: CGFloat = 2.2
      let capacity = Int(size.width / (barWidth + gap))
      let middle = size.height / 2
      context.fill(Path(CGRect(x: 0, y: middle - 0.5, width: size.width, height: 1)), with: .color(accent.opacity(0.45)))

      let visible = history.suffix(capacity)
      let offset = capacity - visible.count
      let gradient = Gradient(stops: [
        .init(color: accent.opacity(0.35), location: 0),
        .init(color: accentLight, location: 0.5),
        .init(color: accent.opacity(0.35), location: 1)
      ])
      var bars = Path()
      for (i, amplitude) in visible.enumerated() {
        // Square root keeps quiet passages visible
        let height = max(2, CGFloat(sqrt(amplitude)) * (size.height - 8))
        let x = CGFloat(offset + i) * (barWidth + gap)
        bars.addRect(CGRect(x: x, y: middle - height / 2, width: barWidth, height: height))
      }
      context.addFilter(.shadow(color: accent.opacity(0.55), radius: 3))
      context.fill(bars, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }
  }
}
