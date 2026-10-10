import SwiftUI

struct GeneralManagerTabView: View {
    @StateObject private var vm = GeneralManagerViewModel()
    @EnvironmentObject private var appState: AppState
    var body: some View {
        Group {
            if let actor = appState.currentUser {
                TabView {
                    NavigationStack { GeneralDashboardView(vm: vm) }
                        .tabItem { Label("Inicio", systemImage: "house") }
                    NavigationStack { BranchesView(vm: vm) }
                        .tabItem { Label("Sucursales", systemImage: "location.circle") }
                    NavigationStack { OperationsRootView(actor: actor, branchID: nil, section: .management) }
                        .tabItem { Label("Gestión", systemImage: "square.grid.2x2") }
                    NavigationStack { ManagersView(vm: vm) }
                        .tabItem { Label("Usuarios", systemImage: "person.2") }
                    NavigationStack { AccountView() }
                        .tabItem { Label("Cuenta", systemImage: "person.crop.circle") }
                }
            } else { LoginView() }
        }
        .tint(DLCTheme.orange).dlcScreen()
    }
}
