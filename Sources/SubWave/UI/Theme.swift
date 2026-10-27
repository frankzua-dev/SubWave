import SwiftUI

/// SubWave's surfaces (dark or light) plus one user-chosen neon accent.
struct Theme {
  static let defaultAccentHex = "#B026FF"

  static let neonSwatches: [(name: String, hex: String)] = [
    ("Neon Purple", "#B026FF"), ("Mint", "#3DDC97"), ("Lime", "#A3FF2E"), ("Cyan", "#22E4FF"),
    ("Electric Blue", "#3D7BFF"), ("Magenta", "#FF2FD0"), ("Hot Pink", "#FF3D8B"), ("Red", "#FF3B47"),
    ("Orange", "#FF8A1F"), ("Yellow", "#FFE62E")
  ]

  let isLight: Bool
  let accent: Color
  /// Accent blended into the card color, for selected backgrounds
  let accentDark: Color
  let accentLight: Color

  // Surfaces and text
  let window: Color
  let header: Color
  let card: Color
  let cardBorder: Color
  let field: Color
  let fieldBorder: Color
  let control: Color
  let textPrimary: Color
  let textSecondary: Color
  let title: Color
  let icon: Color
  let track: Color
  // Control details
  let tick: Color
  let outline: Color
  let switchOff: Color
  let switchKnobOff: Color
  let circleButton: Color
  let meterOff: Color
  let capTop: Color
  let capBottom: Color
  let bezel: Color
  let grille: Color
  let errorText: Color
  let errorBackground: Color

  init (accentHex: String, light: Bool = false) {
    let rgb = RGB(hex: accentHex)
    isLight = light
    accent = rgb.color
    accentLight = rgb.mixed(with: RGB(r: 1, g: 1, b: 1), amount: 0.25).color
    func c (_ dark: String, _ lightHex: String) -> Color { Color(hex: light ? lightHex : dark) }
    accentDark = light
      ? rgb.mixed(with: RGB(r: 1, g: 1, b: 1), amount: 0.78).color
      : rgb.mixed(with: RGB(hex: "#24272B"), amount: 0.62).color

    window = c("#1C1E21", "#ECEEF1")
    header = c("#202226", "#E2E5E9")
    card = c("#24272B", "#FFFFFF")
    cardBorder = c("#30343A", "#D7DBE0")
    field = c("#17191C", "#F2F3F5")
    fieldBorder = c("#2D3137", "#D3D7DC")
    control = c("#2A2D32", "#F4F5F7")
    textPrimary = c("#E8EAED", "#1C1E21")
    textSecondary = c("#A3A9B0", "#5E646B")
    title = c("#C9CDD2", "#2A2D31")
    icon = c("#D5D9DE", "#3A3F45")
    track = c("#131518", "#D6D9DE")
    tick = c("#5B6169", "#A3A9B0")
    outline = c("#565B62", "#B8BDC3")
    switchOff = c("#3A3E44", "#CDD1D6")
    switchKnobOff = c("#4A4F56", "#FFFFFF")
    circleButton = c("#26292D", "#FFFFFF")
    meterOff = c("#33373D", "#D9DCE0")
    capTop = c("#3B3F45", "#FFFFFF")
    capBottom = c("#212428", "#D9DCE1")
    bezel = c("#121417", "#B9BEC5")
    grille = c("#0F1113", "#C4C8CD")
    errorText = c("#FFB4B4", "#9B1C26")
    errorBackground = c("#3A1E22", "#FBE3E5")
  }

  /// A fully saturated, bright color for a hue in 0...360: every hue is neon
  static func neonHex (hue: Double) -> String {
    RGB(hue: hue, saturation: 1, lightness: 0.56).hex
  }

  static func hue (ofHex hex: String) -> Double {
    RGB(hex: hex).hue
  }
}

private struct ThemeKey: EnvironmentKey {
  static let defaultValue = Theme(accentHex: Theme.defaultAccentHex)
}

extension EnvironmentValues {
  var theme: Theme {
    get { self[ThemeKey.self] }
    set { self[ThemeKey.self] = newValue }
  }
}

extension Color {
  init (hex: String) {
    self = RGB(hex: hex).color
  }
}

/// Small sRGB helper for parsing, mixing and hue math.
struct RGB {
  var r: Double, g: Double, b: Double

  init (r: Double, g: Double, b: Double) {
    self.r = r; self.g = g; self.b = b
  }

  init (hex: String) {
    var value = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
    if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
    let number = UInt32(value, radix: 16) ?? 0x3DDC97
    r = Double((number >> 16) & 0xFF) / 255
    g = Double((number >> 8) & 0xFF) / 255
    b = Double(number & 0xFF) / 255
  }

  init (hue: Double, saturation s: Double, lightness l: Double) {
    let c = (1 - abs(2 * l - 1)) * s
    let h = hue.truncatingRemainder(dividingBy: 360) / 60
    let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
    let m = l - c / 2
    let (r1, g1, b1): (Double, Double, Double) = switch h {
    case ..<1: (c, x, 0)
    case ..<2: (x, c, 0)
    case ..<3: (0, c, x)
    case ..<4: (0, x, c)
    case ..<5: (x, 0, c)
    default: (c, 0, x)
    }
    r = r1 + m; g = g1 + m; b = b1 + m
  }

  var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

  var hex: String {
    String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
  }

  var hue: Double {
    let maxC = max(r, g, b), minC = min(r, g, b), d = maxC - minC
    guard d > 0 else { return 0 }
    var h: Double
    if maxC == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
    else if maxC == g { h = (b - r) / d + 2 }
    else { h = (r - g) / d + 4 }
    h *= 60
    return h < 0 ? h + 360 : h
  }

  func mixed (with other: RGB, amount: Double) -> RGB {
    RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
  }
}
