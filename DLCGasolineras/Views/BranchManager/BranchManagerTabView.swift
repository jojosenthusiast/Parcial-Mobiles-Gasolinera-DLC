import SwiftUI

struct BranchManagerTabView: View {
    let branch: Branch
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: BranchManagerViewModel
    init(branch: Branch) { self.branch = branch; _vm = StateObject(wrappedValue: BranchManagerViewModel(branch: branch)) }
    var body: some View {
        TabView {
            NavigationStack { BranchDashboardView(vm: vm) }.tabItem { Label("Inicio", systemImage: "house") }
            NavigationStack { CutsView(vm: vm) }.tabItem { Label("Cortes", systemImage: "location.circle") }
            if let actor = appState.currentUser {
                NavigationStack { OperationsRootView(actor: actor, branchID: branch.id, section: .store) }
                    .tabItem { Label("Tienda", systemImage: "cart") }
                NavigationStack { OperationsRootView(actor: actor, branchID: branch.id, section: .team) }
                    .tabItem { Label("Equipo", systemImage: "person.2") }
            }
            NavigationStack { AccountView() }.tabItem { Label("Cuenta", systemImage: "person.crop.circle") }
        }.tint(DLCTheme.orange).dlcScreen()
    }
}
