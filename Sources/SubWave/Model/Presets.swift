import Foundation

enum EQMode: String, Codable, CaseIterable {
  case basic = "Basic"
  case advanced = "Advanced"
}

struct BasicGains: Codable, Equatable {
  var bass = 0.0
  var mid = 0.0
  var treble = 0.0
}

struct AdvancedGains: Codable, Equatable {
  static let frequencies: [Double] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
  static let labels = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]

  var global = 0.0
  var bands = [Double](repeating: 0, count: AdvancedGains.frequencies.count)
}

/// A saved sound setting for one equalizer mode.
struct Preset: Codable, Identifiable, Equatable {
  var id: String = UUID().uuidString
  var name: String
  var isBuiltIn = false
  var favorite = false
  var basic = BasicGains()
  var advanced = AdvancedGains()
  var peakLimiter = true          // Distortion Guard
}

enum BuiltInPresets {
  static let flatID = "builtin.flat"
  static let funkyID = "builtin.basic.funky"

  /// SubWave's signature sound and the default on first launch
  static let funky = Preset(id: funkyID, name: "Funky", isBuiltIn: true, basic: BasicGains(bass: 12, mid: -3, treble: 8))

  static let basic: [Preset] = [
    funky,
    Preset(id: flatID, name: "Flat", isBuiltIn: true)
  ]

  static let advanced: [Preset] = [
    Preset(id: flatID, name: "Flat", isBuiltIn: true)
  ]
}
