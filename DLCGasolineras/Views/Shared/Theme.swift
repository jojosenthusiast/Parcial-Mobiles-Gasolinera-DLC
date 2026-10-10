import SwiftUI
import UIKit

extension Color {
    /// Adaptive colour resolved by the current interface style (light/dark).
    /// The light value is returned for every non-dark style, so existing light
    /// appearance is preserved exactly.
    init(light: Color, dark: Color) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

/// User-selectable appearance, persisted with `@AppStorage("dlc.appearance")`.
enum DLCAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "dlc.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Sistema"
        case .light: "Claro"
        case .dark: "Oscuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return ColorScheme.light
        case .dark: return ColorScheme.dark
        }
    }
}

enum DLCTheme {
    // Surfaces
    static let background = Color(
        light: Color(red: 0.96, green: 0.94, blue: 0.90),
        dark: Color(red: 0.086, green: 0.086, blue: 0.078)
    )
    static let surface = Color(
        light: Color(red: 1.00, green: 0.99, blue: 0.97),
        dark: Color(red: 0.133, green: 0.129, blue: 0.118)
    )
    /// Slightly raised surface used for translucent overlays (white in light mode).
    static let raised = Color(
        light: Color(red: 1.0, green: 1.0, blue: 1.0),
        dark: Color(red: 0.173, green: 0.165, blue: 0.149)
    )
    static let border = Color(
        light: Color(red: 0.88, green: 0.84, blue: 0.77),
        dark: Color(red: 0.263, green: 0.251, blue: 0.224)
    )

    // Text / ink. `ink` is the dark green used for text on light surfaces
    // (and a warm off-white in dark mode). `forest` is the dark FILL colour for
    // cards that carry white text, so it stays dark in both modes.
    static let ink = Color(
        light: Color(red: 0.13, green: 0.21, blue: 0.18),
        dark: Color(red: 0.93, green: 0.91, blue: 0.86)
    )
    static let forest = Color(
        light: Color(red: 0.13, green: 0.21, blue: 0.18),
        dark: Color(red: 0.17, green: 0.31, blue: 0.26)
    )
    static let muted = Color(
        light: Color(red: 0.40, green: 0.41, blue: 0.38),
        dark: Color(red: 0.66, green: 0.66, blue: 0.62)
    )

    // Accents (usable as text/icon/tint on surfaces)
    static let orange = Color(
        light: Color(red: 0.85, green: 0.30, blue: 0.12),
        dark: Color(red: 0.95, green: 0.43, blue: 0.24)
    )
    static let green = Color(
        light: Color(red: 0.16, green: 0.45, blue: 0.31),
        dark: Color(red: 0.40, green: 0.76, blue: 0.56)
    )
    static let yellow = Color(
        light: Color(red: 0.67, green: 0.45, blue: 0.05),
        dark: Color(red: 0.95, green: 0.74, blue: 0.28)
    )
    static let red = Color(
        light: Color(red: 0.75, green: 0.22, blue: 0.17),
        dark: Color(red: 1.00, green: 0.45, blue: 0.40)
    )
    static let blue = Color(
        light: Color(red: 0.25, green: 0.39, blue: 0.45),
        dark: Color(red: 0.50, green: 0.70, blue: 0.78)
    )

    // Accents used as FILL behind white text (buttons, badges): contrast with white >= 4.5 in dark.
    static let orangeFill = Color(
        light: Color(red: 0.85, green: 0.30, blue: 0.12),
        dark: Color(red: 0.78, green: 0.28, blue: 0.12)
    )
    static let greenFill = Color(red: 0.16, green: 0.45, blue: 0.31)
    static let redFill = Color(red: 0.75, green: 0.22, blue: 0.17)
    static let blueFill = Color(red: 0.25, green: 0.39, blue: 0.45)
    static let yellowFill = Color(red: 0.67, green: 0.45, blue: 0.05)

    // Tints (card/background): dark translucent tints over the dark surface
    static let greenBG = Color(
        light: Color(red: 0.89, green: 0.94, blue: 0.88),
        dark: Color(red: 0.40, green: 0.76, blue: 0.56).opacity(0.13)
    )
    static let yellowBG = Color(
        light: Color(red: 0.99, green: 0.95, blue: 0.82),
        dark: Color(red: 0.95, green: 0.74, blue: 0.28).opacity(0.13)
    )
    static let redBG = Color(
        light: Color(red: 0.99, green: 0.91, blue: 0.87),
        dark: Color(red: 1.00, green: 0.45, blue: 0.40).opacity(0.13)
    )
    static let orangeBG = Color(
        light: Color(red: 0.99, green: 0.91, blue: 0.84),
        dark: Color(red: 0.95, green: 0.43, blue: 0.24).opacity(0.13)
    )
    static let blueBG = Color(
        light: Color(red: 0.89, green: 0.93, blue: 0.95),
        dark: Color(red: 0.50, green: 0.70, blue: 0.78).opacity(0.13)
    )

    static let diesel = Color(
        light: Color(red: 0.83, green: 0.56, blue: 0.06),
        dark: Color(red: 0.96, green: 0.70, blue: 0.22)
    )

    static func fuelColor(_ fuel: FuelType) -> Color {
        switch fuel {
        case .regular: red
        case .superFuel: muted
        case .diesel: diesel
        }
    }
}

extension View {
    func dlcScreen() -> some View {
        self
            .background(DLCTheme.background.ignoresSafeArea())
            .tint(DLCTheme.orange)
    }
}

struct CardSurface: ViewModifier {
    var color: Color = DLCTheme.surface
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(DLCTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

extension View {
    func dlcCard(color: Color = DLCTheme.surface) -> some View {
        modifier(CardSurface(color: color))
    }
}

/// Small appearance picker (System / Light / Dark) bound to `@AppStorage("dlc.appearance")`.
struct AppearancePicker: View {
    @AppStorage(DLCAppearance.storageKey) private var appearanceRaw = DLCAppearance.system.rawValue

    var body: some View {
        Menu {
            Picker("Apariencia", selection: $appearanceRaw) {
                ForEach(DLCAppearance.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
        } label: {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(DLCTheme.ink)
                .frame(width: 40, height: 40)
                .background(DLCTheme.surface, in: Circle())
                .overlay(Circle().stroke(DLCTheme.border, lineWidth: 1))
        }
        .accessibilityLabel("Apariencia")
    }

    private var icon: String {
        switch DLCAppearance(rawValue: appearanceRaw) ?? .system {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}
