import SwiftUI

struct OperationsRootView: View {
    let configuration: OperationsConfiguration

    var body: some View {
        VStack(spacing: 20) {
            Image("LogoDLC")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 120)
                .accessibilityLabel("DLC")

            Text("DLC Operations")
                .font(.largeTitle.bold())
                .foregroundStyle(OperationsTheme.ink)

            if !configuration.isConfigured {
                Label("API configuration required", systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(OperationsTheme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OperationsTheme.background.ignoresSafeArea())
    }
}
