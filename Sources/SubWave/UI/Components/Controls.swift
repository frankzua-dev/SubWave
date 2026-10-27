import SwiftUI

// MARK: Card

struct CardModifier: ViewModifier {
  @Environment(\.theme) private var theme
  func body (content: Content) -> some View {
    content
      .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.cardBorder))
      .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
  }
}

extension View {
  func card () -> some View { modifier(CardModifier()) }
}

struct CardTitle: View {
  @Environment(\.theme) private var theme
  let text: String
  var body: some View {
    Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.textPrimary)
  }
}

struct Divider1: View {
  @Environment(\.theme) private var theme
  var body: some View {
    Rectangle().fill(theme.cardBorder).frame(height: 1)
  }
}

// MARK: Value pill

struct ValuePill: View {
  @Environment(\.theme) private var theme
  let text: String
  var dimmed = false
  var minWidth: CGFloat = 46

  var body: some View {
    Text(text)
      .font(.system(size: 13, weight: .medium).monospacedDigit())
      .foregroundStyle(theme.accent)
      .padding(.horizontal, 9)
      .frame(minWidth: minWidth, minHeight: 24)
      .background(theme.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.fieldBorder))
      .opacity(dimmed ? 0.5 : 1)
  }
}

// MARK: Neon switch

struct NeonSwitch: View {
  @Environment(\.theme) private var theme
  @Binding var isOn: Bool
  var large = false

  var body: some View {
    let width: CGFloat = large ? 50 : 36
    let height: CGFloat = large ? 28 : 20
    let knob = height - 4
    ZStack(alignment: isOn ? .trailing : .leading) {
      Capsule().fill(isOn ? theme.accent : theme.switchOff)
      Circle()
        .fill(isOn ? Color.white : theme.switchKnobOff)
        .frame(width: knob, height: knob)
        .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
        .padding(2)
    }
    .frame(width: width, height: height)
    .contentShape(Capsule())
    .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { isOn.toggle() } }
    .accessibilityAddTraits(.isButton)
    .accessibilityValue(isOn ? "On" : "Off")
  }
}

// MARK: Checkbox

struct NeonCheckbox: View {
  @Environment(\.theme) private var theme
  @Binding var isOn: Bool

  var body: some View {
    RoundedRectangle(cornerRadius: 5, style: .continuous)
      .fill(theme.field)
      .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(theme.fieldBorder))
      .overlay {
        if isOn {
          Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(theme.accent)
        }
      }
      .frame(width: 20, height: 20)
      .contentShape(Rectangle())
      .onTapGesture { isOn.toggle() }
  }
}

// MARK: Square icon button

struct IconButton: View {
  let systemName: String
  var color: Color?
  var help: String = ""
  var size: CGFloat = 36
  let action: () -> Void
  @State private var hovering = false
  @Environment(\.theme) private var theme

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(color ?? theme.icon)
        .frame(width: size, height: size)
        .background(theme.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(hovering ? theme.accent.opacity(0.55) : theme.cardBorder))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .help(help)
  }
}

/// Round outlined button used in the header.
struct CircleIconButton: View {
  let systemName: String
  var help: String = ""
  let action: () -> Void
  @State private var hovering = false
  @Environment(\.theme) private var theme

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(theme.icon)
        .frame(width: 28, height: 28)
        .background(theme.circleButton, in: Circle())
        .overlay(Circle().strokeBorder(hovering ? theme.accent : theme.outline, lineWidth: 1.5))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .help(help)
  }
}

// MARK: Segmented control

struct NeonSegmented<Value: Hashable>: View {
  @Environment(\.theme) private var theme
  let options: [(label: String, value: Value)]
  @Binding var selection: Value

  var body: some View {
    HStack(spacing: 0) {
      ForEach(options, id: \.value) { option in
        let selected = option.value == selection
        Text(option.label)
          .font(.system(size: 14))
          .foregroundStyle(theme.textPrimary)
          .frame(minWidth: 72)
          .padding(.horizontal, 12)
          .padding(.vertical, 5)
          .background {
            if selected {
              RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.accentDark)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.accent.opacity(0.45)))
            }
          }
          .contentShape(Rectangle())
          .onTapGesture { selection = option.value }
      }
    }
    .padding(2)
    .background(theme.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.fieldBorder))
  }
}

// MARK: Dropdown field

/// Dark field with a chevron that opens a menu.
struct DropdownField<MenuItems: View>: View {
  @Environment(\.theme) private var theme
  let title: String
  var icon: String?
  @ViewBuilder let items: () -> MenuItems

  var body: some View {
    Menu(content: items) {
      HStack(spacing: 10) {
        if let icon {
          Image(systemName: icon).font(.system(size: 14)).foregroundStyle(theme.icon)
        }
        Text(title).font(.system(size: 14)).foregroundStyle(theme.textPrimary).lineLimit(1)
        Spacer(minLength: 8)
        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.icon)
      }
      .padding(.horizontal, 12)
      .frame(height: 36)
      .background(theme.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.fieldBorder))
      .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
  }
}

// MARK: Chip

struct FavoriteChip: View {
  @Environment(\.theme) private var theme
  let name: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: "star.fill").font(.system(size: 9))
          .foregroundStyle(selected ? theme.accent : theme.textSecondary)
        Text(name).font(.system(size: 12)).foregroundStyle(selected ? theme.accent : theme.textPrimary)
      }
      .padding(.horizontal, 10)
      .frame(height: 24)
      .background(selected ? theme.accent.opacity(0.14) : theme.field, in: Capsule())
      .overlay(Capsule().strokeBorder(selected ? theme.accent.opacity(0.6) : theme.fieldBorder))
    }
    .buttonStyle(.plain)
  }
}
