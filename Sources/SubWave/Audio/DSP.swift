import Foundation

/// Second-order IIR filter coefficients, normalized so a0 == 1.
/// Formulas follow the widely published "Audio EQ Cookbook" (R. Bristow-Johnson).
struct FilterCoefficients {
  var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0

  static let passthrough = FilterCoefficients()

  static func peaking (frequency: Double, gainDB: Double, q: Double, sampleRate: Double) -> FilterCoefficients {
    let a = pow(10, gainDB / 40)
    let w0 = 2 * Double.pi * frequency / sampleRate
    let alpha = sin(w0) / (2 * q)
    let cosW0 = cos(w0)
    let a0 = 1 + alpha / a
    return FilterCoefficients(
      b0: (1 + alpha * a) / a0,
      b1: (-2 * cosW0) / a0,
      b2: (1 - alpha * a) / a0,
      a1: (-2 * cosW0) / a0,
      a2: (1 - alpha / a) / a0
    )
  }

  static func lowShelf (frequency: Double, gainDB: Double, sampleRate: Double) -> FilterCoefficients {
    shelf(frequency: frequency, gainDB: gainDB, sampleRate: sampleRate, high: false)
  }

  static func highShelf (frequency: Double, gainDB: Double, sampleRate: Double) -> FilterCoefficients {
    shelf(frequency: frequency, gainDB: gainDB, sampleRate: sampleRate, high: true)
  }

  // Shelf with slope S = 1 (no resonant bump)
  private static func shelf (frequency: Double, gainDB: Double, sampleRate: Double, high: Bool) -> FilterCoefficients {
    let a = pow(10, gainDB / 40)
    let w0 = 2 * Double.pi * frequency / sampleRate
    let cosW0 = cos(w0)
    let alpha = sin(w0) / 2 * sqrt(2)
    let twoRootAAlpha = 2 * sqrt(a) * alpha
    let sign: Double = high ? -1 : 1
    let a0 = (a + 1) + sign * (a - 1) * cosW0 + twoRootAAlpha
    return FilterCoefficients(
      b0: a * ((a + 1) - sign * (a - 1) * cosW0 + twoRootAAlpha) / a0,
      b1: sign * 2 * a * ((a - 1) - sign * (a + 1) * cosW0) / a0,
      b2: a * ((a + 1) - sign * (a - 1) * cosW0 - twoRootAAlpha) / a0,
      a1: -sign * 2 * ((a - 1) + sign * (a + 1) * cosW0) / a0,
      a2: ((a + 1) + sign * (a - 1) * cosW0 - twoRootAAlpha) / a0
    )
  }
}

/// Everything the audio thread needs, prepared on the main thread.
struct ProcessingSettings {
  var filters: [FilterCoefficients] = []
  var preGain: Float = 1        // equalizer global gain (linear)
  var outputGain: Float = 1     // boost (linear, >= 1)
  var leftGain: Float = 1       // balance
  var rightGain: Float = 1
  var limiterEnabled = false
}

/// Real-time stereo processor: EQ filters, gains, balance, limiter and level metering.
/// The audio thread never allocates or locks. Settings are published through two
/// preallocated slots and an index flip, so the audio thread always reads a
/// complete set; a single buffer may use the previous settings.
final class AudioProcessor {
  static let maxFilters = 16
  private static let slotSize = 5 * maxFilters

  // Two settings slots: coefficients, filter count, gains
  private let coefficients = UnsafeMutablePointer<Double>.allocate(capacity: 2 * slotSize)
  private let filterCount = UnsafeMutablePointer<Int>.allocate(capacity: 2)
  private let gains = UnsafeMutablePointer<Float>.allocate(capacity: 2 * 5)
  private let activeSlot = UnsafeMutablePointer<Int>.allocate(capacity: 1)

  // Filter state: [filter][channel][z1, z2]
  private let state = UnsafeMutablePointer<Double>.allocate(capacity: maxFilters * 2 * 2)
  private var limiterEnvelope: Float = 0

  let meter = LevelMeter()

  init () {
    coefficients.initialize(repeating: 0, count: 2 * Self.slotSize)
    filterCount.initialize(repeating: 0, count: 2)
    gains.initialize(repeating: 1, count: 2 * 5)
    gains[4] = 0
    gains[9] = 0
    activeSlot.initialize(to: 0)
    state.initialize(repeating: 0, count: Self.maxFilters * 4)
  }

  deinit {
    coefficients.deallocate()
    filterCount.deallocate()
    gains.deallocate()
    activeSlot.deallocate()
    state.deallocate()
  }

  /// Main thread: publish new settings for the audio thread.
  func update (_ settings: ProcessingSettings) {
    let slot = 1 - activeSlot.pointee
    let count = min(settings.filters.count, Self.maxFilters)
    let base = coefficients + slot * Self.slotSize
    for (i, f) in settings.filters.prefix(count).enumerated() {
      base[i * 5 + 0] = f.b0
      base[i * 5 + 1] = f.b1
      base[i * 5 + 2] = f.b2
      base[i * 5 + 3] = f.a1
      base[i * 5 + 4] = f.a2
    }
    filterCount[slot] = count
    let g = gains + slot * 5
    g[0] = settings.preGain
    g[1] = settings.outputGain
    g[2] = settings.leftGain
    g[3] = settings.rightGain
    g[4] = settings.limiterEnabled ? 1 : 0
    activeSlot.pointee = slot
  }

  /// Audio thread: clears filter memory (e.g. after the stream restarts).
  func reset () {
    state.update(repeating: 0, count: Self.maxFilters * 4)
    limiterEnvelope = 0
  }

  /// Audio thread: process one stereo frame.
  @inline(__always)
  func process (left: inout Float, right: inout Float) {
    let slot = activeSlot.pointee
    let base = coefficients + slot * Self.slotSize
    let count = filterCount[slot]
    let g = gains + slot * 5

    var l = Double(left * g[0])
    var r = Double(right * g[0])

    for i in 0..<count {
      let c = base + i * 5
      let s = state + i * 4
      // Transposed direct form II
      let outL = c[0] * l + s[0]
      s[0] = c[1] * l - c[3] * outL + s[1]
      s[1] = c[2] * l - c[4] * outL
      l = outL
      let outR = c[0] * r + s[2]
      s[2] = c[1] * r - c[3] * outR + s[3]
      s[3] = c[2] * r - c[4] * outR
      r = outR
    }

    var outL = Float(l) * g[1] * g[2]
    var outR = Float(r) * g[1] * g[3]

    if g[4] > 0 {
      // Peak limiter: instant attack, ~150 ms release, ceiling at -0.5 dBFS
      let ceiling: Float = 0.944
      let peak = max(abs(outL), abs(outR))
      limiterEnvelope = peak > limiterEnvelope ? peak : limiterEnvelope * 0.99985 + peak * 0.00015
      if limiterEnvelope > ceiling {
        let reduction = ceiling / limiterEnvelope
        outL *= reduction
        outR *= reduction
      }
    }

    // Never send anything past full scale to the speakers
    left = min(1, max(-1, outL))
    right = min(1, max(-1, outR))
  }
}

/// Peak and RMS levels for the Live Input display. The audio thread accumulates;
/// the main thread reads and resets about 30 times a second.
final class LevelMeter {
  // [peakL, peakR, sumSquaresL, sumSquaresR, frames]
  private let values = UnsafeMutablePointer<Float>.allocate(capacity: 5)

  init () {
    values.initialize(repeating: 0, count: 5)
  }

  deinit {
    values.deallocate()
  }

  @inline(__always)
  func add (left: Float, right: Float) {
    let l = abs(left), r = abs(right)
    if l > values[0] { values[0] = l }
    if r > values[1] { values[1] = r }
    values[2] += left * left
    values[3] += right * right
    values[4] += 1
  }

  struct Reading {
    var peak: (Float, Float)
    var rms: (Float, Float)
  }

  func read () -> Reading {
    let frames = values[4]
    let reading = Reading(
      peak: (values[0], values[1]),
      rms: frames > 0 ? (sqrt(values[2] / frames), sqrt(values[3] / frames)) : (0, 0)
    )
    values.update(repeating: 0, count: 5)
    return reading
  }
}
