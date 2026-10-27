import ServiceManagement
import SwiftUI

struct SettingsPanel: View {
  @EnvironmentObject private var app: AppState
  @Environment(\.theme) private var theme
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      NeonColorPicker(hex: $app.settings.accentHex)
      Divider1()
      Toggle("Process audio (off = bypass)", isOn: $app.settings.processingEnabled)
      Toggle("Show Live Input", isOn: $app.settings.showLiveInput)
      Toggle("Launch at login", isOn: $launchAtLogin)
        .onChange(of: launchAtLogin) { _, enabled in
          do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
          } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
          }
        }
    }
    .toggleStyle(.checkbox)
    .tint(theme.accent)
    .font(.system(size: 13))
    .padding(16)
    .frame(width: 360)
  }
}

/// Neon swatches, a hue slider where every position is neon, and a custom color well.
struct NeonColorPicker: View {
  @Binding var hex: String
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Neon Color").font(.system(size: 14, weight: .semibold))
        Spacer()
        Text(hex.uppercased()).font(.system(size: 12).monospacedDigit()).foregroundStyle(theme.accent)
        if hex.uppercased() != Theme.defaultAccentHex {
          Button("Reset") { hex = Theme.defaultAccentHex }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(theme.textSecondary)
        }
      }
      HStack(spacing: 0) {
        ForEach(Theme.neonSwatches, id: \.hex) { swatch in
          let selected = swatch.hex.uppercased() == hex.uppercased()
          Circle()
            .fill(Color(hex: swatch.hex))
            .frame(width: 24, height: 24)
            .overlay(Circle().strokeBorder(theme.card, lineWidth: selected ? 2 : 0).padding(-2))
            .overlay(Circle().strokeBorder(Color(hex: swatch.hex), lineWidth: selected ? 2 : 0).padding(-4))
            .shadow(color: Color(hex: swatch.hex).opacity(0.6), radius: selected ? 6 : 3)
            .frame(maxWidth: .infinity)
            .help(swatch.name)
            .onTapGesture { hex = swatch.hex }
        }
      }
      HStack(spacing: 12) {
        HueSlider(hue: Binding(get: { Theme.hue(ofHex: hex) }, set: { hex = Theme.neonHex(hue: $0) }))
        ColorPicker("Custom", selection: Binding(
          get: { Color(hex: hex) },
          set: { color in
            if let rgb = NSColor(color).usingColorSpace(.sRGB) {
              hex = RGB(r: rgb.redComponent, g: rgb.greenComponent, b: rgb.blueComponent).hex
            }
          }
        ), supportsOpacity: false)
        .font(.system(size: 12))
      }
    }
  }
}

/// Rainbow track of fully saturated hues.
private struct HueSlider: View {
  @Binding var hue: Double
  @Environment(\.theme) private var theme

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      ZStack(alignment: .leading) {
        Capsule()
          .fill(LinearGradient(colors: stride(from: 0.0, through: 360, by: 30).map { Color(hex: Theme.neonHex(hue: $0)) },
                               startPoint: .leading, endPoint: .trailing))
          .frame(height: 10)
          .shadow(color: theme.accent.opacity(0.35), radius: 4)
        Circle()
          .fill(.white)
          .overlay(Circle().strokeBorder(theme.accent, lineWidth: 3))
          .frame(width: 18, height: 18)
          .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
          .offset(x: CGFloat(hue / 360) * (width - 18))
      }
      .frame(height: 20)
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
        hue = Double(min(1, max(0, (drag.location.x - 9) / (width - 18)))) * 359
      })
    }
    .frame(height: 20)
    .help("Drag to pick any neon color")
  }
}

struct HelpPanel: View {
  @Environment(\.theme) private var theme
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("SubWave").font(.system(size: 15, weight: .semibold))
      Text("SubWave processes all of your Mac's audio: volume boost, balance and equalizer, then plays it on the output you pick.")
      Text("• Drag knobs and sliders; double-click to reset.\n• ★ saves your current sound as a favorite.\n• The power button bypasses all processing.\n• Quitting SubWave returns your Mac's audio to normal.")
        .foregroundStyle(theme.textSecondary)
    }
    .font(.system(size: 12))
    .padding(16)
    .frame(width: 320)
  }
}

/// Explains the Distortion Guard (peak limiter) switch.
struct DistortionGuardHelp: View {
  @Environment(\.theme) private var theme
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Distortion Guard").font(.system(size: 15, weight: .semibold))
      Text("Keeps the sound from crackling or distorting when it gets too loud.")
      Text("Big EQ boosts (like Funky's +12 dB bass) and Extra Volume can push loud moments past what your speakers can play cleanly. When that's about to happen, Distortion Guard turns just those moments down so they stay clean, then lets the volume come right back.")
        .foregroundStyle(theme.textSecondary)
      Text("• On: heavy bass and Extra Volume stay clean. Recommended.\n• Off: the sound is untouched, but big boosts may crackle.")
        .foregroundStyle(theme.textSecondary)
    }
    .font(.system(size: 12))
    .fixedSize(horizontal: false, vertical: true)
    .padding(16)
    .frame(width: 320)
  }
}
