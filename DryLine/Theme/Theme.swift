import SwiftUI
import UIKit

// MARK: - Appearance

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }
}

// MARK: - Palette ("Bento" — design direction D)
//
// Every colour is a dynamic UIColor, so it resolves against the active
// appearance automatically.
//
// The original names (gold, goldBright, onGold, steel, panel…) are kept so
// existing screens and BrandMark compile unchanged — they now map to the
// Bento palette. Prefer the new names (accent, ink, tile) in new code.

enum Theme {
    // Surfaces
    static let bg          = Color.dynamic(light: 0xFFFFFF, dark: 0x0B0B0C)
    static let panel       = Color.dynamic(light: 0xEEF0F2, dark: 0x1C1D20)   // grey tile
    static let panelRaised = Color.dynamic(light: 0xE3E6E9, dark: 0x26282C)
    static let border      = Color.dynamic(light: 0xDADDE1, dark: 0x2E3034)

    // Accent (orange). Kept under the old "gold" names for compatibility.
    static let gold        = Color.dynamic(light: 0xC2410C, dark: 0xF07030)
    /// Kept for old call sites — same as `gold` so there is one accent only.
    static var goldBright: Color { gold }
    /// Foreground on an accent-filled surface (white in light, near-black in dark).
    static let onGold      = Color.dynamic(light: 0xFFFFFF, dark: 0x0B0B0C)

    // Ink: the black tile / main CTA. Inverts to near-white in dark mode.
    static let ink         = Color.dynamic(light: 0x111111, dark: 0xF2F2F2)
    static let onInk       = Color.dynamic(light: 0xFFFFFF, dark: 0x111111)
    static let onInkDim    = Color.dynamic(light: 0xC9CDD2, dark: 0x4A4E54)

    // Text
    static let text        = Color.dynamic(light: 0x111111, dark: 0xF5F5F5)
    static let textDim     = Color.dynamic(light: 0x52575E, dark: 0xA1A5AB)
    /// Kept for old call sites — same as `textDim` so there are two text colours only.
    static var steel: Color { textDim }

    // New-name aliases
    static var accent: Color   { gold }
    static var onAccent: Color { onGold }
    static var tile: Color     { panel }

    /// Bento is flat; shadows are kept very subtle.
    static var shadow: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.black.withAlphaComponent(0.3)
                : UIColor.black.withAlphaComponent(0.04)
        })
    }
}

extension Color {
    /// Builds a colour that resolves differently in light and dark appearance.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    init(hex: UInt32) {
        self.init(UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >>  8) & 0xFF) / 255.0,
            blue:  CGFloat( hex        & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

// MARK: - Type scale
// Six styles only. Every piece of text in the app uses one of these.
// Space Grotesk if bundled (see README), otherwise SF Pro.
//
//   title     28 bold      screen titles
//   number    40 bold      every quantity / big figure
//   headline  17 semibold  card headings, room dimensions
//   button    16 semibold  every button label
//   body      15 regular   subtitles, sentences
//   caption   13 medium    tile labels, units, card titles

enum DLFont {
    static func grotesk(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "SpaceGrotesk-Bold"
        case .semibold:             name = "SpaceGrotesk-SemiBold"
        case .medium:               name = "SpaceGrotesk-Medium"
        default:                    name = "SpaceGrotesk-Regular"
        }
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight)
    }

    static let title    = grotesk(28, .bold)
    static let number   = grotesk(40, .bold)
    static let headline = grotesk(17, .semibold)
    static let button   = grotesk(16, .semibold)
    static let body     = grotesk(15, .regular)
    static let caption  = grotesk(13, .medium)
}

enum DLMetric {
    static let screenPadding: CGFloat = 16
    static let gap: CGFloat = 8
    static let tileRadius: CGFloat = 22
    static let tilePadding: CGFloat = 16
    /// Every button in the app is this tall (icon buttons are this wide too).
    static let buttonHeight: CGFloat = 52
    static let iconSize: CGFloat = 17
}

// MARK: - Buttons
// One shape (capsule), one height, one font. Two colour roles only:
//   primary   — ink fill, onInk text   (one per screen: the main action)
//   secondary — grey fill, text colour (everything else)

enum DLButtonRole {
    case primary, secondary

    var fill: Color { self == .primary ? Theme.ink : Theme.panel }
    var label: Color { self == .primary ? Theme.onInk : Theme.text }
}

struct DLButtonStyle: ButtonStyle {
    var role: DLButtonRole = .secondary
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DLFont.button)
            .foregroundStyle(role.label)
            .padding(.horizontal, 20)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: DLMetric.buttonHeight)
            .background(role.fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Old names, kept so existing screens compile — they now use the shared style.
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DLButtonStyle(role: .primary).makeBody(configuration: configuration)
    }
}
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DLButtonStyle(role: .secondary).makeBody(configuration: configuration)
    }
}

/// Text button, optional leading icon. Full width by default.
struct DLButton: View {
    let title: String
    var systemImage: String? = nil
    var role: DLButtonRole = .secondary
    var fullWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: DLMetric.iconSize, weight: .semibold))
                }
                Text(title)
            }
        }
        .buttonStyle(DLButtonStyle(role: role, fullWidth: fullWidth))
    }
}

/// Icon-only button: same height and colours as a secondary button, but round.
struct DLIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: DLMetric.iconSize, weight: .semibold))
                .foregroundStyle(DLButtonRole.secondary.label)
                .frame(width: DLMetric.buttonHeight, height: DLMetric.buttonHeight)
                .background(DLButtonRole.secondary.fill, in: Circle())
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Cards

/// Card container used for each section of the app — a flat Bento tile.
struct PanelCard<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(DLFont.caption)
                    .foregroundStyle(Theme.textDim)
            }
            content
                .font(DLFont.body)
                .foregroundStyle(Theme.text)
        }
        .padding(DLMetric.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: DLMetric.tileRadius, style: .continuous))
    }
}

// MARK: - Inputs

/// Labelled text field: same 52pt height as buttons, white field on a grey card.
struct DLTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DLFont.caption)
                .foregroundStyle(Theme.textDim)
            TextField(placeholder, text: $text)
                .font(DLFont.body)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .frame(height: DLMetric.buttonHeight)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
