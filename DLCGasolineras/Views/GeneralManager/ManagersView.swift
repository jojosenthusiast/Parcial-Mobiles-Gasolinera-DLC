import SwiftUI

struct ManagersView: View {
    @ObservedObject var vm: GeneralManagerViewModel
    @State private var searchText = ""

    private var filteredManagers: [AppUser] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return vm.managers }
        return vm.managers.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.username.localizedCaseInsensitiveContains(query)
                || $0.email.localizedCaseInsensitiveContains(query)
        }
    }

    private var assignedCount: Int { vm.managers.filter { $0.branchID != nil }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HeaderView(role: "Gerente General")
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gerentes locales").font(.largeTitle.weight(.bold))
                        Text("Cuentas con acceso a una sucursal; el estado inactivo bloquea el inicio de sesión.")
                            .font(.subheadline).foregroundStyle(DLCTheme.muted)
                    }
                    Spacer()
                    NavigationLink(destination: NewManagerView(vm: vm)) {
                        Image(systemName: "person.badge.plus").font(.title2).foregroundStyle(DLCTheme.orange)
                    }
                    .accessibilityLabel("Crear perfil de gerente local")
                }

                HStack {
                    Label("\(vm.managers.count) perfiles", systemImage: "person.2.fill")
                    Spacer()
                    Text("\(assignedCount) asignados · \(vm.managers.count - assignedCount) sin asignar")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(DLCTheme.muted)
                .dlcCard(color: DLCTheme.orangeBG)

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(DLCTheme.muted)
                    TextField("Buscar nombre o usuario", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(13)
                .background(DLCTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DLCTheme.border))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                ForEach(filteredManagers) { manager in
                    ManagerAssignmentCard(manager: manager, branches: vm.activeBranches, vm: vm) { branchID in
                        vm.assignManager(manager.id, to: branchID)
                    }
                }
            }
            .padding(20)
        }
        .dlcScreen()
        .navigationBarHidden(true)
        .onAppear { vm.reload() }
    }
}

private struct ManagerAssignmentCard: View {
    let manager: AppUser
    let branches: [Branch]
    @ObservedObject var vm: GeneralManagerViewModel
    let onAssign: (UUID?) -> String?

    @State private var selectedBranchID: UUID?
    @State private var feedback = ""
    @State private var feedbackIsError = false

    init(manager: AppUser, branches: [Branch], vm: GeneralManagerViewModel, onAssign: @escaping (UUID?) -> String?) {
        self.manager = manager
        self.branches = branches
        self.vm = vm
        self.onAssign = onAssign
        _selectedBranchID = State(initialValue: manager.branchID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2).foregroundStyle(DLCTheme.forest)
                VStack(alignment: .leading, spacing: 3) {
                    Text(manager.name).font(.headline)
                    Text("@\(manager.username)").font(.caption).foregroundStyle(DLCTheme.muted)
                }
                Spacer()
                Text(!manager.isActive ? "Inactivo" : (manager.branchID == nil ? "Sin asignar" : "Activo"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(!manager.isActive ? DLCTheme.red : (manager.branchID == nil ? DLCTheme.yellow : DLCTheme.green))
            }

            if !manager.email.isEmpty {
                Label(manager.email, systemImage: "envelope").font(.caption).foregroundStyle(DLCTheme.muted)
            }

            Picker("Sucursal vinculada", selection: $selectedBranchID) {
                Text("Sin sucursal").tag(UUID?.none)
                ForEach(branches) { branch in Text(branch.name).tag(Optional(branch.id)) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(DLCTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 11))

            Button("Guardar asignación") {
                showFeedback(onAssign(selectedBranchID), success: "Asignación actualizada.")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DLCTheme.orange)
            .frame(maxWidth: .infinity, alignment: .trailing)

            if !feedback.isEmpty {
                Text(feedback).font(.caption).foregroundStyle(feedbackIsError ? DLCTheme.red : DLCTheme.green)
            }

            HStack {
                NavigationLink(destination: EditManagerView(vm: vm, manager: manager)) {
                    Label("Editar perfil", systemImage: "pencil").font(.caption.weight(.semibold))
                }
                Spacer()
                NavigationLink(destination: ResetManagerPasswordView(vm: vm, manager: manager)) {
                    Label("Contraseña", systemImage: "key.fill").font(.caption.weight(.semibold))
                }
                Spacer()
                Button(manager.isActive ? "Desactivar" : "Activar") {
                    showFeedback(
                        vm.setManagerActive(manager.id, active: !manager.isActive),
                        success: manager.isActive ? "Cuenta desactivada." : "Cuenta activada."
                    )
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(manager.isActive ? DLCTheme.red : DLCTheme.green)
            }
        }
        .dlcCard()
    }

    private func showFeedback(_ error: String?, success: String) {
        feedbackIsError = error != nil
        feedback = error ?? success
    }
}

struct NewManagerView: View {
    @ObservedObject var vm: GeneralManagerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var username = ""
    @State private var password = ""
    @State private var branchID: UUID?
    @State private var errorMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HeaderView(role: "Administración", location: "Perfil local")
                Text("Crear gerente").font(.largeTitle.weight(.bold))
                Text("El acceso se asigna a una sucursal y no permite consultar el resto de la red.")
                    .font(.subheadline).foregroundStyle(DLCTheme.muted)

                field("Nombre completo", placeholder: "Nombre y apellido", text: $name)
                field("Usuario", placeholder: "ana.lopez", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                VStack(alignment: .leading, spacing: 7) {
                    Text("Contraseña temporal").font(.subheadline.weight(.semibold))
                    SecureField("8 caracteres con letras y números", text: $password)
                        .textContentType(.newPassword)
                        .padding(14)
                        .background(DLCTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DLCTheme.border))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Sucursal asignada").font(.subheadline.weight(.semibold))
                    Picker("Seleccionar sucursal", selection: $branchID) {
                        Text("Selecciona una sucursal").tag(UUID?.none)
                        ForEach(vm.branches) { branch in Text(branch.name).tag(Optional(branch.id)) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(DLCTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(DLCTheme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Label("El perfil solo opera la estación seleccionada.", systemImage: "lock.shield.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(DLCTheme.forest)
                    .dlcCard(color: DLCTheme.greenBG)

                if !errorMessage.isEmpty {
                    Text(errorMessage).font(.subheadline).foregroundStyle(DLCTheme.red)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DLCTheme.redBG).clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button("Crear y asignar perfil") { save() }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(20)
        }
        .dlcScreen()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.reload() }
    }

    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField(placeholder, text: text)
                .padding(14)
                .background(DLCTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DLCTheme.border))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func save() {
        guard let branchID else {
            errorMessage = "Selecciona la sucursal a la que se vinculará el gerente."
            return
        }
        errorMessage = vm.createManager(name: name, username: username, password: password, branchID: branchID) ?? ""
        if errorMessage.isEmpty { dismiss() }
    }
}

private struct EditManagerView: View {
    @ObservedObject var vm: GeneralManagerViewModel
    let manager: AppUser
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var email: String
    @State private var branchID: UUID?
    @State private var error = ""

    init(vm: GeneralManagerViewModel, manager: AppUser) {
        self.vm = vm; self.manager = manager
        _name = State(initialValue: manager.name)
        _email = State(initialValue: manager.email)
        _branchID = State(initialValue: manager.branchID)
    }

    var body: some View {
        Form {
            Section("Cuenta") {
                LabeledContent("Usuario", value: manager.username)
                TextField("Nombre completo", text: $name)
                TextField("Correo (opcional)", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
            }
            Section("Sucursal asignada") {
                Picker("Sucursal", selection: $branchID) {
                    Text("Sin asignar").tag(UUID?.none)
                    ForEach(vm.activeBranches) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if !error.isEmpty { Section { Text(error).foregroundStyle(DLCTheme.red) } }
            Section { Button("Guardar perfil", action: save).frame(maxWidth: .infinity, alignment: .center) }
        }
        .navigationTitle("Editar gerente")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        error = vm.updateManager(id: manager.id, name: name, email: email, branchID: branchID) ?? ""
        if error.isEmpty { dismiss() }
    }
}

private struct ResetManagerPasswordView: View {
    @ObservedObject var vm: GeneralManagerViewModel
    let manager: AppUser
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var message = ""

    var body: some View {
        Form {
            Section("Cuenta") {
                LabeledContent("Nombre", value: manager.name)
                LabeledContent("Usuario", value: manager.username)
            }
            Section("Nueva contraseña") {
                SecureField("8 caracteres con letras y números", text: $password)
                SecureField("Confirmar contraseña", text: $confirmation)
            }
            if !message.isEmpty { Section { Text(message).foregroundStyle(message == "Contraseña actualizada." ? DLCTheme.green : DLCTheme.red) } }
            Section { Button("Actualizar contraseña", action: save).frame(maxWidth: .infinity, alignment: .center) }
        }
        .navigationTitle("Restablecer acceso")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        message = vm.resetManagerPassword(manager.id, password: password, confirmation: confirmation) ?? "Contraseña actualizada."
        if message == "Contraseña actualizada." { dismiss() }
    }
}
