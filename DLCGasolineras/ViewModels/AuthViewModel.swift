import Combine
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var username = ""
    @Published var password = ""
    @Published var errorMessage = ""
    @Published private(set) var isLoading = false

    func login(using appState: AppState) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }
        if appState.runtimeMode == .localDemo {
            let success = appState.login(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            errorMessage = success ? "" : "Usuario o contraseña incorrectos"
            return
        }
        do { try await appState.loginRemote(email: username, password: password) }
        catch { errorMessage = error.localizedDescription }
    }
}
