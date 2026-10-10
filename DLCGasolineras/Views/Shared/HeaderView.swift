import SwiftUI

struct HeaderView: View {
    let role: String
    var location: String? = nil
    var body: some View {
        HStack(alignment: .top) {
            LogoView()
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                AppearancePicker()
                Text(role).foregroundStyle(DLCTheme.muted)
                if let location { Text(location).bold().foregroundStyle(DLCTheme.muted) }
            }.font(.subheadline)
        }
    }
}

struct AccountView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingExportConfirmation = false
    @State private var exportFileURL: URL?
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderView(role: "Acceso protegido")
                Text("Mi perfil").font(.largeTitle.weight(.bold))

                if let user = appState.currentUser {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(user.name, systemImage: "person.crop.circle.fill")
                            .font(.title3.weight(.semibold))
                        Label(user.role == .generalManager ? "Gerente General" : "Gerente de Sucursal", systemImage: "person.badge.key.fill")
                            .foregroundStyle(DLCTheme.muted)
                        Label("Usuario: \(user.username)", systemImage: "at")
                            .foregroundStyle(DLCTheme.muted)
                        if let branch = appState.selectedBranch {
                            Label("Sucursal: \(branch.name)", systemImage: "building.2.fill")
                                .foregroundStyle(DLCTheme.muted)
                        } else if user.role == .generalManager {
                            Label("Alcance: toda la red", systemImage: "globe.americas.fill")
                                .foregroundStyle(DLCTheme.muted)
                        }
                    }
                    .dlcCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Respaldo y migración", systemImage: "externaldrive.fill")
                            .font(.headline)
                        Text("Genera una copia JSON de los datos operativos locales para migrarlos. Incluye información de sucursales, usuarios, personal, ventas e inventarios; no incluye contraseñas ni credenciales.")
                            .font(.caption)
                            .foregroundStyle(DLCTheme.muted)
                        Button {
                            showingExportConfirmation = true
                        } label: {
                            Label("Preparar respaldo", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        if let exportFileURL {
                            ShareLink(item: exportFileURL, preview: SharePreview("Respaldo DLC", image: Image(systemName: "doc.text"))) {
                                Label("Compartir archivo JSON", systemImage: "square.and.arrow.up.on.square")
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.vertical, 13)
                            .foregroundStyle(DLCTheme.ink)
                            .background(DLCTheme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                        }
                        if let exportError {
                            Text(exportError).font(.caption).foregroundStyle(DLCTheme.red)
                        }
                    }
                    .dlcCard()

                    Button(role: .destructive) { appState.logout() } label: {
                        Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(22)
        }
        .dlcScreen()
        .navigationBarHidden(true)
        .confirmationDialog(
            "¿Preparar una copia de los datos locales?",
            isPresented: $showingExportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Crear archivo JSON") {
                do {
                    exportFileURL = try appState.repository.makeLegacyExportFile()
                    exportError = nil
                } catch {
                    exportFileURL = nil
                    exportError = "No se pudo preparar el respaldo: \(error.localizedDescription)"
                }
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("El archivo contiene datos operativos y personales. Compártelo solo con una persona autorizada y guárdalo en un lugar protegido.")
        }
    }
}
