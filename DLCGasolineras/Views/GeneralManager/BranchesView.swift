import SwiftUI

private enum BranchListFilter: String, CaseIterable, Identifiable {
    case all = "Todas"
    case attention = "Atención"
    case healthy = "Al día"
    case archived = "Archivadas"
    var id: String { rawValue }
}

struct BranchesView: View {
    @ObservedObject var vm: GeneralManagerViewModel
    @State private var filter: BranchListFilter = .all

    private var visibleBranches: [Branch] {
        switch filter {
        case .all: vm.filteredBranches
        case .attention: vm.filteredBranches.filter { $0.isActive && $0.tanks.contains(where: { $0.status == .critical }) }
        case .healthy: vm.filteredBranches.filter { $0.isActive && !$0.tanks.contains(where: { $0.status == .critical }) }
        case .archived: vm.filteredBranches.filter { !$0.isActive }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HeaderView(role: "Gerente General")
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sucursales").font(.largeTitle.weight(.bold))
                        Text("Estado operativo, inventario y cortes.")
                            .font(.subheadline).foregroundStyle(DLCTheme.muted)
                    }
                    Spacer()
                    NavigationLink(destination: NewBranchView(vm: vm)) {
                        Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(DLCTheme.orange)
                    }
                    .accessibilityLabel("Registrar sucursal")
                }

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(DLCTheme.muted)
                    TextField("Buscar nombre, código o ciudad", text: $vm.searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(13)
                .background(DLCTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(DLCTheme.border))
                .clipShape(RoundedRectangle(cornerRadius: 13))

                Picker("Filtrar sucursales", selection: $filter) {
                    ForEach(BranchListFilter.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)

                Text("\(visibleBranches.count) de \(vm.branches.count) sucursales")
                    .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.muted)

                if visibleBranches.isEmpty {
                    ContentUnavailableView("Sin resultados", systemImage: "building.2", description: Text("Cambia el filtro o el texto de búsqueda."))
                        .padding(.top, 24)
                } else {
                    ForEach(visibleBranches) { branch in
                        VStack(spacing: 8) {
                            NavigationLink(destination: BranchDetailView(vm: vm, branchID: branch.id)) {
                                BranchCard(branch: branch, cuts: vm.todayCuts(for: branch.id))
                            }
                            .buttonStyle(.plain)
                            HStack {
                                NavigationLink(destination: EditBranchView(vm: vm, branch: branch)) {
                                    Label("Editar sucursal", systemImage: "pencil")
                                }
                                .font(.caption.weight(.semibold))
                                Spacer()
                                Button(branch.isActive ? "Desactivar" : "Reactivar") {
                                    _ = vm.setBranchActive(branch.id, active: !branch.isActive)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(branch.isActive ? DLCTheme.red : DLCTheme.green)
                            }
                            .padding(.horizontal, 5)
                        }
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

@MainActor
struct RemoteBranchesDirectoryView: View {
    @StateObject private var vm: RemoteBranchesViewModel
    private let repository: RemoteBranchRepository
    private let pumpRepository: RemotePumpRepository?
    private let tankRepository: RemoteTankRepository?
    private let offlineStore: RemoteOfflineStore
    private let scope: RemoteDataScope
    private let canManageBranches: Bool
    private let canActivateBranches: Bool
    private let canReadInventory: Bool
    private let canReadFuel: Bool
    private let canReadInfrastructure: Bool
    private let canReadStaff: Bool
    private let canManageStaff: Bool
    private let canReadPrices: Bool
    private let canProposePrices: Bool
    @State private var showOnboarding = false
    @State private var branchToEdit: RemoteBranchSummary?

    init(repository: RemoteBranchRepository, pumpRepository: RemotePumpRepository? = nil, tankRepository: RemoteTankRepository? = nil, offlineStore: RemoteOfflineStore, scope: RemoteDataScope, canManageBranches: Bool = false, canActivateBranches: Bool = false, canReadInventory: Bool = false, canReadFuel: Bool = false, canReadInfrastructure: Bool = false, canReadStaff: Bool = false, canManageStaff: Bool = false, canReadPrices: Bool = false, canProposePrices: Bool = false) {
        self.repository = repository
        self.pumpRepository = pumpRepository
        self.tankRepository = tankRepository
        self.offlineStore = offlineStore
        self.scope = scope
        self.canManageBranches = canManageBranches
        self.canActivateBranches = canActivateBranches
        self.canReadInventory = canReadInventory
        self.canReadFuel = canReadFuel
        self.canReadInfrastructure = canReadInfrastructure
        self.canReadStaff = canReadStaff
        self.canManageStaff = canManageStaff
        self.canReadPrices = canReadPrices
        self.canProposePrices = canProposePrices
        _vm = StateObject(wrappedValue: RemoteBranchesViewModel(repository: repository, offlineStore: offlineStore, scope: scope))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sucursales").font(.largeTitle.weight(.bold))
                        Text("Directorio de la red · datos del servidor")
                            .font(.subheadline).foregroundStyle(DLCTheme.muted)
                    }
                    Spacer()
                    if canManageBranches {
                        Button {
                            branchToEdit = nil
                            showOnboarding = true
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(DLCTheme.orange)
                        }
                        .accessibilityLabel("Crear sucursal")
                    }
                }
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(DLCTheme.muted)
                    TextField("Buscar nombre, código o zona", text: $vm.query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: vm.query) { _, value in
                            if value.count > 100 { vm.query = String(value.prefix(100)) }
                        }
                        .onSubmit { Task { await vm.load() } }
                    Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Actualizar sucursales")
                }
                .padding(12).background(DLCTheme.surface).clipShape(RoundedRectangle(cornerRadius: 12))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RemoteBranchFilter.allCases) { filter in
                            Button {
                                guard vm.filter != filter else { return }
                                vm.filter = filter
                                Task { await vm.load() }
                            } label: {
                                Text(filter.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(vm.filter == filter ? Color.white : DLCTheme.ink)
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(vm.filter == filter ? DLCTheme.forest : DLCTheme.surface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if vm.isLoading && vm.branches.isEmpty {
                    ProgressView("Cargando sucursales…").frame(maxWidth: .infinity).padding(28)
                } else if vm.branches.isEmpty {
                    if !vm.errorMessage.isEmpty {
                        Label(vm.errorMessage, systemImage: "wifi.exclamationmark")
                            .font(.footnote).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true)
                    } else {
                        ContentUnavailableView("Sin sucursales", systemImage: "building.2", description: Text("No hay sucursales para este filtro o búsqueda."))
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                } else {
                    if vm.isStale, let date = vm.lastUpdated {
                        Label("Datos guardados · \(date.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.arrow.circlepath")
                            .font(.caption).foregroundStyle(DLCTheme.orange)
                    }
                    if !vm.errorMessage.isEmpty {
                        Label(vm.errorMessage, systemImage: "wifi.exclamationmark")
                            .font(.footnote).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(vm.branches.count) resultados cargados")
                        .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.muted)
                    LazyVStack(spacing: 10) {
                        ForEach(vm.branches) { branch in
                            HStack(spacing: 8) {
                                NavigationLink {
                                    RemoteBranchDetailView(
                                        vm: vm,
                                        branchID: branch.id,
                                        tankRepository: tankRepository,
                                        offlineStore: offlineStore,
                                        scope: RemoteDataScope(organizationId: scope.organizationId, userId: scope.userId, branchId: branch.id),
                                        canReadInventory: canReadInventory
                                    )
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "building.2.fill").font(.title3).foregroundStyle(DLCTheme.orange)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("\(branch.name) · \(branch.code)")
                                                .font(.headline).foregroundStyle(DLCTheme.ink)
                                            Text("\(branch.zone.capitalized) · actualizada \(branch.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                                .font(.caption).foregroundStyle(DLCTheme.muted)
                                        }
                                        Spacer(minLength: 0)
                                        Text(remoteBranchStatusLabel(branch.status))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(remoteBranchStatusColor(branch.status))
                                    }
                                    .dlcCard()
                                }
                                .buttonStyle(.plain)
                                if canManageBranches && branch.status == "draft" {
                                    Button {
                                        branchToEdit = branch
                                        showOnboarding = true
                                    } label: {
                                        Image(systemName: "list.clipboard").foregroundStyle(DLCTheme.orange).padding(10)
                                    }
                                    .accessibilityLabel("Continuar configuración de \(branch.name)")
                                }
                            }
                        }
                    }
                    if vm.hasMore {
                        Button { Task { await vm.loadMore() } } label: {
                            if vm.isLoadingMore { ProgressView() } else { Text("Cargar más") }
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
            }.padding(20)
        }
        .navigationTitle("Red DLC")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .task { if vm.branches.isEmpty { await vm.load() } }
        .sheet(isPresented: $showOnboarding, onDismiss: { Task { await vm.load() } }) {
            NavigationStack {
                RemoteBranchOnboardingView(
                    repository: repository,
                    pumpRepository: pumpRepository,
                    tankRepository: tankRepository,
                    offlineStore: offlineStore,
                    scope: scope,
                    initialBranchID: branchToEdit?.id,
                    canManageBranches: canManageBranches,
                    canActivateBranches: canActivateBranches,
                    canReadFuel: canReadFuel,
                    canReadInfrastructure: canReadInfrastructure,
                    canReadStaff: canReadStaff,
                    canManageStaff: canManageStaff,
                    canReadPrices: canReadPrices,
                    canProposePrices: canProposePrices
                )
            }
        }
    }
}

@MainActor
private struct RemoteBranchOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    let repository: RemoteBranchRepository
    let pumpRepository: RemotePumpRepository?
    let tankRepository: RemoteTankRepository?
    let offlineStore: RemoteOfflineStore
    let scope: RemoteDataScope
    let canManageBranches: Bool
    let canActivateBranches: Bool
    let canReadFuel: Bool
    let canReadInfrastructure: Bool
    let canReadStaff: Bool
    let canManageStaff: Bool
    let canReadPrices: Bool
    let canProposePrices: Bool
    @State private var branchID: UUID?
    @State private var branch: RemoteBranchDetail?
    @State private var readiness: RemoteBranchReadiness?
    @State private var code = ""
    @State private var name = ""
    @State private var zone = "occidental"
    @State private var timezone = "America/El_Salvador"
    @State private var profile = "operational"
    @State private var expectedDispenserCount = "6"
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var statusMessage = ""
    @State private var confirmActivation = false

    init(repository: RemoteBranchRepository, pumpRepository: RemotePumpRepository?, tankRepository: RemoteTankRepository?, offlineStore: RemoteOfflineStore, scope: RemoteDataScope, initialBranchID: UUID?, canManageBranches: Bool, canActivateBranches: Bool, canReadFuel: Bool, canReadInfrastructure: Bool, canReadStaff: Bool, canManageStaff: Bool, canReadPrices: Bool, canProposePrices: Bool) {
        self.repository = repository
        self.pumpRepository = pumpRepository
        self.tankRepository = tankRepository
        self.offlineStore = offlineStore
        self.scope = scope
        self.canManageBranches = canManageBranches
        self.canActivateBranches = canActivateBranches
        self.canReadFuel = canReadFuel
        self.canReadInfrastructure = canReadInfrastructure
        self.canReadStaff = canReadStaff
        self.canManageStaff = canManageStaff
        self.canReadPrices = canReadPrices
        self.canProposePrices = canProposePrices
        _branchID = State(initialValue: initialBranchID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(branchID == nil ? "Nueva sucursal" : "Preparación de sucursal")
                        .font(.largeTitle.weight(.bold))
                    Text(branchID == nil ? "Crea un borrador y completa su preparación por etapas." : "El estado se consulta al servidor y puedes retomar este borrador después.")
                        .font(.subheadline).foregroundStyle(DLCTheme.muted)
                }
                if !errorMessage.isEmpty {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true)
                        .dlcCard(color: DLCTheme.orangeBG)
                }
                if !statusMessage.isEmpty {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(DLCTheme.green).fixedSize(horizontal: false, vertical: true)
                }
                if branchID == nil {
                    draftForm
                } else if isLoading && branch == nil {
                    ProgressView("Cargando borrador…").frame(maxWidth: .infinity).padding(28)
                } else if let branch, let readiness {
                    onboardingContent(branch: branch, readiness: readiness)
                } else {
                    ContentUnavailableView("No se pudo abrir la sucursal", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                }
            }
            .padding(20)
        }
        .navigationTitle("Alta de sucursal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } }
            if branchID != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Actualizar preparación")
                }
            }
        }
        .confirmationDialog("¿Activar esta sucursal?", isPresented: $confirmActivation, titleVisibility: .visible) {
            Button("Activar sucursal", role: .destructive) { Task { await activate() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La API volverá a comprobar los requisitos dentro de la transacción. Si algún dato cambió, la activación será rechazada.")
        }
        .task(id: branchID) { if branchID != nil { await reload() } }
    }

    private var draftForm: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Datos iniciales").font(.headline)
            TextField("Código", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder).accessibilityLabel("Código de sucursal")
            TextField("Nombre de sucursal", text: $name).textFieldStyle(.roundedBorder)
            Picker("Zona", selection: $zone) {
                Text("Occidental").tag("occidental")
                Text("Central").tag("central")
                Text("Oriental").tag("oriental")
                Text("Otra").tag("other")
            }
            TextField("Zona horaria IANA", text: $timezone).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            Picker("Perfil de operación", selection: $profile) {
                Text("Operación configurable").tag("operational")
                Text("Laboratorio 22 · 6 bombas").tag("academicLab22")
            }
            if profile == "operational" {
                TextField("Bombas construidas", text: $expectedDispenserCount)
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
            } else {
                Label("El perfil del laboratorio fija exactamente seis bombas.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            }
            Button {
                Task { await createDraft() }
            } label: {
                if isSaving { ProgressView().frame(maxWidth: .infinity) }
                else { Label("Crear borrador", systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent).tint(DLCTheme.orangeFill)
            .disabled(isSaving || !canManageBranches)
        }
        .padding(16).dlcCard()
    }

    @ViewBuilder
    private func onboardingContent(branch: RemoteBranchDetail, readiness: RemoteBranchReadiness) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(branch.name).font(.title2.weight(.bold))
                    Spacer()
                    Text(remoteBranchStatusLabel(branch.status)).font(.caption.weight(.semibold)).foregroundStyle(remoteBranchStatusColor(branch.status))
                }
                Text("\(branch.code) · \(branch.zone.capitalized) · versión \(readiness.onboardingVersion)")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
                Text("\(readiness.blockers.count) requisitos pendientes · \(readiness.activeEmployeeCount) personas activas")
                    .font(.subheadline.weight(.medium)).foregroundStyle(readiness.canActivate ? DLCTheme.green : DLCTheme.orange)
            }.dlcCard(color: DLCTheme.orangeBG)

            ForEach(["identity", "products", "tanks", "dispensers", "openingBalances", "staff", "prices", "review"], id: \.self) { step in
                onboardingStep(step, readiness: readiness)
            }

            if branch.status == "draft" && canManageBranches {
                identityEditor(branch: branch, readiness: readiness)
                staffReview(readiness: readiness)
            }

            if !readiness.blockers.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pendientes que bloquean la activación").font(.headline)
                    ForEach(readiness.blockers) { blocker in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(DLCTheme.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(blocker.message).font(.subheadline)
                                Text(blocker.step).font(.caption).foregroundStyle(DLCTheme.muted)
                            }
                        }
                    }
                }.dlcCard()
            }

            if readiness.canActivate && canActivateBranches && branch.status == "draft" {
                Button { confirmActivation = true } label: {
                    Label("Activar sucursal", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(DLCTheme.greenFill).disabled(isSaving)
            } else if readiness.canActivate && branch.status != "draft" {
                Label("Sucursal activa", systemImage: "checkmark.seal.fill").foregroundStyle(DLCTheme.green).dlcCard()
            }
        }
    }

    @ViewBuilder
    private func onboardingStep(_ step: String, readiness: RemoteBranchReadiness) -> some View {
        let blocker = readiness.blockers.first(where: { $0.step == step })
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: blocker == nil ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(blocker == nil ? DLCTheme.green : DLCTheme.orange)
                Text(stepTitle(step)).font(.subheadline.weight(.semibold))
                Spacer()
                Text(blocker == nil ? "Listo" : "Pendiente").font(.caption.weight(.semibold))
                    .foregroundStyle(blocker == nil ? DLCTheme.green : DLCTheme.orange)
            }
            if let blocker { Text(blocker.message).font(.caption).foregroundStyle(DLCTheme.muted) }
            if step == "tanks", let tankRepository, let branchID {
                NavigationLink { RemoteTanksDirectoryView(repository: tankRepository, offlineStore: offlineStore, scope: scoped(to: branchID), branchID: branchID).onDisappear { Task { await reload() } } } label: {
                    Label("Revisar tanques e inventario", systemImage: "drop.fill").font(.caption.weight(.semibold))
                }
            } else if step == "products", let branchID, canReadFuel && canReadInfrastructure {
                NavigationLink { RemoteFuelOfferSetupView(repository: repository, branchID: branchID, canManageBranches: canManageBranches).onDisappear { Task { await reload() } } } label: {
                    Label("Configurar combustibles", systemImage: "fuelpump.fill").font(.caption.weight(.semibold))
                }
            } else if step == "products" && (!canReadFuel || !canReadInfrastructure) {
                Label("Se requieren permisos de lectura de combustible e infraestructura para configurar este paso.", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            } else if step == "openingBalances", let tankRepository, let branchID {
                NavigationLink { RemoteTanksDirectoryView(repository: tankRepository, offlineStore: offlineStore, scope: scoped(to: branchID), branchID: branchID).onDisappear { Task { await reload() } } } label: {
                    Label("Revisar saldos y movimientos", systemImage: "list.bullet.rectangle").font(.caption.weight(.semibold))
                }
            } else if step == "dispensers", let pumpRepository, let branchID {
                NavigationLink { RemotePumpsOverviewView(repository: pumpRepository, offlineStore: offlineStore, scope: scoped(to: branchID), branchID: branchID).onDisappear { Task { await reload() } } } label: {
                    Label("Revisar bombas y mangueras", systemImage: "fuelpump.fill").font(.caption.weight(.semibold))
                }
            } else if step == "staff", let branchID, canReadStaff {
                NavigationLink { RemoteBranchStaffSetupView(repository: repository, branchID: branchID, canManageStaff: canManageStaff).onDisappear { Task { await reload() } } } label: {
                    Label("Revisar y agregar personal", systemImage: "person.2.fill").font(.caption.weight(.semibold))
                }
            } else if step == "staff" && !canReadStaff {
                Label("Se requiere permiso de lectura de personal para consultar este paso.", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            } else if step == "prices", let branchID, canReadPrices {
                NavigationLink { RemoteBranchPriceSetupView(repository: repository, branchID: branchID, canProposePrices: canProposePrices, canReadFuel: canReadFuel, canReadInfrastructure: canReadInfrastructure).onDisappear { Task { await reload() } } } label: {
                    Label("Revisar y proponer precios", systemImage: "dollarsign.circle").font(.caption.weight(.semibold))
                }
            } else if step == "prices" && !canReadPrices {
                Label("Se requiere permiso de lectura de precios para consultar este paso.", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            }
        }
        .padding(13).dlcCard()
    }

    private func identityEditor(branch: RemoteBranchDetail, readiness: RemoteBranchReadiness) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Identidad del borrador").font(.headline)
            TextField("Código", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            TextField("Nombre", text: $name).textFieldStyle(.roundedBorder)
            Picker("Zona", selection: $zone) {
                Text("Occidental").tag("occidental"); Text("Central").tag("central"); Text("Oriental").tag("oriental"); Text("Otra").tag("other")
            }
            TextField("Zona horaria IANA", text: $timezone).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            Button("Guardar identidad") { Task { await saveIdentity(version: readiness.onboardingVersion) } }
                .buttonStyle(.bordered).disabled(isSaving)
        }.padding(15).dlcCard()
        .onAppear {
            if code.isEmpty { code = branch.code }
            if name.isEmpty { name = branch.name }
            if timezone == "America/El_Salvador" { timezone = branch.timezone }
            zone = branch.zone
        }
    }

    private func staffReview(readiness: RemoteBranchReadiness) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Revisión de personal").font(.headline)
            Text("Hay \(readiness.activeEmployeeCount) personas activas. Si cambia la cantidad, confirma de nuevo antes de activar.")
                .font(.caption).foregroundStyle(DLCTheme.muted)
            HStack {
                Button("Confirmar cantidad") {
                    Task { await saveStaffReview(status: "confirmed", count: readiness.activeEmployeeCount, version: readiness.onboardingVersion) }
                }
                .buttonStyle(.borderedProminent).tint(DLCTheme.forest)
                .disabled(isSaving || readiness.activeEmployeeCount < 1)
                Button("Dejar pendiente") {
                    Task { await saveStaffReview(status: "deferred", count: readiness.activeEmployeeCount, version: readiness.onboardingVersion) }
                }.buttonStyle(.bordered).disabled(isSaving)
            }
        }.padding(15).dlcCard()
    }

    private func createDraft() async {
        errorMessage = ""; statusMessage = ""
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = profile == "academicLab22" ? 6 : Int(expectedDispenserCount)
        guard !cleanCode.isEmpty, !cleanName.isEmpty, !timezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let count, (1...200).contains(count) else {
            errorMessage = "Completa código, nombre, zona horaria y una cantidad de 1 a 200 bombas."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let created = try await repository.createBranchDraft(RemoteCreateBranchDraft(code: cleanCode, name: cleanName, zone: zone, timezone: timezone.trimmingCharacters(in: .whitespacesAndNewlines), profile: profile, expectedDispenserCount: count))
            isLoading = true
            branchID = created.id
            statusMessage = "Borrador guardado en el servidor. Puedes salir y continuar después."
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveIdentity(version: Int) async {
        guard let branchID else { return }
        errorMessage = ""; isSaving = true; defer { isSaving = false }
        let data = RemoteBranchOnboardingData(code: code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), zone: zone, timezone: timezone.trimmingCharacters(in: .whitespacesAndNewlines))
        do { try await repository.saveOnboardingStep(branchID: branchID, expectedVersion: version, step: "identity", data: data); statusMessage = "Identidad actualizada."; await reload() }
        catch { errorMessage = error.localizedDescription }
    }

    private func saveStaffReview(status: String, count: Int, version: Int) async {
        guard let branchID else { return }
        errorMessage = ""; isSaving = true; defer { isSaving = false }
        do {
            try await repository.saveOnboardingStep(branchID: branchID, expectedVersion: version, step: "staff", data: RemoteBranchOnboardingData(status: status, employeeCount: count))
            statusMessage = status == "confirmed" ? "Revisión de personal registrada." : "La revisión quedó pendiente."
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    private func activate() async {
        guard let branchID, let readiness else { return }
        errorMessage = ""; isSaving = true; defer { isSaving = false }
        do { try await repository.activateBranch(branchID: branchID, expectedVersion: readiness.onboardingVersion); statusMessage = "Sucursal activada."; await reload() }
        catch { errorMessage = error.localizedDescription; await reload() }
    }

    private func reload() async {
        guard let branchID else { return }
        isLoading = true; errorMessage = ""
        defer { isLoading = false }
        do {
            async let branchTask = repository.branchDetail(branchID: branchID)
            async let readinessTask = repository.branchReadiness(branchID: branchID)
            let (loadedBranch, loadedReadiness) = try await (branchTask, readinessTask)
            branch = loadedBranch; readiness = loadedReadiness
            if code.isEmpty { code = loadedBranch.code }
            if name.isEmpty { name = loadedBranch.name }
            zone = loadedBranch.zone; timezone = loadedBranch.timezone
        } catch { errorMessage = error.localizedDescription }
    }

    private func scoped(to branchID: UUID) -> RemoteDataScope {
        RemoteDataScope(organizationId: scope.organizationId, userId: scope.userId, branchId: branchID)
    }

    private func stepTitle(_ step: String) -> String {
        switch step {
        case "identity": "Identidad y perfil"
        case "products": "Combustibles"
        case "tanks": "Tanques"
        case "dispensers": "Bombas y mangueras"
        case "openingBalances": "Saldos iniciales"
        case "staff": "Personal activo"
        case "prices": "Precios vigentes"
        default: "Revisión final"
        }
    }
}

private struct RemoteFuelOfferSetupView: View {
    let repository: RemoteBranchRepository
    let branchID: UUID
    let canManageBranches: Bool
    @State private var products: [RemoteFuelProductSummary] = []
    @State private var offers: [RemoteBranchFuelOffer] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showCreateProduct = false

    private var enabledIDs: Set<UUID> { Set(offers.filter { $0.status == "active" }.map(\.id)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Combustibles de la sucursal").font(.largeTitle.weight(.bold))
                Text("Activa únicamente productos que se venderán en esta ubicación. El tipo de combustible se asigna después a tanques y mangueras.")
                    .font(.subheadline).foregroundStyle(DLCTheme.muted)
                if !errorMessage.isEmpty { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(DLCTheme.red).dlcCard(color: DLCTheme.orangeBG) }
                if canManageBranches {
                    Button { showCreateProduct = true } label: { Label("Crear producto de combustible", systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(DLCTheme.orangeFill)
                }
                if isLoading && products.isEmpty { ProgressView("Cargando combustibles…").frame(maxWidth: .infinity).padding(20) }
                ForEach(products) { product in
                    HStack(spacing: 12) {
                        Image(systemName: productIcon(product.family)).foregroundStyle(fuelColor(product.family)).font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.displayName).font(.headline)
                            Text("\(product.sku) · \(product.family.capitalized)\(product.brand.map { " · \($0)" } ?? "")")
                                .font(.caption).foregroundStyle(DLCTheme.muted)
                        }
                        Spacer(minLength: 6)
                        if enabledIDs.contains(product.id) {
                            Label("Activo", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.green)
                        } else if canManageBranches {
                            Button("Habilitar") { Task { await enable(product.id) } }
                                .buttonStyle(.bordered).tint(DLCTheme.orange).disabled(isLoading)
                        } else {
                            Text("No habilitado").font(.caption).foregroundStyle(DLCTheme.muted)
                        }
                    }.padding(14).dlcCard()
                }
                if let cursor {
                    Button { Task { await loadMore(cursor) } } label: {
                        if isLoading { ProgressView().frame(maxWidth: .infinity) }
                        else { Text("Cargar más combustibles").frame(maxWidth: .infinity) }
                    }.buttonStyle(.bordered).disabled(isLoading)
                }
                if products.isEmpty && !isLoading { ContentUnavailableView("No hay combustibles activos", systemImage: "fuelpump", description: Text("Crea el producto con una cuenta que tenga permiso branch.manage.")) }
            }.padding(20)
        }
        .navigationTitle("Combustibles")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .sheet(isPresented: $showCreateProduct, onDismiss: { Task { await reload() } }) {
            NavigationStack { RemoteFuelProductCreateView(repository: repository) }
        }
    }

    private func reload() async {
        isLoading = true; errorMessage = ""; defer { isLoading = false }
        do {
            async let productPage = repository.fuelProducts(cursor: nil)
            async let configuration = repository.branchConfiguration(branchID: branchID)
            let (page, config) = try await (productPage, configuration)
            products = page.data; cursor = page.meta.nextCursor; offers = config.fuelOffers
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadMore(_ next: String) async {
        isLoading = true; errorMessage = ""; defer { isLoading = false }
        do { let page = try await repository.fuelProducts(cursor: next); products.append(contentsOf: page.data); cursor = page.meta.nextCursor }
        catch { errorMessage = error.localizedDescription }
    }

    private func enable(_ productID: UUID) async {
        isLoading = true; errorMessage = ""; defer { isLoading = false }
        do { try await repository.enableFuelOffer(branchID: branchID, fuelProductID: productID); await reload() }
        catch { errorMessage = error.localizedDescription }
    }

    private func productIcon(_ family: String) -> String { family == "diesel" ? "drop.fill" : "fuelpump.fill" }
    private func fuelColor(_ family: String) -> Color { family == "diesel" ? DLCTheme.ink : (family == "super" ? DLCTheme.orange : DLCTheme.red) }
}

private struct RemoteFuelProductCreateView: View {
    @Environment(\.dismiss) private var dismiss
    let repository: RemoteBranchRepository
    @State private var sku = ""
    @State private var name = ""
    @State private var family = "regular"
    @State private var brand = ""
    @State private var errorMessage = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("Ficha del producto") {
                TextField("Código SKU", text: $sku).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField("Nombre comercial", text: $name)
                Picker("Familia", selection: $family) {
                    Text("Súper").tag("super"); Text("Regular").tag("regular"); Text("Diésel").tag("diesel"); Text("Otro").tag("other")
                }
                TextField("Marca (opcional)", text: $brand)
            }
            if !errorMessage.isEmpty { Section { Text(errorMessage).foregroundStyle(DLCTheme.red) } }
            Section { Button(isSaving ? "Guardando…" : "Crear producto") { Task { await save() } }.disabled(isSaving || sku.trimmingCharacters(in: .whitespacesAndNewlines).count < 1 || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
        .navigationTitle("Nuevo combustible")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
    }

    private func save() async {
        errorMessage = ""; isSaving = true; defer { isSaving = false }
        do {
            try await repository.createFuelProduct(RemoteCreateFuelProduct(sku: sku.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), displayName: name.trimmingCharacters(in: .whitespacesAndNewlines), family: family, brand: brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : brand.trimmingCharacters(in: .whitespacesAndNewlines)))
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct RemoteBranchStaffSetupView: View {
    let repository: RemoteBranchRepository
    let branchID: UUID
    let canManageStaff: Bool
    @State private var employees: [RemoteEmployeeSummary] = []
    @State private var cursor: String?
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showCreateEmployee = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Personal de la sucursal").font(.largeTitle.weight(.bold))
                Text("Solo se cuentan personas activas para validar la preparación. Los datos privados se muestran de acuerdo con los permisos de la cuenta.")
                    .font(.subheadline).foregroundStyle(DLCTheme.muted)
                Text("\(employees.filter { $0.status == "active" }.count) personas activas cargadas")
                    .font(.headline).padding(14).frame(maxWidth: .infinity, alignment: .leading).dlcCard(color: DLCTheme.orangeBG)
                if canManageStaff {
                    Button { showCreateEmployee = true } label: { Label("Agregar persona", systemImage: "person.badge.plus").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(DLCTheme.orangeFill)
                }
                if !errorMessage.isEmpty { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(DLCTheme.red).dlcCard(color: DLCTheme.orangeBG) }
                ForEach(employees) { employee in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(employee.legalName).font(.headline); Spacer(); Text(employee.status.capitalized).font(.caption.weight(.semibold)).foregroundStyle(employee.status == "active" ? DLCTheme.green : DLCTheme.muted) }
                        Text("\(employee.employeeCode) · \(employee.positionTitle)").font(.caption).foregroundStyle(DLCTheme.muted)
                    }.padding(14).dlcCard()
                }
                if let cursor { Button { Task { await loadMore(cursor) } } label: { if isLoading { ProgressView().frame(maxWidth: .infinity) } else { Text("Cargar más personal").frame(maxWidth: .infinity) } }.buttonStyle(.bordered).disabled(isLoading) }
                if employees.isEmpty && !isLoading { ContentUnavailableView("No hay personal registrado", systemImage: "person.2", description: Text(canManageStaff ? "Agrega por lo menos una persona activa para continuar." : "Solicita a una cuenta con permiso staff.manage que registre al personal.")) }
            }.padding(20)
        }
        .navigationTitle("Personal")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .sheet(isPresented: $showCreateEmployee, onDismiss: { Task { await reload() } }) { NavigationStack { RemoteBranchEmployeeCreateView(repository: repository, branchID: branchID) } }
    }

    private func reload() async {
        isLoading = true; errorMessage = ""; defer { isLoading = false }
        do { let page = try await repository.employees(branchID: branchID, cursor: nil); employees = page.data; cursor = page.meta.nextCursor }
        catch { errorMessage = error.localizedDescription }
    }

    private func loadMore(_ next: String) async {
        isLoading = true; errorMessage = ""; defer { isLoading = false }
        do { let page = try await repository.employees(branchID: branchID, cursor: next); employees.append(contentsOf: page.data); cursor = page.meta.nextCursor }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct RemoteBranchEmployeeCreateView: View {
    @Environment(\.dismiss) private var dismiss
    let repository: RemoteBranchRepository
    let branchID: UUID
    @State private var employeeCode = ""
    @State private var legalName = ""
    @State private var positionTitle = ""
    @State private var contactEmail = ""
    @State private var errorMessage = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("Ficha de personal") {
                TextField("Código de empleado", text: $employeeCode).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField("Nombre legal", text: $legalName)
                TextField("Puesto", text: $positionTitle)
                TextField("Correo de contacto (opcional)", text: $contactEmail).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if !errorMessage.isEmpty { Section { Text(errorMessage).foregroundStyle(DLCTheme.red) } }
            Section { Button(isSaving ? "Guardando…" : "Crear persona activa") { Task { await save() } }.disabled(isSaving || employeeCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || legalName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || positionTitle.trimmingCharacters(in: .whitespacesAndNewlines).count < 2) }
        }
        .navigationTitle("Agregar personal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
    }

    private func save() async {
        errorMessage = ""; isSaving = true; defer { isSaving = false }
        let email = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await repository.createEmployee(branchID: branchID, input: RemoteCreateEmployee(employeeCode: employeeCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), legalName: legalName.trimmingCharacters(in: .whitespacesAndNewlines), positionTitle: positionTitle.trimmingCharacters(in: .whitespacesAndNewlines), contactEmail: email.isEmpty ? nil : email))
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct RemoteBranchPriceSetupView: View {
    let repository: RemoteBranchRepository
    let branchID: UUID
    let canProposePrices: Bool
    let canReadFuel: Bool
    let canReadInfrastructure: Bool
    @State private var products: [RemoteFuelProductSummary] = []
    @State private var enabledProductIDs: Set<UUID> = []
    @State private var board: RemoteBranchFuelPriceBoard?
    @State private var proposals: [RemoteFuelPriceProposal] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showProposalForm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Precios de combustible").font(.largeTitle.weight(.bold))
                Text("Los precios se proponen con vigencia futura. Otra persona con permiso de aprobación debe resolverlos; el sistema no aplica una propuesta por el hecho de capturarla.")
                    .font(.subheadline).foregroundStyle(DLCTheme.muted)
                if !errorMessage.isEmpty { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(DLCTheme.red).dlcCard(color: DLCTheme.orangeBG) }
                if canProposePrices && canReadFuel && canReadInfrastructure {
                    Button { showProposalForm = true } label: { Label("Proponer precio", systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(DLCTheme.orangeFill)
                } else if canProposePrices {
                    Label("Para proponer precios también se requiere lectura del catálogo y de la configuración de la sucursal.", systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(DLCTheme.muted).dlcCard(color: DLCTheme.orangeBG)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Precios vigentes").font(.headline)
                    if let board, !board.current.isEmpty {
                        ForEach(board.current) { price in priceRow(price, label: "Vigente") }
                    } else if !isLoading { Text("No hay precios vigentes.").font(.subheadline).foregroundStyle(DLCTheme.muted) }
                }.padding(14).dlcCard()
                if let board, !board.upcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Programados").font(.headline)
                        ForEach(board.upcoming) { price in priceRow(price, label: "Desde \(price.effectiveAt.formatted(date: .abbreviated, time: .shortened))") }
                    }.padding(14).dlcCard()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Propuestas").font(.headline)
                    if proposals.isEmpty && !isLoading { Text("No hay propuestas registradas.").font(.subheadline).foregroundStyle(DLCTheme.muted) }
                    ForEach(proposals) { proposal in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(proposal.productName ?? productName(proposal.fuelProductId)).font(.subheadline.weight(.semibold)); Spacer(); Text(proposal.status.replacingOccurrences(of: "_", with: " ")).font(.caption.weight(.semibold)).foregroundStyle(proposal.status == "approved" || proposal.status == "scheduled" ? DLCTheme.green : DLCTheme.orange) }
                            Text("\(proposal.serviceMode == "full_service" ? "Servicio completo" : "Autoservicio") · $\(proposal.priceUsdPerUnit) / \(proposal.unit) · \(proposal.effectiveAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(DLCTheme.muted)
                            Text(proposal.reason).font(.caption)
                            if proposal.status == "pending_approval" && proposal.createdBy == nil { Text("El API no devolvió quién creó esta propuesta; resuélvela desde una cuenta autorizada.").font(.caption).foregroundStyle(DLCTheme.muted) }
                        }.padding(12).background(DLCTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    }
                }.padding(14).dlcCard()
                if isLoading { ProgressView().frame(maxWidth: .infinity).padding(10) }
            }.padding(20)
        }
        .navigationTitle("Precios")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Actualizar precios") } }
        .task { await reload() }
        .sheet(isPresented: $showProposalForm, onDismiss: { Task { await reload() } }) {
            NavigationStack { RemoteFuelPriceProposalCreateView(repository: repository, branchID: branchID, products: products.filter { enabledProductIDs.contains($0.id) }) }
        }
    }

    private func priceRow(_ price: RemoteBranchFuelPrice, label: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(price.productName ?? productName(price.fuelProductId)).font(.subheadline.weight(.semibold))
                Text("\(price.serviceMode == "full_service" ? "Servicio completo" : "Autoservicio") · \(label)").font(.caption).foregroundStyle(DLCTheme.muted)
            }
            Spacer()
            Text("$\(price.priceUsdPerUnit) / \(price.unit)").font(.subheadline.weight(.bold))
        }.padding(.vertical, 4)
    }

    private func productName(_ id: UUID) -> String { products.first(where: { $0.id == id })?.displayName ?? "Combustible" }

    private func reload() async {
        isLoading = true; errorMessage = ""; defer { isLoading = false }
        do {
            async let prices = repository.fuelPriceBoard(branchID: branchID)
            async let proposals = repository.fuelPriceProposals(branchID: branchID)
            let (priceBoard, priceProposals) = try await (prices, proposals)
            board = priceBoard; self.proposals = priceProposals
        } catch { errorMessage = error.localizedDescription; return }
        guard canReadFuel && canReadInfrastructure else { products = []; enabledProductIDs = []; return }
        do {
            async let page = repository.fuelProducts(cursor: nil)
            async let configuration = repository.branchConfiguration(branchID: branchID)
            let (productPage, config) = try await (page, configuration)
            products = productPage.data
            enabledProductIDs = Set(config.fuelOffers.filter { $0.status == "active" }.map(\.id))
        } catch { errorMessage = "Precios cargados, pero no se pudo consultar el catálogo o las ofertas: \(error.localizedDescription)" }
    }
}

private struct RemoteFuelPriceProposalCreateView: View {
    @Environment(\.dismiss) private var dismiss
    let repository: RemoteBranchRepository
    let branchID: UUID
    let products: [RemoteFuelProductSummary]
    @State private var selectedProductID: UUID?
    @State private var serviceMode = "full_service"
    @State private var price = ""
    @State private var unit = "us_gallon"
    @State private var effectiveAt = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var reason = ""
    @State private var errorMessage = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("Propuesta") {
                if products.isEmpty { Text("Habilita un combustible para la sucursal antes de proponer un precio.").foregroundStyle(DLCTheme.muted) }
                else {
                    Picker("Combustible", selection: $selectedProductID) {
                        ForEach(products) { product in Text("\(product.displayName) · \(product.sku)").tag(Optional(product.id)) }
                    }
                    Picker("Modalidad", selection: $serviceMode) { Text("Servicio completo").tag("full_service"); Text("Autoservicio").tag("self_service") }
                    TextField("Precio propuesto", text: $price).keyboardType(.decimalPad)
                    Picker("Unidad", selection: $unit) { Text("Por galón US").tag("us_gallon"); Text("Por litro").tag("liter") }
                    DatePicker("Vigente desde", selection: $effectiveAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    TextField("Motivo y referencia", text: $reason, axis: .vertical).lineLimit(3...5)
                }
            }
            if !errorMessage.isEmpty { Section { Text(errorMessage).foregroundStyle(DLCTheme.red) } }
            Section { Button(isSaving ? "Enviando…" : "Enviar para aprobación") { Task { await submit() } }.disabled(isSaving || selectedProductID == nil || !validPrice || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || effectiveAt <= .now) }
        }
        .navigationTitle("Nuevo precio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
        .onAppear { selectedProductID = selectedProductID ?? products.first?.id }
    }

    private var validPrice: Bool { guard let value = Decimal(string: price.replacingOccurrences(of: ",", with: ".")), value > 0 else { return false }; return true }

    private func submit() async {
        guard let selectedProductID, let value = Decimal(string: price.replacingOccurrences(of: ",", with: ".")), value > 0 else { errorMessage = "Ingresa un precio mayor que cero."; return }
        errorMessage = ""; isSaving = true; defer { isSaving = false }
        do {
            try await repository.createFuelPriceProposal(branchID: branchID, input: RemoteCreateFuelPriceProposal(fuelProductId: selectedProductID, serviceMode: serviceMode, priceUsdPerUnit: NSDecimalNumber(decimal: value).stringValue, unit: unit, effectiveAt: effectiveAt, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)))
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

@MainActor
private struct RemoteBranchDetailView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var vm: RemoteBranchesViewModel
    let branchID: UUID
    let tankRepository: RemoteTankRepository?
    let offlineStore: RemoteOfflineStore
    let scope: RemoteDataScope
    let canReadInventory: Bool

    private var detail: RemoteBranchDetail? {
        vm.selectedBranch?.id == branchID ? vm.selectedBranch : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if vm.isDetailStale, let date = vm.detailLastUpdated {
                    Label("Ficha guardada · \(date.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(DLCTheme.orange)
                }
                if !vm.detailErrorMessage.isEmpty {
                    Label(vm.detailErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true)
                }
                if let detail {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(detail.name).font(.title2.weight(.bold))
                        Text("\(detail.code) · \(detail.zone.capitalized)").font(.subheadline).foregroundStyle(DLCTheme.muted)
                        Text(remoteBranchStatusLabel(detail.status))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(remoteBranchStatusColor(detail.status))
                    }.dlcCard(color: DLCTheme.orangeBG)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Datos de la sucursal").font(.headline)
                        remoteBranchDetailRow("Zona horaria", value: detail.timezone)
                        remoteBranchDetailRow("Versión de configuración", value: "\(detail.onboardingVersion)")
                        remoteBranchDetailRow("Creada", value: detail.createdAt.formatted(date: .long, time: .shortened))
                        remoteBranchDetailRow("Última actualización", value: detail.updatedAt.formatted(date: .long, time: .shortened))
                        if let configuredAt = detail.configuredAt {
                            remoteBranchDetailRow("Configurada", value: configuredAt.formatted(date: .long, time: .shortened))
                        }
                        if let activatedAt = detail.activatedAt {
                            remoteBranchDetailRow("Activada", value: activatedAt.formatted(date: .long, time: .shortened))
                        }
                    }.dlcCard()
                    Text("Esta ficha muestra el estado y la configuración registrados por el servidor. Las ventas y los cortes consolidados de la red se incorporarán cuando sus consultas estén conectadas.")
                        .font(.footnote).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                    if let repository = appState.remotePumpRepository {
                        if appState.remoteCapabilities?.permissions.contains("pos.catalog.read") == true {
                            NavigationLink {
                                RemotePOSCatalogView(repository: repository, store: offlineStore, scope: scope, branchID: branchID,
                                    canManage: appState.remoteCapabilities?.permissions.contains("pos.catalog.manage") == true,
                                    canReceive: appState.remoteCapabilities?.permissions.contains("pos.stock.receive") == true,
                                    canSell: appState.remoteCapabilities?.permissions.contains("sale.create") == true,
                                    canReadCost: appState.remoteCapabilities?.permissions.contains("finance.cost.read") == true)
                            } label: {
                                Label("Tienda y servicios", systemImage: "basket.fill").frame(maxWidth: .infinity, alignment: .leading)
                            }.dlcCard()
                        }
                        if appState.remoteCapabilities?.permissions.contains("sale.read") == true {
                            NavigationLink { RemoteFuelSalesView(repository: repository, branchID: branchID) } label: {
                                Label("Ventas", systemImage: "receipt").frame(maxWidth: .infinity, alignment: .leading)
                            }.dlcCard()
                        }
                    }
                    if canReadInventory, let tankRepository {
                        NavigationLink {
                            RemoteTanksDirectoryView(repository: tankRepository, offlineStore: offlineStore, scope: scope, branchID: branchID)
                        } label: {
                            Label("Ver tanques e inventario", systemImage: "drop.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .dlcCard()
                    }
                } else if vm.isLoadingDetail {
                    ProgressView("Cargando ficha…").frame(maxWidth: .infinity).padding(28)
                }
            }.padding(20)
        }
        .navigationTitle("Detalle de sucursal")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .task(id: branchID) { await vm.loadBranch(branchID) }
    }
}

private func remoteBranchDetailRow(_ title: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(title).font(.subheadline).foregroundStyle(DLCTheme.muted)
        Spacer(minLength: 14)
        Text(value).font(.subheadline.weight(.medium)).multilineTextAlignment(.trailing)
    }
}

private func remoteBranchStatusLabel(_ status: String) -> String {
    switch status {
    case "active": "Activa"
    case "configured": "Configurada"
    case "draft": "Borrador"
    case "suspended": "Suspendida"
    case "archived": "Archivada"
    default: status.capitalized
    }
}

private func remoteBranchStatusColor(_ status: String) -> Color {
    switch status {
    case "active": DLCTheme.green
    case "configured": DLCTheme.green
    case "draft": DLCTheme.yellow
    case "suspended", "archived": DLCTheme.red
    default: DLCTheme.muted
    }
}

struct BranchCard: View {
    let branch: Branch
    let cuts: [DailyCut]

    private var criticalCount: Int { branch.tanks.filter { $0.status == .critical }.count }
    private var stockPercentage: Int {
        guard branch.totalCapacityLiters > 0 else { return 0 }
        return Int((branch.totalInventoryLiters / branch.totalCapacityLiters * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(branch.name).font(.headline)
                    Text("\(branch.code) · \(branch.city), \(branch.department)")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
                Spacer()
                Label(!branch.isActive ? "Archivada" : (criticalCount == 0 ? "Al día" : "Revisar \(criticalCount)"), systemImage: !branch.isActive ? "pause.circle.fill" : (criticalCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(!branch.isActive ? DLCTheme.muted : (criticalCount == 0 ? DLCTheme.green : DLCTheme.red))
            }

            HStack(spacing: 7) {
                Image(systemName: "drop.fill").foregroundStyle(DLCTheme.blue)
                Text("Inventario total")
                Spacer()
                Text("\(stockPercentage)% · \(Int(branch.totalInventoryLiters.rounded()).formatted()) L")
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .foregroundStyle(DLCTheme.ink)

            ForEach(branch.tanks) { tank in
                HStack(spacing: 8) {
                    Text(tank.type.rawValue).font(.caption.weight(.medium)).frame(width: 54, alignment: .leading)
                    ProgressView(value: Double(tank.percentage), total: 100).tint(statusColor(tank.status))
                    Text("\(tank.percentage)%").font(.caption2.weight(.semibold)).frame(width: 34, alignment: .trailing)
                }
            }

            Divider()
            ForEach(CutType.allCases) { type in
                let cut = cuts.first(where: { $0.type == type })
                HStack {
                    Text(type.rawValue).foregroundStyle(DLCTheme.muted)
                    Spacer()
                    Text(cutStatus(cut)).fontWeight(.semibold).foregroundStyle(cutColor(cut))
                    Text("· \(cut?.completedPumpCount ?? 0)/6 bombas")
                        .foregroundStyle(DLCTheme.muted)
                }
                .font(.caption)
            }
        }
        .dlcCard()
    }

    private func cutStatus(_ cut: DailyCut?) -> String {
        guard let cut else { return "Sin iniciar" }
        return cut.isClosed ? "Cerrado" : "En curso"
    }

    private func cutColor(_ cut: DailyCut?) -> Color {
        guard let cut else { return DLCTheme.muted }
        return cut.isClosed ? DLCTheme.green : DLCTheme.orange
    }

    private func statusColor(_ status: InventoryStatus) -> Color {
        switch status {
        case .optimal: DLCTheme.green
        case .medium: DLCTheme.yellow
        case .critical: DLCTheme.red
        }
    }
}

@MainActor
struct RemoteTanksDirectoryView: View {
    @StateObject private var vm: RemoteTanksViewModel
    let branchID: UUID

    init(repository: RemoteTankRepository, offlineStore: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID) {
        self.branchID = branchID
        _vm = StateObject(wrappedValue: RemoteTanksViewModel(repository: repository, offlineStore: offlineStore, scope: scope, branchID: branchID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tanques e inventario").font(.largeTitle.weight(.bold))
                    Text("Existencias, capacidad y movimientos registrados")
                        .font(.subheadline).foregroundStyle(DLCTheme.muted)
                }
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(DLCTheme.muted)
                    TextField("Buscar código o nombre", text: $vm.query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: vm.query) { _, value in
                            if value.count > 100 { vm.query = String(value.prefix(100)) }
                        }
                        .onSubmit { Task { await vm.load() } }
                    Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Actualizar tanques")
                }
                .padding(12).background(DLCTheme.surface).clipShape(RoundedRectangle(cornerRadius: 12))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RemoteTankFilter.allCases) { filter in
                            Button {
                                guard vm.filter != filter else { return }
                                vm.filter = filter
                                Task { await vm.load() }
                            } label: {
                                Text(filter.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(vm.filter == filter ? Color.white : DLCTheme.ink)
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(vm.filter == filter ? DLCTheme.forest : DLCTheme.surface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if vm.isLoading && vm.tanks.isEmpty {
                    ProgressView("Cargando tanques…").frame(maxWidth: .infinity).padding(28)
                } else if vm.tanks.isEmpty {
                    if !vm.errorMessage.isEmpty {
                        Label(vm.errorMessage, systemImage: "wifi.exclamationmark")
                            .font(.footnote).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true)
                    } else {
                        ContentUnavailableView("Sin tanques", systemImage: "drop", description: Text("No hay tanques para este filtro o búsqueda."))
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                } else {
                    if vm.isStale, let date = vm.lastUpdated {
                        Label("Datos guardados · \(date.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.arrow.circlepath")
                            .font(.caption).foregroundStyle(DLCTheme.orange)
                    }
                    if !vm.errorMessage.isEmpty {
                        Label(vm.errorMessage, systemImage: "wifi.exclamationmark")
                            .font(.footnote).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(vm.tanks.count) tanques cargados")
                        .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.muted)
                    LazyVStack(spacing: 10) {
                        ForEach(vm.tanks) { tank in
                            NavigationLink {
                                RemoteTankDetailView(vm: vm, tankID: tank.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "drop.fill").font(.title3).foregroundStyle(DLCTheme.blue)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("\(tank.name ?? "Tanque \(tank.code)") · \(tank.fuelName)")
                                            .font(.headline).foregroundStyle(DLCTheme.ink)
                                        Text("\(tank.code) · capacidad \(tank.nominalCapacityL) L")
                                            .font(.caption).foregroundStyle(DLCTheme.muted)
                                    }
                                    Spacer(minLength: 0)
                                    Text(remoteTankStatusLabel(tank.status))
                                        .font(.caption.weight(.semibold)).foregroundStyle(remoteTankStatusColor(tank.status))
                                }.dlcCard()
                            }.buttonStyle(.plain)
                        }
                    }
                    if vm.hasMore {
                        Button { Task { await vm.loadMore() } } label: {
                            if vm.isLoadingMore { ProgressView() } else { Text("Cargar más") }
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
            }.padding(20)
        }
        .navigationTitle("Tanques")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .task { if vm.tanks.isEmpty { await vm.load() } }
    }
}

@MainActor
private struct RemoteTankDetailView: View {
    @ObservedObject var vm: RemoteTanksViewModel
    let tankID: UUID

    private var snapshot: RemoteTankSnapshot? {
        vm.selectedTank?.detail.id == tankID ? vm.selectedTank : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if vm.detailIsStale, let date = vm.detailLastUpdated {
                    Label("Ficha guardada · \(date.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(DLCTheme.orange)
                }
                if !vm.detailErrorMessage.isEmpty {
                    Label(vm.detailErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true)
                }
                if let snapshot {
                    let tank = snapshot.detail
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tank.name ?? "Tanque \(tank.code)").font(.title2.weight(.bold))
                        Text("\(tank.code) · \(tank.fuelName) · \(remoteTankStatusLabel(tank.status))")
                            .font(.subheadline).foregroundStyle(DLCTheme.muted)
                        tankDetailRow("Capacidad nominal", value: "\(tank.nominalCapacityL) L")
                        tankDetailRow("Límite seguro de llenado", value: "\(tank.safeFillLimitL) L")
                        tankDetailRow("Reserva no utilizable", value: "\(tank.unusableReserveL) L")
                    }.dlcCard(color: DLCTheme.orangeBG)

                    if let inventory = snapshot.inventory {
                        if inventory.balanceKnown, let balance = inventory.balance, let quantity = Double(balance.onHandL) {
                            let capacity = Double(tank.nominalCapacityL)
                            let percent = capacity.flatMap { $0 > 0 ? quantity / $0 * 100 : nil }
                            let exceedsSafeFill = Double(tank.safeFillLimitL).map { quantity > $0 } ?? false
                            VStack(alignment: .leading, spacing: 11) {
                                HStack {
                                    Text("Inventario actual").font(.headline)
                                    Spacer()
                                    if let percent {
                                        Text("\(Int(percent.rounded()))%")
                                            .font(.title3.weight(.bold)).foregroundStyle(exceedsSafeFill ? DLCTheme.red : DLCTheme.blue)
                                    }
                                }
                                Text("\(balance.onHandL) L" + (capacity.map { " de \(tank.nominalCapacityL) L nominales" } ?? ""))
                                    .font(.subheadline)
                                if let percent {
                                    ProgressView(value: min(max(percent, 0), 100), total: 100)
                                        .tint(exceedsSafeFill ? DLCTheme.red : DLCTheme.blue)
                                }
                                if exceedsSafeFill {
                                    Label("Supera el límite seguro de llenado. Requiere revisión.", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.red)
                                }
                                tankDetailRow("Valuación", value: remoteValuationLabel(balance.valuationQuality))
                                if let averageCost = balance.averageCostPerLUsd {
                                    tankDetailRow("Costo promedio", value: "$\(averageCost) / L")
                                }
                                if let value = balance.inventoryValueUsd {
                                    tankDetailRow("Valor inventario", value: "$\(value)")
                                }
                                if let updatedAt = balance.updatedAt {
                                    tankDetailRow("Actualizado", value: updatedAt.formatted(date: .long, time: .shortened))
                                }
                            }.dlcCard()
                        } else {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Saldo no establecido").font(.headline)
                                Text("El servidor no tiene una existencia inicial confirmada para este tanque. No se interpreta como cero litros.")
                                    .font(.footnote).foregroundStyle(DLCTheme.muted)
                            }.dlcCard(color: DLCTheme.yellow.opacity(0.16))
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mangueras conectadas").font(.headline)
                        if tank.connections.isEmpty {
                            Text("No hay conexiones vigentes registradas.").font(.subheadline).foregroundStyle(DLCTheme.muted)
                        } else {
                            ForEach(tank.connections) { connection in
                                HStack {
                                    Image(systemName: "fuelpump.fill").foregroundStyle(DLCTheme.orange)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(connection.dispenserCode) · manguera \(connection.nozzleCode)")
                                            .font(.subheadline.weight(.medium))
                                        Text(connection.validUntil == nil ? "Conexión vigente desde \(connection.validFrom.formatted(date: .abbreviated, time: .shortened))" : "Conexión histórica")
                                            .font(.caption).foregroundStyle(DLCTheme.muted)
                                    }
                                }
                            }
                        }
                    }.dlcCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Movimientos de inventario").font(.headline)
                        if snapshot.movements.isEmpty {
                            Text(vm.detailErrorMessage.isEmpty ? "No hay movimientos registrados." : "No se pudieron cargar los movimientos.")
                                .font(.subheadline).foregroundStyle(DLCTheme.muted)
                        }
                        ForEach(snapshot.movements) { movement in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(remoteMovementLabel(movement.movementType)).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(movement.deltaL) L")
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(movement.deltaL.hasPrefix("-") ? DLCTheme.red : DLCTheme.green)
                                }
                                Text("Capturado: \(movement.quantityEntered) \(movement.unitEntered) · observado: \(movement.observedL) L")
                                    .font(.caption).foregroundStyle(DLCTheme.muted)
                                Text("Saldo: \(movement.beforeQuantityL ?? "—") → \(movement.afterQuantityL ?? "—") L · \(movement.occurredAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(DLCTheme.muted)
                                if let compensated = movement.compensatedL {
                                    Text("Volumen compensado: \(compensated) L · base: \(movement.volumeBasis ?? "no indicada")")
                                        .font(.caption2).foregroundStyle(DLCTheme.muted)
                                }
                                if let temperature = movement.temperatureC {
                                    Text("Temperatura capturada: \(temperature) °C")
                                        .font(.caption2).foregroundStyle(DLCTheme.muted)
                                }
                                if let reason = movement.reason, !reason.isEmpty {
                                    Text(reason).font(.caption).foregroundStyle(DLCTheme.muted)
                                }
                                if let cost = movement.costRecognizedUsd {
                                    Text("Costo reconocido: $\(cost) · \(remoteValuationLabel(movement.valuationQuality))")
                                        .font(.caption2).foregroundStyle(DLCTheme.muted)
                                }
                                if let reference = movement.documentReference, !reference.isEmpty {
                                    Text("Documento: \(reference)").font(.caption2).foregroundStyle(DLCTheme.muted)
                                }
                            }
                            if movement.id != snapshot.movements.last?.id { Divider() }
                        }
                        if snapshot.nextMovementCursor != nil {
                            Button { Task { await vm.loadMoreMovements() } } label: {
                                if vm.isLoadingMore { ProgressView() } else { Text("Cargar más movimientos") }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .disabled(vm.isLoadingMore)
                        }
                    }.dlcCard()
                } else if vm.isLoadingDetail {
                    ProgressView("Cargando inventario…").frame(maxWidth: .infinity).padding(28)
                }
            }.padding(20)
        }
        .navigationTitle("Detalle de tanque")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .task(id: tankID) { await vm.loadTank(tankID) }
    }
}

private func tankDetailRow(_ title: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(title).font(.subheadline).foregroundStyle(DLCTheme.muted)
        Spacer(minLength: 14)
        Text(value).font(.subheadline.weight(.medium)).multilineTextAlignment(.trailing)
    }
}

private func remoteTankStatusLabel(_ status: String) -> String {
    switch status {
    case "active": "Activo"
    case "maintenance": "En mantenimiento"
    case "offline": "Fuera de servicio"
    case "decommissioned": "Dado de baja"
    default: status.capitalized
    }
}

private func remoteTankStatusColor(_ status: String) -> Color {
    switch status {
    case "active": DLCTheme.green
    case "maintenance", "offline": DLCTheme.yellow
    case "decommissioned": DLCTheme.red
    default: DLCTheme.muted
    }
}

private func remoteMovementLabel(_ value: String) -> String {
    switch value {
    case "opening": "Saldo inicial"
    case "receipt": "Recepción"
    case "sale": "Venta"
    case "loss": "Pérdida"
    case "adjustment_in": "Ajuste de entrada"
    case "adjustment_out": "Ajuste de salida"
    default: value.capitalized
    }
}

private func remoteValuationLabel(_ value: String) -> String {
    switch value {
    case "known": "Costo conocido"
    case "provisional": "Costo provisional"
    case "unknown": "Costo aún desconocido"
    default: value.capitalized
    }
}
