import SwiftUI

struct EqualizerCard: View {
  @EnvironmentObject private var app: AppState
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      if app.settings.showEqualizer {
        Divider1()
        PresetsBar()
        Group {
          switch app.settings.eqMode {
          case .basic: BasicEQView()
          case .advanced: AdvancedEQView()
          }
        }
        .opacity(app.settings.processingEnabled ? 1 : 0.45)
      }
      Divider1().padding(.horizontal, 14)
      OutputRow()
    }
    .card()
  }

  private var toolbar: some View {
    HStack(spacing: 14) {
      NeonSegmented(options: EQMode.allCases.map { ($0.rawValue, $0) }, selection: $app.settings.eqMode)
      Spacer()
      Button {
        app.settings.showEqualizer.toggle()
      } label: {
        Image(systemName: app.settings.showEqualizer ? "eye.slash" : "eye")
          .font(.system(size: 16))
          .foregroundStyle(theme.textSecondary)
      }
      .buttonStyle(.plain)
      .help(app.settings.showEqualizer ? "Hide equalizer" : "Show equalizer")
    }
    .padding(.horizontal, 14)
    .frame(height: 54)
  }
}

// MARK: Presets and favorites

private struct PresetsBar: View {
  @EnvironmentObject private var app: AppState
  @Environment(\.theme) private var theme

  private enum NamePrompt: Identifiable {
    case save, favorite
    var id: Self { self }
  }
  @State private var prompt: NamePrompt?
  @State private var name = ""
  @State private var confirmDelete = false

  var body: some View {
    let selected = app.selectedPreset
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        IconButton(systemName: "arrow.counterclockwise", help: "Reset to Flat") { app.resetToFlat() }
        DropdownField(title: selected?.name ?? "Manual") {
          ForEach(app.presets.filter(\.isBuiltIn)) { preset in
            presetItem(preset)
          }
          let own = app.presets.filter { !$0.isBuiltIn }
          if !own.isEmpty {
            Divider()
            ForEach(own.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { preset in
              presetItem(preset)
            }
          }
        }
        IconButton(
          systemName: selected?.favorite == true ? "star.fill" : "star",
          color: selected?.favorite == true ? theme.accent : theme.icon,
          help: selected == nil ? "Save as Favorite" : (selected!.favorite ? "Remove from Favorites" : "Add to Favorites")
        ) {
          if let selected {
            app.toggleFavorite(selected)
          } else {
            ask(.favorite)
          }
        }
        IconButton(systemName: "plus", help: "Save Preset") { ask(.save) }
        if let selected, !selected.isBuiltIn {
          IconButton(systemName: "trash", help: "Delete Preset") { confirmDelete = true }
        }
      }
      if !app.favorites.isEmpty {
        HStack(spacing: 6) {
          Text("Favorites").font(.system(size: 12)).foregroundStyle(theme.textSecondary)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
              ForEach(app.favorites) { favorite in
                FavoriteChip(name: favorite.name, selected: favorite.id == app.selectedPreset?.id) {
                  app.select(favorite)
                }
              }
            }
          }
        }
      }
    }
    .padding(EdgeInsets(top: 12, leading: 14, bottom: 0, trailing: 14))
    .alert(prompt == .favorite ? "Name your favorite" : "Save preset", isPresented: Binding(
      get: { prompt != nil }, set: { if !$0 { prompt = nil } }
    )) {
      TextField("Preset name", text: $name)
      Button("Save") {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
          app.saveCurrent(as: trimmed, favorite: prompt == .favorite)
        }
        prompt = nil
      }
      Button("Cancel", role: .cancel) { prompt = nil }
    } message: {
      Text(app.presetNameExists(name.trimmingCharacters(in: .whitespaces))
           ? "A preset with this name exists and will be replaced."
           : "Saves the current settings so you can recall them anytime.")
    }
    .confirmationDialog("Delete \"\(selected?.name ?? "")\"?", isPresented: $confirmDelete) {
      Button("Delete", role: .destructive) {
        if let selected { app.delete(selected) }
      }
    }
  }

  private func presetItem (_ preset: Preset) -> some View {
    Button {
      app.select(preset)
    } label: {
      if preset.id == app.selectedPreset?.id {
        Label(preset.name, systemImage: "checkmark")
      } else if preset.favorite {
        Label(preset.name, systemImage: "star.fill")
      } else {
        Text(preset.name)
      }
    }
  }

  private func ask (_ kind: NamePrompt) {
    name = ""
    prompt = kind
  }
}

// MARK: Basic

private struct BasicEQView: View {
  @Environment(\.theme) private var theme
  @EnvironmentObject private var app: AppState
  @State private var showGuardHelp = false

  var body: some View {
    VStack(spacing: 10) {
      HStack(spacing: 12) {
        NeonSwitch(isOn: Binding(get: { app.settings.peakLimiter }, set: { app.settings.peakLimiter = $0; app.markManual() }))
        Text("Distortion Guard").font(.system(size: 14)).foregroundStyle(theme.textPrimary)
        Button { showGuardHelp.toggle() } label: {
          Image(systemName: "questionmark.circle")
            .font(.system(size: 13))
            .foregroundStyle(theme.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("What is Distortion Guard?")
        .popover(isPresented: $showGuardHelp, arrowEdge: .bottom) { DistortionGuardHelp() }
      }
      HStack {
        band("BASS", \.bass)
        Spacer()
        band("MID", \.mid)
        Spacer()
        band("TREBLE", \.treble)
      }
      .padding(.horizontal, 20)
    }
    .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
  }

  private func band (_ label: String, _ keyPath: WritableKeyPath<BasicGains, Double>) -> some View {
    VStack(spacing: 8) {
      Text(label).font(.system(size: 14, weight: .medium)).kerning(0.5).foregroundStyle(theme.textPrimary)
      ArcKnob(value: Binding(get: { app.settings.basic[keyPath: keyPath] },
                             set: { app.settings.basic[keyPath: keyPath] = ($0 * 10).rounded() / 10 }),
              range: -24...24, onChange: { app.markManual() })
      ValuePill(text: formatDB(app.settings.basic[keyPath: keyPath]), minWidth: 74)
    }
  }
}

// MARK: Advanced

private struct AdvancedEQView: View {
  @EnvironmentObject private var app: AppState
  @Environment(\.theme) private var theme

  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        Text("Global").font(.system(size: 13)).foregroundStyle(theme.textPrimary)
        NeonSlider(value: gain(\.global), range: -24...24, fill: .fromCenter, centerValue: 0, defaultValue: 0,
                   thumb: 16, onChange: { _ in app.markManual() })
        ValuePill(text: formatDB(app.settings.advanced.global), minWidth: 70)
      }
      HStack(alignment: .top, spacing: 0) {
        ForEach(AdvancedGains.labels.indices, id: \.self) { i in
          VStack(spacing: 6) {
            Text(AdvancedGains.labels[i]).font(.system(size: 11)).foregroundStyle(theme.textSecondary)
            NeonSlider(value: gain(\.bands[i]), range: -24...24, vertical: true, fill: .fromCenter, centerValue: 0,
                       defaultValue: 0, thickness: 5, thumb: 14, onChange: { _ in app.markManual() })
              .frame(height: 124)
            Text(formatDB(app.settings.advanced.bands[i], compact: true))
              .font(.system(size: 10).monospacedDigit())
              .foregroundStyle(theme.accent)
          }
          .frame(maxWidth: .infinity)
        }
      }
    }
    .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
  }

  private func gain (_ keyPath: WritableKeyPath<AdvancedGains, Double>) -> Binding<Double> {
    Binding(get: { app.settings.advanced[keyPath: keyPath] },
            set: { app.settings.advanced[keyPath: keyPath] = ($0 * 2).rounded() / 2 })
  }
}

private func formatDB (_ value: Double, compact: Bool = false) -> String {
  let sign = value > 0 ? "+" : ""
  return compact ? "\(sign)\(String(format: "%.1f", value))" : "\(sign)\(String(format: "%.1f", value)) dB"
}

// MARK: Output

private struct OutputRow: View {
  @Environment(\.theme) private var theme
  @EnvironmentObject private var app: AppState

  var body: some View {
    HStack(spacing: 14) {
      Text("Output").font(.system(size: 14)).foregroundStyle(theme.textPrimary)
      DropdownField(title: app.currentOutput?.name ?? "No output", icon: app.currentOutput?.symbol ?? "speaker.slash") {
        Button {
          app.settings.outputUID = nil
          app.restartEngine()
        } label: {
          if app.settings.outputUID == nil {
            Label("System Default", systemImage: "checkmark")
          } else {
            Text("System Default")
          }
        }
        Divider()
        ForEach(app.devices) { device in
          Button {
            app.selectOutput(device)
          } label: {
            if device.uid == app.currentOutput?.uid {
              Label(device.name, systemImage: "checkmark")
            } else {
              Text(device.name)
            }
          }
        }
      }
      SpeakerGrille()
    }
    .padding(.horizontal, 14)
    .frame(height: 56)
  }
}

/// Decorative dotted speaker grille.
private struct SpeakerGrille: View {
  @Environment(\.theme) private var theme
  var body: some View {
    Canvas { context, size in
      for row in 0..<3 {
        let count = 9
        for column in 0..<count {
          let x = CGFloat(column) * 9 + (row % 2 == 0 ? 4 : 8.5)
          let y = CGFloat(row) * 7 + 4
          context.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)),
                       with: .color(theme.grille))
        }
      }
    }
    .frame(width: 86, height: 22)
  }
}
