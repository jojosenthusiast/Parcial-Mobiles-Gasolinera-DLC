import SwiftUI

enum DLCTheme {
    static let background = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let surface = Color(red: 1.00, green: 0.99, blue: 0.97)
    static let orange = Color(red: 0.85, green: 0.30, blue: 0.12)
    static let forest = Color(red: 0.13, green: 0.21, blue: 0.18)
    static let muted = Color(red: 0.40, green: 0.41, blue: 0.38)
    static let border = Color(red: 0.88, green: 0.84, blue: 0.77)

    static let green = Color(red: 0.16, green: 0.45, blue: 0.31)
    static let yellow = Color(red: 0.67, green: 0.45, blue: 0.05)
    static let red = Color(red: 0.75, green: 0.22, blue: 0.17)
    static let blue = Color(red: 0.25, green: 0.39, blue: 0.45)

    static let greenBG = Color(red: 0.89, green: 0.94, blue: 0.88)
    static let yellowBG = Color(red: 0.99, green: 0.95, blue: 0.82)
    static let redBG = Color(red: 0.99, green: 0.91, blue: 0.87)
    static let orangeBG = Color(red: 0.99, green: 0.91, blue: 0.84)

    static func fuelColor(_ fuel: FuelType) -> Color {
        switch fuel {
        case .regular: red
        case .superFuel: muted
        case .diesel: Color(red: 0.83, green: 0.56, blue: 0.06)
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
