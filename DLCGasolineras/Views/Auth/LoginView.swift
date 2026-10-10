import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm = AuthViewModel()
    @State private var showPassword = false
    @FocusState private var focusedField: LoginField?

    private enum LoginField: Hashable { case username, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                HStack { Spacer(); AppearancePicker() }.padding(.horizontal, 18).padding(.top, 8)
                Spacer(minLength: 38)
                LogoView(loginStyle: true)
                VStack(alignment: .leading, spacing: 19) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Iniciar sesión")
                            .font(.largeTitle.weight(.bold)).foregroundStyle(DLCTheme.ink)
                        Text("Ingresa con tu cuenta asignada para abrir el panel de tu rol.")
                            .font(.subheadline).foregroundStyle(DLCTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text("ENTORNO DE ACCESO").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(DLCTheme.muted)
                        HStack(spacing: 10) {
                            environmentOption(.remote, title: "Servidor", subtitle: "Cuenta de la organización", symbol: "cloud.fill")
                            environmentOption(.localDemo, title: "Demostración", subtitle: "Datos locales de ejemplo", symbol: "sparkles.rectangle.stack.fill")
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        credentialField(
                            title: appState.runtimeMode == .remote ? "Correo electrónico" : "Usuario",
                            icon: appState.runtimeMode == .remote ? "envelope" : "person.crop.circle",
                            placeholder: appState.runtimeMode == .remote ? "nombre@empresa.com" : "Tu nombre de usuario",
                            text: $vm.username,
                            field: .username,
                            keyboard: appState.runtimeMode == .remote ? .emailAddress : .default,
                            capitalization: .never
                        )
                        passwordField
                    }
                    .padding(16)
                    .background(DLCTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(DLCTheme.border, lineWidth: 1))

                    if appState.runtimeMode == .localDemo, let recoveryMessage = appState.repository.recoveryRequiredMessage {
                        Label(recoveryMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.medium)).foregroundStyle(DLCTheme.red)
                            .fixedSize(horizontal: false, vertical: true).dlcCard(color: DLCTheme.redBG)
                    }
                    if appState.runtimeMode == .remote, !appState.remoteError.isEmpty {
                        Label(appState.remoteError, systemImage: "wifi.exclamationmark")
                            .font(.footnote.weight(.medium)).foregroundStyle(DLCTheme.red)
                            .fixedSize(horizontal: false, vertical: true).dlcCard(color: DLCTheme.redBG)
                    }
                    if !vm.errorMessage.isEmpty {
                        Label(vm.errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.medium)).foregroundStyle(DLCTheme.red)
                            .fixedSize(horizontal: false, vertical: true).dlcCard(color: DLCTheme.redBG)
                    }

                    Button {
                        Task { await vm.login(using: appState) }
                    } label: {
                        HStack(spacing: 9) {
                            if vm.isLoading || appState.isRestoringRemoteSession { ProgressView().tint(.white) }
                            else { Image(systemName: "lock.open.fill") }
                            Text(vm.isLoading ? "Verificando acceso…" : appState.isRestoringRemoteSession ? "Restaurando sesión…" : "Entrar")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(vm.isLoading || appState.isRestoringRemoteSession || vm.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.password.isEmpty || (appState.runtimeMode == .localDemo && appState.repository.recoveryRequiredMessage != nil))

                    if appState.runtimeMode == .localDemo {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Gerente general  ·  admin / admin123")
                                Text("Gerente de sucursal  ·  santa / santa123")
                            }
                            .font(.caption.monospaced())
                            .foregroundStyle(DLCTheme.muted)
                            .padding(.top, 6)
                        } label: {
                            Label("Accesos locales de demostración", systemImage: "info.circle")
                                .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.ink)
                        }
                        .tint(DLCTheme.orange)
                    }
                }
                .padding(20)
                .background(DLCTheme.raised.opacity(0.64), in: RoundedRectangle(cornerRadius: 25))
                .overlay(RoundedRectangle(cornerRadius: 25).stroke(DLCTheme.border.opacity(0.7), lineWidth: 1))
                .shadow(color: DLCTheme.forest.opacity(0.05), radius: 18, y: 8)
                .padding(.horizontal, 18)
                Spacer(minLength: 38)
            }
        }
        .dlcScreen()
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.84), value: appState.runtimeMode)
        .task(id: appState.runtimeMode) {
            if appState.runtimeMode == .remote { await appState.restoreRemoteSession() }
        }
        .onChange(of: appState.runtimeMode) { _, _ in
            vm.username = ""
            vm.password = ""
            vm.errorMessage = ""
            showPassword = false
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contraseña").font(.headline).foregroundStyle(DLCTheme.ink)
            HStack(spacing: 10) {
                Image(systemName: "lock").foregroundStyle(DLCTheme.muted.opacity(0.8))
                Group {
                    if showPassword {
                        TextField("Tu contraseña", text: $vm.password)
                    } else {
                        SecureField("Tu contraseña", text: $vm.password)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { await vm.login(using: appState) } }
                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundStyle(DLCTheme.muted).frame(width: 32, height: 32)
                }
                .accessibilityLabel(showPassword ? "Ocultar contraseña" : "Mostrar contraseña")
            }
            .padding(14)
            .background(DLCTheme.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(DLCTheme.border.opacity(0.7), lineWidth: 1))
        }
    }

    private func credentialField(title: String, icon: String, placeholder: String, text: Binding<String>, field: LoginField, keyboard: UIKeyboardType, capitalization: TextInputAutocapitalization) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(DLCTheme.ink)
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(DLCTheme.muted.opacity(0.8))
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
                    .keyboardType(keyboard)
                    .textContentType(field == .username ? (appState.runtimeMode == .remote ? .emailAddress : .username) : .password)
                    .focused($focusedField, equals: field)
                    .submitLabel(field == .username ? .next : .go)
                    .onSubmit {
                        if field == .username { focusedField = .password }
                        else { Task { await vm.login(using: appState) } }
                    }
            }
            .padding(14)
            .background(DLCTheme.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(DLCTheme.border.opacity(0.7), lineWidth: 1))
        }
    }

    private func environmentOption(_ mode: AppState.RuntimeMode, title: String, subtitle: String, symbol: String) -> some View {
        let selected = appState.runtimeMode == mode
        return Button {
            appState.setRuntimeMode(mode)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.headline)
                Text(title).font(.subheadline.weight(.bold))
                Text(subtitle).font(.caption2).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(selected ? .white : DLCTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .padding(12)
            .background(selected ? DLCTheme.forest : DLCTheme.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? DLCTheme.forest : DLCTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
