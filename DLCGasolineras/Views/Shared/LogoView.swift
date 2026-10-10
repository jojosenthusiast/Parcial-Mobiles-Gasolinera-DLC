import SwiftUI

struct LogoView: View {
    var loginStyle = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        Image(loginStyle ? "LogoLogin" : "LogoDLC")
            .resizable()
            .scaledToFit()
            .frame(width: loginStyle ? 245 : 170, height: loginStyle ? 245 : 90)
            .padding(isDark ? 8 : 0)
            // The logo artwork is dark-on-transparent; give it a light backing in dark mode.
            .background(
                isDark ? Color(red: 0.96, green: 0.94, blue: 0.90) : Color.clear,
                in: RoundedRectangle(cornerRadius: 18)
            )
            .accessibilityLabel("DLC")
    }
}
