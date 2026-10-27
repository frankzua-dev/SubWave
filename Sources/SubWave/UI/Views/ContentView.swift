import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var app: AppState
  @State private var showSettings = false
  @State private var showHelp = false

  // Built here (not read from the environment) because this view provides it
  private var theme: Theme {
    Theme(accentHex: app.settings.accentHex, light: app.settings.lightMode)
  }

  private static let copyrightYear = Calendar.current.component(.year, from: Date())

  var body: some View {
    VStack(spacing: 0) {
      header
      VStack(spacing: 10) {
        if let error = app.engineError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12))
            .foregroundStyle(theme.errorText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(theme.errorBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        EqualizerCard()
        HStack(alignment: .top, spacing: 10) {
          VolumeCard()
          BalanceCard()
        }
        .fixedSize(horizontal: false, vertical: true)
        if app.settings.showLiveInput {
          LiveInputCard()
        }
        Spacer(minLength: 0)
      }
      .padding(EdgeInsets(top: 10, leading: 12, bottom: 6, trailing: 12))
      Text("Created by Francis Garcia · © \(String(Self.copyrightYear)) · All rights reserved")
        .font(.system(size: 10))
        .foregroundStyle(theme.textSecondary.opacity(0.8))
        .padding(.bottom, 8)
    }
    // Opens at its natural size; drag the corners to make it bigger
    .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(theme.window)
    .environment(\.theme, theme)
    .preferredColorScheme(app.settings.lightMode ? .light : .dark)
  }

  private var header: some View {
    ZStack {
      Text("SubWave")
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(theme.title)
      HStack(spacing: 10) {
        AppearanceSwitch()
        Spacer()
        CircleIconButton(systemName: "questionmark", help: "Help") { showHelp.toggle() }
          .popover(isPresented: $showHelp, arrowEdge: .bottom) { HelpPanel() }
        CircleIconButton(systemName: "gearshape", help: "Settings") { showSettings.toggle() }
          .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            SettingsPanel().environmentObject(app)
              .environment(\.theme, theme)
          }
        PowerButton()
      }
      .padding(.horizontal, 14)
    }
    .frame(height: 44)
    .background(theme.header)
    .overlay(alignment: .bottom) { Divider1() }
  }
}

/// Sun/moon switch between dark (default) and light mode.
private struct AppearanceSwitch: View {
  @EnvironmentObject private var app: AppState
  @Environment(\.theme) private var theme

  var body: some View {
    let light = app.settings.lightMode
    ZStack(alignment: light ? .trailing : .leading) {
      Capsule()
        .fill(theme.field)
        .overlay(Capsule().strokeBorder(theme.fieldBorder))
      HStack {
        Image(systemName: "moon.fill").opacity(light ? 0.55 : 0)
        Spacer()
        Image(systemName: "sun.max.fill").opacity(light ? 0 : 0.55)
      }
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(theme.textSecondary)
      .padding(.horizontal, 7)
      Circle()
        .fill(theme.accent)
        .overlay(
          Image(systemName: light ? "sun.max.fill" : "moon.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
        )
        .frame(width: 22, height: 22)
        .shadow(color: theme.accent.opacity(0.6), radius: 4)
        .padding(3)
    }
    .frame(width: 54, height: 28)
    .contentShape(Capsule())
    .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { app.settings.lightMode.toggle() } }
    .help(light ? "Switch to dark mode" : "Switch to light mode")
    .accessibilityLabel("Appearance")
    .accessibilityValue(light ? "Light" : "Dark")
  }
}

/// Turns all processing on or off (bypass); glows in the accent color when on.
private struct PowerButton: View {
  @EnvironmentObject private var app: AppState
  @Environment(\.theme) private var theme

  var body: some View {
    let on = app.settings.processingEnabled
    Button {
      app.settings.processingEnabled.toggle()
    } label: {
      Image(systemName: "power")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(on ? theme.accent : theme.icon)
        .frame(width: 28, height: 28)
        .background(theme.circleButton, in: Circle())
        .overlay(Circle().strokeBorder(on ? theme.accent : theme.outline, lineWidth: 1.5))
        .shadow(color: on ? theme.accent.opacity(0.5) : .clear, radius: 4)
    }
    .buttonStyle(.plain)
    .help(on ? "SubWave is on. Click to bypass all processing." : "Bypassed. Click to turn SubWave on.")
  }
}
