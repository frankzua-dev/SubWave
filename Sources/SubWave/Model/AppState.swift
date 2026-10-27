import AppKit
import Combine
import CoreAudio
import SwiftUI

/// Everything the user can change, saved between launches.
struct Settings: Codable, Equatable {
  /// Bumped when new defaults should be applied once to existing users
  static let currentDefaultsVersion = 5

  var defaultsVersion = Settings.currentDefaultsVersion
  var processingEnabled = true
  var boostEnabled = false
  var boost = 0.0                 // extra software gain, 0...1 (0-100%)
  var leftLevel = 1.0             // per-channel level, 0...1
  var rightLevel = 1.0
  var balance = 0.0               // replaced by left/right levels; read only to migrate
  var eqMode = EQMode.basic
  var showEqualizer = true
  var basic = BuiltInPresets.funky.basic
  var advanced = AdvancedGains()
  var peakLimiter = true          // Distortion Guard
  var selectedBasicPresetID: String? = BuiltInPresets.funkyID  // nil = unsaved ("Manual") settings
  var selectedAdvancedPresetID: String? = BuiltInPresets.flatID
  var accentHex = Theme.defaultAccentHex
  var outputUID: String?          // nil = follow the system's default output
  var showLiveInput = true
  var lightMode = false

  init () {}

  // Missing keys (e.g. settings saved by an older version) keep their defaults
  init (from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable> (_ key: CodingKeys, _ fallback: T) -> T {
      (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    let d = Settings()
    defaultsVersion = value(.defaultsVersion, 0)
    processingEnabled = value(.processingEnabled, d.processingEnabled)
    boostEnabled = value(.boostEnabled, d.boostEnabled)
    boost = value(.boost, d.boost)
    balance = value(.balance, d.balance)
    leftLevel = value(.leftLevel, d.leftLevel)
    rightLevel = value(.rightLevel, d.rightLevel)
    eqMode = value(.eqMode, d.eqMode)
    showEqualizer = value(.showEqualizer, d.showEqualizer)
    basic = value(.basic, d.basic)
    advanced = value(.advanced, d.advanced)
    peakLimiter = value(.peakLimiter, d.peakLimiter)
    selectedBasicPresetID = value(.selectedBasicPresetID, nil)
    selectedAdvancedPresetID = value(.selectedAdvancedPresetID, nil)
    accentHex = value(.accentHex, d.accentHex)
    outputUID = value(.outputUID, nil)
    showLiveInput = value(.showLiveInput, d.showLiveInput)
    lightMode = value(.lightMode, d.lightMode)
  }

  /// One-time updates for settings saved before new defaults existed
  mutating func migrate () {
    if defaultsVersion < 2 {
      // Funky became the default sound and neon purple the default color
      basic = BuiltInPresets.funky.basic
      peakLimiter = BuiltInPresets.funky.peakLimiter
      selectedBasicPresetID = BuiltInPresets.funkyID
      eqMode = .basic
      accentHex = Theme.defaultAccentHex
    }
    if defaultsVersion < 3 {
      // Balance became two level knobs; keep the same left/right result
      leftLevel = min(1, 1 - balance)
      rightLevel = min(1, 1 + balance)
      balance = 0
    }
    if defaultsVersion < 4 {
      // Distortion Guard became on by default, Funky included
      peakLimiter = true
    }
    if defaultsVersion < 5, selectedAdvancedPresetID?.hasPrefix("builtin.advanced.") == true {
      // The Advanced presets other than Flat were removed; fall back to Flat
      advanced = AdvancedGains()
      selectedAdvancedPresetID = BuiltInPresets.flatID
    }
    defaultsVersion = Settings.currentDefaultsVersion
  }
}

@MainActor
final class AppState: ObservableObject {
  @Published var settings: Settings { didSet { settingsChanged(from: oldValue) } }
  @Published private(set) var basicPresets: [Preset]
  @Published private(set) var advancedPresets: [Preset]

  @Published private(set) var devices: [OutputDevice] = []
  @Published private(set) var currentOutput: OutputDevice?
  @Published private(set) var deviceVolume: Float = 0.5
  @Published private(set) var deviceHasVolume = true
  @Published private(set) var engineError: String?

  let processor = AudioProcessor()
  let levels = LiveLevels()
  private lazy var engine = TapEngine(processor: processor)
  // Engine setup can block (e.g. while macOS asks for audio permission), so it
  // runs off the main thread; the queue also keeps restarts in order
  private let engineQueue = DispatchQueue(label: "com.subwave.engine")
  private var sampleRate: Double = 48_000
  private var engineGeneration = 0

  private var listeners: [AudioSystem.ListenerToken] = []
  private var outputListeners: [AudioSystem.ListenerToken] = []
  private var meterTimer: Timer?
  private let defaults = UserDefaults.standard

  init () {
    var loaded = Self.load(Settings.self, key: "settings") ?? Settings()
    loaded.migrate()
    settings = loaded
    basicPresets = Self.mergeBuiltIns(BuiltInPresets.basic, Self.load([Preset].self, key: "basicPresets") ?? [])
    advancedPresets = Self.mergeBuiltIns(BuiltInPresets.advanced, Self.load([Preset].self, key: "advancedPresets") ?? [])
    save(settings, key: "settings") // keep any migration
  }

  // MARK: Lifecycle

  func start () {
    refreshDevices()
    listeners = [
      AudioSystem.listen(AudioSystem.system, AudioSystem.address(kAudioHardwarePropertyDevices)) { [weak self] in
        self?.devicesChanged()
      },
      AudioSystem.listen(AudioSystem.system, AudioSystem.address(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in
        guard let self, self.settings.outputUID == nil else { return }
        self.restartEngine()
      }
    ]
    restartEngine()
    meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.pollMeter() }
    }
  }

  func stop () {
    meterTimer?.invalidate()
    // Give the engine a moment to tear down so system audio is restored before exit
    let engine = self.engine
    let done = DispatchSemaphore(value: 0)
    engineQueue.async {
      engine.stop()
      done.signal()
    }
    _ = done.wait(timeout: .now() + 2)
  }

  /// (Re)builds the audio pipeline for the chosen output device.
  func restartEngine () {
    let engine = self.engine
    guard let output = resolvedOutput() else {
      engineQueue.async { engine.stop() }
      engineError = "No output device found."
      return
    }
    currentOutput = output
    watchOutput(output)
    engineGeneration += 1
    let generation = engineGeneration
    engineQueue.async { [weak self] in
      var failure: String?
      do {
        try engine.start(outputUID: output.uid)
      } catch {
        failure = "\(error)"
      }
      let rate = engine.sampleRate
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self, generation == self.engineGeneration else { return }
          self.engineError = failure
          self.sampleRate = rate
          self.applyProcessing()
        }
      }
    }
    applyProcessing()
  }

  private func resolvedOutput () -> OutputDevice? {
    if let uid = settings.outputUID, let device = devices.first(where: { $0.uid == uid }) {
      return device
    }
    if let id = AudioSystem.defaultOutputDeviceID, let device = devices.first(where: { $0.id == id }) {
      return device
    }
    return devices.first
  }

  private func refreshDevices () {
    devices = AudioSystem.outputDevices()
  }

  private func devicesChanged () {
    let previous = currentOutput?.uid
    refreshDevices()
    // Restart if our device disappeared
    if let previous, !devices.contains(where: { $0.uid == previous }) {
      restartEngine()
    }
  }

  private func watchOutput (_ device: OutputDevice) {
    syncVolume()
    var tokens = [
      AudioSystem.listen(device.id, AudioSystem.address(kAudioDevicePropertyNominalSampleRate)) { [weak self] in
        self?.restartEngine()
      }
    ]
    for element in [kAudioObjectPropertyElementMain, 1, 2] as [AudioObjectPropertyElement] {
      tokens.append(AudioSystem.listen(device.id, AudioSystem.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, element)) { [weak self] in
        self?.syncVolume()
      })
    }
    outputListeners = tokens
  }

  // MARK: Volume (device volume up to 100%, software boost beyond)

  private func syncVolume () {
    guard let device = currentOutput else { return }
    deviceHasVolume = AudioSystem.hasVolume(device.id)
    deviceVolume = AudioSystem.volume(device.id) ?? 1
  }

  /// Slider value: 0...1 is the device volume; 1...2 is boost (when enabled).
  var volumeSliderValue: Double {
    Double(deviceVolume) + (settings.boostEnabled ? settings.boost : 0)
  }

  func setVolumeSlider (_ value: Double) {
    guard let device = currentOutput else { return }
    let volume = Float(min(1, max(0, value)))
    if deviceHasVolume {
      AudioSystem.setVolume(device.id, volume)
      deviceVolume = volume
    }
    if settings.boostEnabled {
      settings.boost = max(0, value - 1)
    }
  }

  // MARK: Settings

  private func settingsChanged (from old: Settings) {
    save(settings, key: "settings")
    if old.outputUID != settings.outputUID {
      restartEngine()
    } else {
      applyProcessing()
    }
    if !settings.boostEnabled && settings.boost != 0 {
      settings.boost = 0
    }
  }

  private func applyProcessing () {
    var processing = ProcessingSettings()
    let s = settings
    let rate = sampleRate
    // Keep filter frequencies safely below Nyquist
    func freq (_ f: Double) -> Double { min(f, rate * 0.45) }

    if s.processingEnabled {
      switch s.eqMode {
      case .basic:
        processing.filters = [
          .lowShelf(frequency: freq(110), gainDB: s.basic.bass, sampleRate: rate),
          .peaking(frequency: freq(1_000), gainDB: s.basic.mid, q: 0.9, sampleRate: rate),
          .highShelf(frequency: freq(6_500), gainDB: s.basic.treble, sampleRate: rate)
        ]
      case .advanced:
        processing.filters = zip(AdvancedGains.frequencies, s.advanced.bands).map { f, gain in
          .peaking(frequency: freq(f), gainDB: gain, q: 1.41, sampleRate: rate)
        }
        processing.preGain = Float(pow(10, s.advanced.global / 20))
      }
      processing.outputGain = Float(1 + (s.boostEnabled ? s.boost : 0))
      processing.leftGain = Float(min(1, max(0, s.leftLevel)))
      processing.rightGain = Float(min(1, max(0, s.rightLevel)))
      processing.limiterEnabled = s.peakLimiter
    }
    processor.update(processing)
  }

  func selectOutput (_ device: OutputDevice) {
    // Picking the system default again means "follow the default"
    settings.outputUID = device.id == AudioSystem.defaultOutputDeviceID ? nil : device.uid
    if settings.outputUID == nil { restartEngine() }
  }

  // MARK: Presets

  var presets: [Preset] {
    settings.eqMode == .basic ? basicPresets : advancedPresets
  }

  var selectedPresetID: String? {
    settings.eqMode == .basic ? settings.selectedBasicPresetID : settings.selectedAdvancedPresetID
  }

  /// The chosen preset, or else the first one the current settings match
  /// exactly (so dialing Funky back in by hand still shows "Funky")
  var selectedPreset: Preset? {
    if let id = selectedPresetID, let preset = presets.first(where: { $0.id == id }) {
      return preset
    }
    return presets.first { preset in
      switch settings.eqMode {
      case .basic: preset.basic == settings.basic && preset.peakLimiter == settings.peakLimiter
      case .advanced: preset.advanced == settings.advanced
      }
    }
  }

  var favorites: [Preset] {
    presets.filter(\.favorite).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  func select (_ preset: Preset) {
    switch settings.eqMode {
    case .basic:
      settings.basic = preset.basic
      settings.peakLimiter = preset.peakLimiter
      settings.selectedBasicPresetID = preset.id
    case .advanced:
      settings.advanced = preset.advanced
      settings.selectedAdvancedPresetID = preset.id
    }
  }

  func resetToFlat () {
    if let flat = presets.first(where: { $0.id == BuiltInPresets.flatID }) {
      select(flat)
    }
  }

  /// Any manual change detaches the settings from the selected preset.
  func markManual () {
    switch settings.eqMode {
    case .basic: settings.selectedBasicPresetID = nil
    case .advanced: settings.selectedAdvancedPresetID = nil
    }
  }

  /// Saves the current settings as a preset (replacing a user preset with the same name).
  @discardableResult
  func saveCurrent (as name: String, favorite: Bool = false) -> Preset {
    var preset = Preset(name: name, favorite: favorite, basic: settings.basic, advanced: settings.advanced, peakLimiter: settings.peakLimiter)
    updatePresets { list in
      if let index = list.firstIndex(where: { !$0.isBuiltIn && $0.name == name }) {
        preset.id = list[index].id
        preset.favorite = favorite || list[index].favorite
        list[index] = preset
      } else {
        list.append(preset)
      }
    }
    select(preset)
    return preset
  }

  func toggleFavorite (_ preset: Preset) {
    updatePresets { list in
      if let index = list.firstIndex(where: { $0.id == preset.id }) {
        list[index].favorite.toggle()
      }
    }
  }

  func delete (_ preset: Preset) {
    guard !preset.isBuiltIn else { return }
    updatePresets { $0.removeAll { $0.id == preset.id } }
    if selectedPresetID == preset.id { markManual() }
  }

  func presetNameExists (_ name: String) -> Bool {
    presets.contains { !$0.isBuiltIn && $0.name == name }
  }

  private func updatePresets (_ change: (inout [Preset]) -> Void) {
    switch settings.eqMode {
    case .basic:
      change(&basicPresets)
      save(basicPresets.filter { !$0.isBuiltIn || $0.favorite }, key: "basicPresets")
    case .advanced:
      change(&advancedPresets)
      save(advancedPresets.filter { !$0.isBuiltIn || $0.favorite }, key: "advancedPresets")
    }
  }

  /// Built-ins always come from code; saved copies only carry the favorite flag.
  private static func mergeBuiltIns (_ builtIns: [Preset], _ saved: [Preset]) -> [Preset] {
    let favorites = Set(saved.filter { $0.isBuiltIn && $0.favorite }.map(\.id))
    let merged = builtIns.map { preset -> Preset in
      var preset = preset
      preset.favorite = favorites.contains(preset.id)
      return preset
    }
    return merged + saved.filter { !$0.isBuiltIn }
  }

  // MARK: Meter

  private func pollMeter () {
    levels.push(processor.meter.read())
  }

  // MARK: Persistence

  private static func load<T: Decodable> (_ type: T.Type, key: String) -> T? {
    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  private func save<T: Encodable> (_ value: T, key: String) {
    if let data = try? JSONEncoder().encode(value) {
      defaults.set(data, forKey: key)
    }
  }
}

/// Recent output levels for the Live Input panel (kept separate so meter
/// updates only redraw that panel).
@MainActor
final class LiveLevels: ObservableObject {
  static let historyLength = 160
  @Published private(set) var rms: (Float, Float) = (0, 0)
  @Published private(set) var history: [Float] = []
  @Published private(set) var signalDetected = false
  private var lastSignal = Date.distantPast

  func push (_ reading: LevelMeter.Reading) {
    rms = reading.rms
    let peak = max(reading.peak.0, reading.peak.1)
    if peak > 0.003 { lastSignal = Date() }
    signalDetected = Date().timeIntervalSince(lastSignal) < 0.6
    history.append(min(1, peak))
    if history.count > Self.historyLength {
      history.removeFirst(history.count - Self.historyLength)
    }
  }
}
