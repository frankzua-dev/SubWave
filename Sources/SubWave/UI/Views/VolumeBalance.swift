import SwiftUI

struct VolumeCard: View {
  @Environment(\.theme) private var theme
  @EnvironmentObject private var app: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      CardTitle(text: "Volume")
      VStack(spacing: 4) {
        // 0-100% is the device volume; with Extra Volume it continues to 200%
        ArcKnob(
          value: Binding(get: { app.volumeSliderValue }, set: { app.setVolumeSlider($0) }),
          range: 0...(app.settings.boostEnabled ? 2 : 1),
          arcOrigin: 0,
          resetsOnDoubleClick: false,
          size: 92
        )
        .disabled(!app.deviceHasVolume && !app.settings.boostEnabled)
        ValuePill(text: "\(Int((min(1, app.volumeSliderValue) * 100).rounded()))%", minWidth: 74)
      }
      .frame(maxWidth: .infinity)
      HStack(spacing: 12) {
        NeonCheckbox(isOn: $app.settings.boostEnabled)
          .help("Go beyond 100% with extra gain")
        Text("Extra Volume").font(.system(size: 14)).foregroundStyle(theme.textPrimary)
        Spacer()
        ValuePill(text: "\(Int((app.settings.boost * 100).rounded()))%", dimmed: !app.settings.boostEnabled)
      }
      .frame(minHeight: 28)
      .padding(.top, 4)
    }
    .padding(EdgeInsets(top: 11, leading: 14, bottom: 10, trailing: 14))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .card()
  }
}

/// Left and right channel levels, each on its own knob (double-click for 100%).
struct BalanceCard: View {
  @Environment(\.theme) private var theme
  @EnvironmentObject private var app: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      CardTitle(text: "Balance")
      HStack(alignment: .top) {
        channel("Left", \.leftLevel)
        Spacer()
        channel("Right", \.rightLevel)
      }
      .padding(.horizontal, 10)
    }
    .padding(EdgeInsets(top: 11, leading: 14, bottom: 10, trailing: 14))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .card()
  }

  private func channel (_ label: String, _ keyPath: WritableKeyPath<Settings, Double>) -> some View {
    VStack(spacing: 4) {
      Text(label).font(.system(size: 14)).foregroundStyle(theme.textPrimary)
      ArcKnob(
        value: Binding(get: { app.settings[keyPath: keyPath] },
                       set: { app.settings[keyPath: keyPath] = ($0 * 100).rounded() / 100 }),
        range: 0...1,
        defaultValue: 1,
        arcOrigin: 0,
        size: 72
      )
      ValuePill(text: "\(Int((app.settings[keyPath: keyPath] * 100).rounded()))%", minWidth: 64)
    }
  }
}
