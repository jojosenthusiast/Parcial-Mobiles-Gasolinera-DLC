import SwiftUI

struct LogoView: View {
    var loginStyle = false
    var body: some View {
        Image(loginStyle ? "LogoLogin" : "LogoDLC")
            .resizable()
            .scaledToFit()
            .frame(width: loginStyle ? 245 : 170, height: loginStyle ? 245 : 90)
            .accessibilityLabel("DLC")
    }
}
