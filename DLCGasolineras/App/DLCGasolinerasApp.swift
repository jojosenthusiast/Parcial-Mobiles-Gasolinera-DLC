import SwiftUI
import Charts

@main
struct DLCGasolinerasApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootContentView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
        }
    }
/// Vista raíz de la aplicación.
/// Se mantiene en este archivo para conservar exactamente la estructura solicitada.
private struct RootContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.runtimeMode == .remote {
                if let identity = appState.remoteIdentity {
                    NavigationStack { RemoteSessionHomeView(identity: identity) }
                } else {
                    LoginView()
                }
            } else if let user = appState.currentUser {
                switch user.role {
                case .generalManager:
                    GeneralManagerTabView()
                case .branchManager:
                    if let branch = appState.selectedBranch {
                        BranchManagerTabView(branch: branch)
                    } else {
                        LoginView()
                    }
                }
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.currentUser)
    }
}

private struct RemoteSessionHomeView: View {
    @EnvironmentObject private var appState: AppState
    let identity: RemoteIdentity
    @State private var branchDetail: RemoteBranchDetail?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LogoView()
                Text(identity.roles.contains(where: \.isGeneralManager) ? "Resumen de la red" : "Operación de mi sucursal")
                    .font(.largeTitle.weight(.bold))
                if let client = appState.remoteMetricsClient {
                    if identity.roles.contains(where: \.isGeneralManager),
                       appState.remoteCapabilities?.permissions.contains("branch.read") == true {
                        RemoteNetworkDashboardView(client: client)
                    } else if let branchID = identity.roles.first(where: { $0.branchId != nil })?.branchId,
                              appState.remoteCapabilities?.permissions.contains("inventory.read") == true {
                        RemoteBranchDashboardView(client: client, branchID: branchID)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label(identity.displayName, systemImage: "person.crop.circle.fill").font(.headline)
                    Text(identity.email).font(.subheadline).foregroundStyle(DLCTheme.muted)
                    ForEach(identity.roles.indices, id: \.self) { index in
                        let role = identity.roles[index]
                        HStack {
                            Text(role.name)
                            Spacer()
                            Text(role.branchId == nil ? "Red" : "Sucursal asignada")
                                .foregroundStyle(DLCTheme.muted)
                        }.font(.subheadline)
                    }
                }.dlcCard()
                if let capabilities = appState.remoteCapabilities {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Permisos cargados").font(.headline)
                        Text("\(capabilities.permissions.count) permisos en esta sesión")
                            .font(.subheadline).foregroundStyle(DLCTheme.muted)
                    }.dlcCard(color: DLCTheme.orangeBG)
                }
                if identity.roles.contains(where: \.isGeneralManager) {
                    if appState.remoteCapabilities?.permissions.contains("branch.read") == true,
                       let repository = appState.remoteBranchRepository {
                        let scope = RemoteDataScope(organizationId: identity.organizationId, userId: identity.id, branchId: nil)
                        NavigationLink {
                            RemoteBranchesDirectoryView(
                                repository: repository,
                                pumpRepository: appState.remotePumpRepository,
                                tankRepository: appState.remoteTankRepository,
                                offlineStore: appState.remoteOfflineStore,
                                scope: scope,
                                canManageBranches: appState.remoteCapabilities?.permissions.contains("branch.manage") == true,
                                canActivateBranches: appState.remoteCapabilities?.permissions.contains("branch.activate") == true,
                                canReadInventory: appState.remoteCapabilities?.permissions.contains("infrastructure.read") == true
                                    && appState.remoteCapabilities?.permissions.contains("inventory.read") == true,
                                canReadFuel: appState.remoteCapabilities?.permissions.contains("fuel.read") == true,
                                canReadInfrastructure: appState.remoteCapabilities?.permissions.contains("infrastructure.read") == true,
                                canReadStaff: appState.remoteCapabilities?.permissions.contains("staff.read") == true,
                                canManageStaff: appState.remoteCapabilities?.permissions.contains("staff.manage") == true,
                                canReadPrices: appState.remoteCapabilities?.permissions.contains("price.read") == true,
                                canProposePrices: appState.remoteCapabilities?.permissions.contains("price.propose") == true
                            )
                        } label: {
                            Label("Directorio de sucursales", systemImage: "building.2")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .dlcCard()
                    } else {
                        Label("Tu cuenta no tiene permiso para consultar sucursales.", systemImage: "lock.fill")
                            .font(.footnote).foregroundStyle(DLCTheme.red).dlcCard()
                    }
                } else if let branchID = identity.roles.first(where: { $0.branchId != nil })?.branchId,
                   let repository = appState.remotePumpRepository {
                    if appState.remoteCapabilities?.permissions.contains("cut.read") == true,
                       let cutRepository = appState.remoteCutRepository {
                        NavigationLink {
                            RemoteCutsDirectoryView(
                                repository: cutRepository,
                                pumpRepository: repository,
                                branchID: branchID,
                                branchName: branchDetail?.name ?? "Sucursal asignada",
                                timezoneIdentifier: branchDetail?.timezone ?? "America/El_Salvador",
                                currentUserID: identity.id,
                                canRead: true,
                                canCapture: appState.remoteCapabilities?.permissions.contains("cut.capture") == true,
                                canMeasureMeters: appState.remoteCapabilities?.permissions.contains("inventory.measure") == true,
                                canSubmit: appState.remoteCapabilities?.permissions.contains("cut.submit") == true,
                                canReviewOrClose: appState.remoteCapabilities?.permissions.contains("cut.close") == true
                            )
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "fuelpump.fill")
                                    .font(.title3.weight(.semibold)).foregroundStyle(.white)
                                    .frame(width: 46, height: 46)
                                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Cortes de hoy").font(.headline).foregroundStyle(.white)
                                    Text("Registrar bombas · medir tanques · conciliar")
                                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(.white)
                            }
                            .padding(15)
                            .background(LinearGradient(colors: [DLCTheme.forest, DLCTheme.green], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
                            .overlay(alignment: .trailing) {
                                Circle().fill(DLCTheme.orange.opacity(0.22)).frame(width: 75, height: 75).offset(x: 24).clipped()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                        .shadow(color: DLCTheme.forest.opacity(0.14), radius: 12, y: 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if appState.remoteCapabilities?.permissions.contains("report.read") == true,
                       let client = appState.remoteMetricsClient {
                        NavigationLink {
                            RemoteReportCenterView(client: client, branchID: branchID)
                        } label: { Label("Reportes", systemImage: "chart.bar.doc.horizontal")
                            .frame(maxWidth: .infinity, alignment: .leading) }.dlcCard()
                    }
                    let scope = RemoteDataScope(organizationId: identity.organizationId, userId: identity.id, branchId: branchID)
                    if appState.remoteCapabilities?.permissions.contains("cash.read") == true,
                       let client = appState.remoteMetricsClient {
                        NavigationLink {
                            RemoteCashCenterView(
                                client: client,
                                store: appState.remoteOfflineStore,
                                scope: scope,
                                branchID: branchID,
                                currentUserID: identity.id,
                                canManageRegisters: appState.remoteCapabilities?.permissions.contains("cash.register.manage") == true,
                                canOpen: appState.remoteCapabilities?.permissions.contains("cash.open") == true,
                                canMove: appState.remoteCapabilities?.permissions.contains("cash.move") == true,
                                canClose: appState.remoteCapabilities?.permissions.contains("cash.close") == true,
                                canDecideVariance: appState.remoteCapabilities?.permissions.contains("approval.decide") == true
                                    && appState.remoteCapabilities?.permissions.contains("cash.variance.approve") == true
                            )
                        } label: {
                            Label("Caja y arqueos", systemImage: "dollarsign.circle.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .dlcCard(color: DLCTheme.greenBG)
                    }
                    if appState.remoteCapabilities?.permissions.contains("infrastructure.read") == true {
                    NavigationLink {
                        RemotePumpsOverviewView(
                            repository: repository,
                            offlineStore: appState.remoteOfflineStore,
                            scope: scope,
                            branchID: branchID,
                            canCaptureMeter: appState.remoteCapabilities?.permissions.contains("inventory.measure") == true,
                            canAuthorizeDispense: appState.remoteCapabilities?.permissions.contains("dispense.authorize") == true,
                            canReadSales: appState.remoteCapabilities?.permissions.contains("sale.read") == true,
                            canCreateSales: appState.remoteCapabilities?.permissions.contains("sale.create") == true,
                            prepaymentClient: appState.remoteMetricsClient,
                            canCollectPrepayments: appState.remoteCapabilities?.permissions.contains("payment.collect") == true,
                            canReadCash: appState.remoteCapabilities?.permissions.contains("cash.read") == true,
                            canReadPrepayments: appState.remoteCapabilities?.permissions.contains("payment.read") == true
                        )
                    } label: {
                        Label("Bombas de mi sucursal", systemImage: "fuelpump.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .dlcCard()
                    if appState.remoteCapabilities?.permissions.contains("infrastructure.read") == true,
                       appState.remoteCapabilities?.permissions.contains("inventory.read") == true,
                       let tankRepository = appState.remoteTankRepository {
                        NavigationLink {
                            RemoteTanksDirectoryView(repository: tankRepository, offlineStore: appState.remoteOfflineStore, scope: scope, branchID: branchID)
                        } label: {
                            Label("Tanques e inventario", systemImage: "drop.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .dlcCard()
                    }
                    } else {
                        Label("Tu cuenta no tiene permiso para consultar bombas.", systemImage: "lock.fill")
                            .font(.footnote).foregroundStyle(DLCTheme.red).dlcCard()
                    }
                    if appState.remoteCapabilities?.permissions.contains("inventory.read") == true,
                       appState.remoteCapabilities?.permissions.contains("infrastructure.read") != true {
                        Label("Para consultar tanques también se requiere permiso de infraestructura.", systemImage: "lock.fill")
                            .font(.footnote).foregroundStyle(DLCTheme.muted).dlcCard()
                    }
                    if appState.remoteCapabilities?.permissions.contains("sale.read") == true, let repository = appState.remotePumpRepository {
                        NavigationLink {
                            RemoteFuelTaxPoliciesView(repository: repository, branchID: branchID, currentUserID: identity.id,
                                canPropose: appState.remoteCapabilities?.permissions.contains("tax.policy.propose") == true,
                                canApprove: appState.remoteCapabilities?.permissions.contains("tax.policy.approve") == true)
                        } label: {
                            Label("Políticas fiscales", systemImage: "doc.text")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.dlcCard()
                    }
                    if appState.remoteCapabilities?.permissions.contains("pos.catalog.read") == true {
                        NavigationLink {
                            RemotePOSCatalogView(repository: repository, store: appState.remoteOfflineStore, scope: scope, branchID: branchID,
                                canManage: appState.remoteCapabilities?.permissions.contains("pos.catalog.manage") == true,
                                canReceive: appState.remoteCapabilities?.permissions.contains("pos.stock.receive") == true,
                                canSell: appState.remoteCapabilities?.permissions.contains("sale.create") == true,
                                canReadCost: appState.remoteCapabilities?.permissions.contains("finance.cost.read") == true)
                        } label: {
                            Label("Tienda y servicios", systemImage: "basket.fill").frame(maxWidth: .infinity, alignment: .leading)
                        }.dlcCard()
                    }
                    if appState.remoteCapabilities?.permissions.contains("sale.read") == true,
                       let repository = appState.remotePumpRepository,
                       let client = appState.remoteMetricsClient {
                        NavigationLink {
                            RemoteFuelSalesView(
                                repository: repository,
                                branchID: branchID,
                                client: client,
                                store: appState.remoteOfflineStore,
                                scope: scope,
                                canCreateSales: appState.remoteCapabilities?.permissions.contains("sale.create") == true,
                                canReadPayments: appState.remoteCapabilities?.permissions.contains("payment.read") == true,
                                canCollectPayments: appState.remoteCapabilities?.permissions.contains("payment.collect") == true,
                                canResolvePayments: appState.remoteCapabilities?.permissions.contains("payment.resolve") == true,
                                canReadCash: appState.remoteCapabilities?.permissions.contains("cash.read") == true,
                                canRequestRefund: appState.remoteCapabilities?.permissions.contains("sale.refund.request") == true,
                                canDecideRefund: appState.remoteCapabilities?.permissions.contains("approval.decide") == true
                                    && appState.remoteCapabilities?.permissions.contains("sale.refund.approve") == true,
                                canExecuteRefund: appState.remoteCapabilities?.permissions.contains("payment.refund") == true
                            )
                        } label: {
                            Label("Ventas", systemImage: "receipt")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.dlcCard()
                    }
                    if appState.remoteCapabilities?.permissions.contains("payment.read") == true,
                       let client = appState.remoteMetricsClient {
                        NavigationLink {
                            RemotePrepaymentsView(
                                client: client, store: appState.remoteOfflineStore, scope: scope, branchID: branchID,
                                canRequest: appState.remoteCapabilities?.permissions.contains("sale.refund.request") == true,
                                canDecide: appState.remoteCapabilities?.permissions.contains("approval.decide") == true
                                    && appState.remoteCapabilities?.permissions.contains("sale.refund.approve") == true,
                                canExecute: appState.remoteCapabilities?.permissions.contains("payment.refund") == true,
                                canReadCash: appState.remoteCapabilities?.permissions.contains("cash.read") == true,
                                canAllocate: appState.remoteCapabilities?.permissions.contains("payment.collect") == true
                                    && appState.remoteCapabilities?.permissions.contains("sale.read") == true,
                                canResolve: appState.remoteCapabilities?.permissions.contains("payment.resolve") == true
                            )
                        } label: {
                            Label("Anticipos y devoluciones", systemImage: "arrow.uturn.backward.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.dlcCard(color: DLCTheme.orangeBG)
                    }
                    if appState.remoteCapabilities?.permissions.contains("dispense.read") == true, let repository = appState.remotePumpRepository {
                        NavigationLink {
                            RemoteDispenseQueueView(
                                vm: RemotePumpsViewModel(repository: repository, offlineStore: appState.remoteOfflineStore, scope: scope, branchID: branchID,
                                    canReadSales: appState.remoteCapabilities?.permissions.contains("sale.read") == true,
                                    canCreateSales: appState.remoteCapabilities?.permissions.contains("sale.create") == true),
                                prepaymentClient: appState.remoteMetricsClient, prepaymentStore: appState.remoteOfflineStore,
                                prepaymentScope: scope, prepaymentBranchID: branchID,
                                canCollectPrepayments: appState.remoteCapabilities?.permissions.contains("payment.collect") == true,
                                canReadCash: appState.remoteCapabilities?.permissions.contains("cash.read") == true,
                                canReadPrepayments: appState.remoteCapabilities?.permissions.contains("payment.read") == true
                            )
                        } label: {
                            Label("Despachos pendientes", systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .dlcCard(color: DLCTheme.orangeBG)
                    }
                }
                Button("Cerrar sesión") { Task { await appState.logoutRemote() } }
                    .buttonStyle(PrimaryButtonStyle())
            }.padding(20)
        }
        .dlcScreen()
        .task(id: identity.id) {
            guard let branchID = identity.roles.first(where: { $0.branchId != nil })?.branchId,
                  let repository = appState.remoteBranchRepository else { return }
            branchDetail = try? await repository.branchDetail(branchID: branchID)
        }
    }
}

private struct RemoteBranchDashboardView: View {
    @EnvironmentObject private var appState: AppState
    let client: RemoteAPIClient
    let branchID: UUID
    @State private var dashboard: RemoteBranchDashboard?
    @State private var error: String?
    @State private var selectedAnomaly: RemoteBranchDashboard.Alert?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hoy").font(.title2.bold())
                Spacer()
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Actualizar indicadores")
            }
            if let error { Text(error).foregroundStyle(DLCTheme.red).font(.footnote) }
            if let dashboard {
                Text("\(dashboard.branch.name) · \(dashboard.operationalDate)")
                    .foregroundStyle(DLCTheme.muted)
                ForEach(dashboard.cuts) { cut in
                    let fraction = cut.expectedNozzles > 0 ? Double(cut.registeredNozzles) / Double(cut.expectedNozzles) : 0
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cut.slot.capitalized).font(.headline).foregroundStyle(DLCTheme.forest)
                                Text(remoteCutStatusTitle(cut.status))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(cut.status == "closed" ? DLCTheme.green : cut.reviewRequired == true ? DLCTheme.red : DLCTheme.muted)
                            }
                            Spacer()
                            if cut.reviewRequired == true {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .font(.headline).foregroundStyle(DLCTheme.red)
                                    .padding(9).background(DLCTheme.redBG, in: Circle())
                            } else if cut.status == "closed" {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.headline).foregroundStyle(DLCTheme.green)
                            } else {
                                Text(cut.status == "scheduled" ? "Pendiente" : "En curso")
                                    .font(.caption2.weight(.bold)).foregroundStyle(DLCTheme.orange)
                            }
                        }
                        HStack(spacing: 7) {
                            Label("\(cut.registeredDispensers)/\(cut.expectedDispensers) bombas", systemImage: "fuelpump.fill")
                            Text("·")
                            Label("\(cut.registeredNozzles)/\(cut.expectedNozzles) mangueras", systemImage: "drop.fill")
                        }
                        .font(.caption.weight(.medium)).foregroundStyle(DLCTheme.muted)
                        ProgressView(value: min(max(fraction, 0), 1))
                            .tint(cut.reviewRequired == true ? DLCTheme.yellow : DLCTheme.orange)
                            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: fraction)
                        if cut.status == "closed", let closedAt = cut.closedAt {
                            Text("Cerrado \(closedAt.formatted(date: .omitted, time: .shortened)) · ventas \(cut.closedSalesUsd.map { "$\($0)" } ?? "reservadas por permiso")")
                                .font(.caption2).foregroundStyle(DLCTheme.green)
                        }
                        if cut.reviewRequired == true {
                            Text("Conciliación fuera de tolerancia: requiere aprobación de otro usuario antes del cierre.")
                                .font(.caption).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .dlcCard(color: cut.reviewRequired == true ? DLCTheme.yellowBG : DLCTheme.surface)
                    .scrollTransition(.animated(.spring(duration: 0.38))) { content, phase in
                        content.opacity(phase.isIdentity ? 1 : 0.9).scaleEffect(phase.isIdentity ? 1 : 0.98)
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Inventario de tanques").font(.headline)
                            Text("Saldo registrado · capacidad nominal · litros")
                                .font(.caption).foregroundStyle(DLCTheme.muted)
                        }
                        Spacer()
                        Text(dashboard.inventory.totalLiters.map { "\($0) L" } ?? "Incompleto")
                            .font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(DLCTheme.forest)
                    }
                    ForEach(dashboard.inventory.tanks) { tank in
                        let level = Double(tank.percentage ?? "").flatMap { $0.isFinite ? $0 : nil }
                        let tint: Color = tank.levelColor == "critical" ? DLCTheme.red : tank.levelColor == "warning" ? DLCTheme.yellow : tank.levelColor == "unknown" ? DLCTheme.muted : DLCTheme.green
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tank.fuelName).font(.subheadline.weight(.bold)).foregroundStyle(DLCTheme.forest)
                                    Text("Tanque \(tank.code)\(tank.name.map { " · \($0)" } ?? "")")
                                        .font(.caption2).foregroundStyle(DLCTheme.muted)
                                }
                                Spacer()
                                Text(tank.levelLabel)
                                    .font(.caption2.weight(.bold)).foregroundStyle(tint)
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(tint.opacity(0.12), in: Capsule())
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(tank.onHandLiters.map { "\($0)" } ?? "—")
                                    .font(.title3.monospacedDigit().weight(.bold)).foregroundStyle(DLCTheme.forest)
                                    .contentTransition(.numericText())
                                Text("/ \(tank.capacityLiters) L")
                                    .font(.caption).foregroundStyle(DLCTheme.muted)
                                Spacer()
                                if let percentage = tank.percentage { Text("\(percentage)%").font(.headline.monospacedDigit()).foregroundStyle(tint) }
                            }
                            if let level {
                                ProgressView(value: min(max(level / 100, 0), 1))
                                    .tint(tint)
                                    .animation(.spring(response: 0.6, dampingFraction: 0.76), value: level)
                            } else {
                                Text("No hay línea base para calcular el nivel disponible.")
                                    .font(.caption).foregroundStyle(DLCTheme.red)
                            }
                            HStack {
                                if let usable = tank.usableLiters { Label("Útil sobre reserva: \(usable) L", systemImage: "drop") }
                                Spacer()
                                if let updatedAt = tank.updatedAt { Text(updatedAt.formatted(date: .omitted, time: .shortened)) }
                            }
                            .font(.caption2).foregroundStyle(DLCTheme.muted)
                        }
                        .padding(12)
                        .background(DLCTheme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 15))
                    }
                    if dashboard.inventory.missingBaselines > 0 {
                        Text("\(dashboard.inventory.missingBaselines) tanques sin medición inicial")
                            .foregroundStyle(DLCTheme.red).font(.footnote)
                    }
                }.dlcCard()
                if !dashboard.alerts.isEmpty || dashboard.openMaintenanceOrders > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Atención requerida").font(.headline)
                        ForEach(dashboard.alerts) { alert in
                            if alert.action.kind == "cut-calendar",
                               let cutRepository = appState.remoteCutRepository,
                               let identity = appState.remoteIdentity,
                               appState.remoteCapabilities?.permissions.contains("cut.read") == true {
                                NavigationLink {
                                    RemoteCutsDirectoryView(
                                        repository: cutRepository,
                                        pumpRepository: appState.remotePumpRepository,
                                        branchID: branchID,
                                        branchName: dashboard.branch.name,
                                        timezoneIdentifier: dashboard.branch.timezone,
                                        currentUserID: identity.id,
                                        canRead: true,
                                        canCapture: appState.remoteCapabilities?.permissions.contains("cut.capture") == true,
                                        canMeasureMeters: appState.remoteCapabilities?.permissions.contains("inventory.measure") == true,
                                        canSubmit: appState.remoteCapabilities?.permissions.contains("cut.submit") == true,
                                        canReviewOrClose: appState.remoteCapabilities?.permissions.contains("cut.close") == true
                                    )
                                } label: {
                                    Label("\(alert.severity.uppercased()) · \(alert.title): \(alert.detail)", systemImage: "arrow.up.right")
                                        .font(.subheadline).foregroundStyle(DLCTheme.forest)
                                }
                            } else if alert.action.kind == "tank", let repository = appState.remoteTankRepository,
                               let userID = appState.remoteIdentity?.id,
                               let orgID = appState.remoteIdentity?.organizationId,
                               appState.remoteCapabilities?.permissions.contains("infrastructure.read") == true {
                                NavigationLink {
                                    RemoteTanksDirectoryView(repository: repository, offlineStore: appState.remoteOfflineStore,
                                        scope: RemoteDataScope(organizationId: orgID, userId: userID, branchId: branchID), branchID: branchID)
                                } label: {
                                    Label("\(alert.severity.uppercased()) · \(alert.title): \(alert.detail)", systemImage: "chevron.right")
                                        .font(.subheadline).foregroundStyle(DLCTheme.forest)
                                }
                            } else {
                                if alert.action.kind == "incident",
                                   appState.remoteCapabilities?.permissions.contains("incident.read") == true {
                                    NavigationLink {
                                        RemoteIncidentDashboardDetail(client: client, branchID: branchID, incidentID: alert.action.id)
                                    } label: {
                                        Label("\(alert.title): \(alert.detail)", systemImage: "chevron.right")
                                            .font(.subheadline).foregroundStyle(DLCTheme.forest)
                                    }
                                } else if alert.action.kind == "anomaly",
                                          appState.remoteCapabilities?.permissions.contains("incident.resolve") == true {
                                    Button { selectedAnomaly = alert } label: {
                                        Label("\(alert.title): \(alert.detail)", systemImage: "checkmark.circle")
                                            .font(.subheadline).foregroundStyle(DLCTheme.forest)
                                    }
                                } else {
                                    Text("\(alert.severity.uppercased()) · \(alert.title): \(alert.detail)")
                                        .font(.subheadline)
                                }
                            }
                        }
                        Text("\(dashboard.openMaintenanceOrders) órdenes de mantenimiento pendientes")
                            .font(.subheadline)
                    }.dlcCard(color: DLCTheme.orangeBG)
                }
                Text("Inventario del registro vigente; ventas y avance del corte se actualizan desde el servidor. Último dato: \(dashboard.lastSourceAt?.formatted(date: .abbreviated, time: .shortened) ?? "sin registro")")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            } else if error == nil { ProgressView("Cargando operación") }
        }.task(id: branchID) { await reload() }
            .sheet(item: $selectedAnomaly) { alert in
                RemoteAnomalyReviewSheet(client: client, branchID: branchID, alert: alert) {
                    Task { await reload() }
                }
            }
    }
    private func reload() async {
        do { dashboard = try await client.branchDashboard(branchID: branchID); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private func remoteCutStatusTitle(_ status: String) -> String {
    switch status {
    case "scheduled": "Pendiente de apertura"
    case "open": "Captura en curso"
    case "prepared": "Conciliación preparada"
    case "inReview": "Revisión pendiente"
    case "closed": "Corte cerrado"
    default: status.capitalized
    }
}

private struct RemoteIncidentDashboardDetail: View {
    let client: RemoteAPIClient
    let branchID: UUID
    let incidentID: UUID
    @State private var detail: RemoteIncidentDetail?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let detail {
                    Text(detail.incident.code).font(.title.bold())
                    Text("\(detail.incident.category) · \(detail.incident.severity) · \(detail.incident.status)")
                    Text(detail.incident.description).dlcCard()
                    Text("Historial").font(.headline)
                    ForEach(detail.events) { event in
                        VStack(alignment: .leading) {
                            Text("\(event.toStatus) · \(event.occurredAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.subheadline.bold())
                            Text(event.note).font(.subheadline)
                        }.dlcCard()
                    }
                } else if let error { Text(error).foregroundStyle(DLCTheme.red) }
                else { ProgressView("Cargando incidencia") }
            }.padding(20)
        }.navigationTitle("Incidencia").task {
            do { detail = try await client.incidentDetail(branchID: branchID, incidentID: incidentID) }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct RemoteAnomalyReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let client: RemoteAPIClient
    let branchID: UUID
    let alert: RemoteBranchDashboard.Alert
    let onSuccess: () -> Void
    @State private var note = ""
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section(alert.title) { Text(alert.detail); Text("Estado: \(alert.status)") }
                Section("Nota de revisión") {
                    TextField("Describe la investigación", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let error { Text(error).foregroundStyle(DLCTheme.red) }
                Button("Marcar en investigación") {
                    Task { await decide("investigating") }
                }.disabled(saving || alert.status != "open" || note.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                Button("Descartar con justificación") { Task { await decide("dismissed") } }
                    .disabled(saving || note.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
            }.navigationTitle("Revisar variación")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
    }
    private func decide(_ status: String) async {
        saving = true
        defer { saving = false }
        do {
            try await client.reviewAnomaly(branchID: branchID, alertID: alert.action.id,
                expectedStatus: alert.status, nextStatus: status, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
            onSuccess(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct RemoteNetworkDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let client: RemoteAPIClient
    @State private var days = 7
    @State private var selected: UUID?
    @State private var dashboard: RemoteNetworkDashboard?
    @State private var availableBranches: [RemoteNetworkDashboard.Branch] = []
    @State private var error: String?
    @State private var selectedDateKey: String?

    private var dashboardQueryKey: String { "\(days)-\(selected?.uuidString ?? "network")" }
    private var selectedDay: RemoteNetworkDashboard.Day? {
        let key = selectedDateKey ?? dashboard?.dailySeries.last?.date
        return dashboard?.dailySeries.first(where: { $0.date == key })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Periodo", selection: $days) {
                Text("Hoy").tag(1); Text("7 días").tag(7); Text("30 días").tag(30)
            }.pickerStyle(.segmented)
            if let dashboard {
                Picker("Sucursal", selection: $selected) {
                    Text("Toda la red").tag(Optional<UUID>.none)
                    ForEach(availableBranches) { branch in
                        Text(branch.name).tag(Optional(branch.id))
                    }
                }
                HStack(spacing: 12) {
                    Image(systemName: selected == nil ? "building.2.crop.circle.fill" : "building.2.fill")
                        .font(.title2).foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(selected == nil ? "Red DLC" : availableBranches.first(where: { $0.id == selected })?.name ?? "Sucursal")")
                            .font(.headline).foregroundStyle(.white)
                        Text("\(dashboard.cutCoverage.closed) de \(dashboard.cutCoverage.expected) cortes cerrados · \(dashboard.activeBranchCount) sucursales")
                            .font(.caption).foregroundStyle(.white.opacity(0.78))
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 0)
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [DLCTheme.forest, Color(red: 0.08, green: 0.31, blue: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
                .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.84), value: dashboard.cutCoverage.closed)
                if !dashboard.dailySeries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Ventas consolidadas").font(.headline).foregroundStyle(DLCTheme.forest)
                                Text("Solo cortes cerrados · USD")
                                    .font(.caption).foregroundStyle(DLCTheme.muted)
                            }
                            Spacer()
                            Text("\(dashboard.periodDays) d")
                                .font(.caption.weight(.bold)).foregroundStyle(DLCTheme.orange)
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .background(DLCTheme.orangeBG, in: Capsule())
                        }
                        if let day = selectedDay {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(chartSales(day), format: .currency(code: "USD").precision(.fractionLength(2)))
                                    .font(.title2.weight(.bold)).foregroundStyle(DLCTheme.forest)
                                    .contentTransition(.numericText())
                                Text("\(day.soldLiters) L · \(day.closedCuts) cortes")
                                    .font(.caption.weight(.medium)).foregroundStyle(DLCTheme.muted)
                                Spacer()
                                Text(day.date).font(.caption2.monospacedDigit()).foregroundStyle(DLCTheme.muted)
                            }
                            .padding(.vertical, 3)
                        }
                        Chart {
                            ForEach(dashboard.dailySeries) { day in
                                let value = chartSales(day)
                                AreaMark(x: .value("Fecha", day.date), yStart: .value("Base", 0.0), yEnd: .value("Ventas USD", value))
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(LinearGradient(colors: [DLCTheme.orange.opacity(0.28), DLCTheme.orange.opacity(0.025)], startPoint: .top, endPoint: .bottom))
                                LineMark(x: .value("Fecha", day.date), y: .value("Ventas USD", value))
                                    .interpolationMethod(.catmullRom)
                                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                                    .foregroundStyle(DLCTheme.orange)
                                if selectedDay?.date == day.date {
                                    PointMark(x: .value("Fecha", day.date), y: .value("Ventas USD", value))
                                        .symbolSize(75).foregroundStyle(DLCTheme.forest)
                                }
                            }
                            if let selectedDateKey {
                                RuleMark(x: .value("Fecha seleccionada", selectedDateKey))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                    .foregroundStyle(DLCTheme.muted.opacity(0.55))
                            }
                        }
                        .chartXSelection(value: $selectedDateKey)
                        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: min(7, dashboard.dailySeries.count))) }
                        .chartYScale(domain: 0...max(dashboard.dailySeries.map(chartSales).max() ?? 0, 1))
                        .frame(height: 190)
                        .animation(reduceMotion ? nil : .snappy(duration: 0.45), value: dashboard.dailySeries.map(\.id))
                        Text("Toca o arrastra sobre el gráfico para consultar un día.")
                            .font(.caption2).foregroundStyle(DLCTheme.muted)
                        Text("Los días sin cortes cerrados no aparecen en la serie.")
                            .font(.caption2).foregroundStyle(DLCTheme.muted)
                    }.dlcCard()
                }
                ForEach(dashboard.branches.filter { selected == nil || $0.id == selected }) { branch in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(branch.name).font(.headline)
                        Text(branch.inventoryRisk == "critical" ? "Inventario crítico" :
                             branch.inventoryRisk == "warning" ? "Inventario bajo" :
                             branch.inventoryRisk == "unknown" ? "Inventario incompleto" : "Inventario normal")
                            .font(.subheadline)
                            .foregroundStyle(branch.inventoryRisk == "critical" ? DLCTheme.red : DLCTheme.forest)
                        Text("Cortes cerrados: \(branch.closedCuts) / \(branch.expectedCuts)")
                        ForEach(branch.products, id: \.fuelProductId) { product in
                            HStack {
                                Text(product.fuelName)
                                Spacer()
                                Text("\(product.soldLiters) L · $\(product.salesUsd)")
                            }.font(.subheadline)
                        }
                        if branch.products.isEmpty { Text("Sin cortes cerrados en el periodo").foregroundStyle(DLCTheme.muted) }
                        if branch.tanks.contains(where: { $0.missingBaselines > 0 }) {
                            Text("Inventario sin medición completa").foregroundStyle(DLCTheme.red)
                        }
                    }
                    .dlcCard(color: branch.inventoryRisk == "critical" ? DLCTheme.redBG : DLCTheme.surface)
                    .scrollTransition(.animated(.spring(duration: 0.38))) { content, phase in
                        reduceMotion ? content : content.opacity(phase.isIdentity ? 1 : 0.9).scaleEffect(phase.isIdentity ? 1 : 0.98)
                    }
                    if appState.remoteCapabilities?.permissions.contains("report.read") == true {
                        NavigationLink {
                            RemoteReportCenterView(client: client, branchID: branch.id)
                        } label: {
                            Label("Reportes de \(branch.name)", systemImage: "chart.bar.doc.horizontal")
                                .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        }.dlcCard()
                    }
                }
                Text("Ventas: cortes cerrados · Inventario: saldo vigente · Actualizado: \(dashboard.lastSourceAt?.formatted(date: .abbreviated, time: .shortened) ?? "sin registro")")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            } else if error == nil { ProgressView("Cargando red") }
            if let error { Text(error).foregroundStyle(DLCTheme.red).font(.footnote) }
            Button { Task { await reload() } } label: {
                Label("Actualizar indicadores", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(DLCTheme.forest)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: dashboardQueryKey)
        .task(id: dashboardQueryKey) { await reload() }
    }
    private func reload() async {
        do {
            let result = try await client.networkDashboard(days: days, branchID: selected)
            if selected == nil {
                availableBranches = result.branches
            } else if availableBranches.isEmpty {
                availableBranches = try await client.networkDashboard(days: days).branches
            }
            dashboard = result
            if let selectedDateKey, dashboard?.dailySeries.contains(where: { $0.date == selectedDateKey }) != true {
                self.selectedDateKey = nil
            }
            error = nil
        }
        catch { self.error = error.localizedDescription }
    }

    private func chartSales(_ day: RemoteNetworkDashboard.Day) -> Double {
        guard let value = Double(day.salesUsd), value.isFinite else { return 0 }
        return max(value, 0)
    }
}

private struct RemoteReportCenterView: View {
    @EnvironmentObject private var appState: AppState
    let client: RemoteAPIClient
    let branchID: UUID
    @State private var reportType = "closed_cuts"
    @State private var from = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var page: RemoteReportPage?
    @State private var error: String?
    @State private var loading = false
    @State private var csvURL: URL?
    @State private var xlsxURL: URL?
    @State private var pdfURL: URL?
    @State private var activeExportID: UUID?
    @State private var exportProgress = ""
    @State private var savedFilters: [RemoteSavedReportFilter] = []
    @State private var filterToDelete: RemoteSavedReportFilter?
    @State private var showingDeleteFilter = false
    @State private var filterName = ""
    @State private var dispensers: [RemoteDispenserSummary] = []
    @State private var selectedProduct: UUID?
    @State private var selectedDispenser: UUID?
    @State private var selectedServiceMode: String?
    @State private var selectedGroupBy: String?
    @State private var selectedStatus: String?
    private var products: [RemoteDispenserProduct] {
        let all = dispensers.flatMap(\.products)
        return Array(Dictionary(grouping: all, by: \.id).compactMap { $0.value.first })
            .sorted { $0.name < $1.name }
    }
    private var statuses: [String] {
        switch reportType {
        case "incidents": return ["reported","assessed","in_progress","resolved","closed"]
        case "purchase_orders": return ["draft","pending_approval","approved","ordered","partially_received","received","rejected","cancelled"]
        default: return []
        }
    }
    private var filterProduct: UUID? { ["fuel_sales","tank_movements"].contains(reportType) ? selectedProduct : nil }
    private var filterDispenser: UUID? { reportType == "fuel_sales" ? selectedDispenser : nil }
    private var filterServiceMode: String? { reportType == "fuel_sales" ? selectedServiceMode : nil }
    private var filterGroupBy: String? { reportType == "fuel_sales" ? selectedGroupBy : nil }
    private var filterStatus: String? { statuses.contains(selectedStatus ?? "") ? selectedStatus : nil }
    private let templates = [
        ("closed_cuts", "Cortes cerrados"), ("fuel_sales", "Ventas de combustible"),
        ("tank_movements", "Movimientos de tanque"), ("incidents", "Incidencias"),
        ("purchase_orders", "Órdenes de compra")
    ]
    private var availableTemplates: [(String,String)] {
        let permissions = Set(appState.remoteCapabilities?.permissions ?? [])
        return templates.filter { item in
            let needed: String
            switch item.0 {
            case "closed_cuts": needed = "cut.read"
            case "fuel_sales": needed = "sale.read"
            case "tank_movements": needed = "inventory.read"
            case "incidents": needed = "incident.read"
            default: needed = "purchase.read"
            }
            return permissions.contains(needed) && (item.0 != "closed_cuts" || permissions.contains("sale.read"))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Reportes").font(.largeTitle.bold())
                if availableTemplates.isEmpty {
                    Text("No tienes plantillas de reporte habilitadas para esta sucursal.")
                        .foregroundStyle(DLCTheme.muted)
                }
                Picker("Plantilla", selection: $reportType) {
                    ForEach(availableTemplates.indices, id: \.self) { index in
                        Text(availableTemplates[index].1).tag(availableTemplates[index].0)
                    }
                }
                DatePicker("Desde", selection: $from, displayedComponents: .date)
                DatePicker("Hasta", selection: $to, displayedComponents: .date)
                if ["fuel_sales","tank_movements"].contains(reportType), !products.isEmpty {
                    Picker("Combustible", selection: $selectedProduct) {
                        Text("Todos").tag(Optional<UUID>.none)
                        ForEach(products) { product in Text(product.name).tag(Optional(product.id)) }
                    }
                }
                if reportType == "fuel_sales", !dispensers.isEmpty {
                    Picker("Bomba", selection: $selectedDispenser) {
                        Text("Todas").tag(Optional<UUID>.none)
                        ForEach(dispensers) { dispenser in
                            Text(dispenser.name ?? dispenser.code).tag(Optional(dispenser.id))
                        }
                    }
                }
                if reportType == "fuel_sales" {
                    Picker("Modalidad", selection: $selectedServiceMode) {
                        Text("Todas").tag(Optional<String>.none)
                        Text("Servicio completo").tag(Optional("full_service"))
                        Text("Autoservicio").tag(Optional("self_service"))
                    }
                    Picker("Agrupar por", selection: $selectedGroupBy) {
                        Text("Detalle de ventas").tag(Optional<String>.none)
                        Text("Día").tag(Optional("day"))
                        Text("Combustible").tag(Optional("fuel"))
                        Text("Bomba").tag(Optional("dispenser"))
                        Text("Modalidad").tag(Optional("service_mode"))
                    }
                }
                if !statuses.isEmpty {
                    Picker("Estado", selection: $selectedStatus) {
                        Text("Todos").tag(Optional<String>.none)
                        ForEach(statuses, id: \.self) { status in Text(status).tag(Optional(status)) }
                    }
                }
                if !savedFilters.isEmpty {
                    Text("Mis filtros").font(.headline)
                    ForEach(savedFilters) { saved in
                        HStack {
                            Button("\(saved.name) · \(saved.filters.from) a \(saved.filters.to)") { apply(saved) }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button(role: .destructive) {
                                filterToDelete = saved; showingDeleteFilter = true
                            } label: { Image(systemName: "trash") }
                                .accessibilityLabel("Eliminar filtro \(saved.name)")
                        }.dlcCard()
                    }
                }
                HStack {
                    TextField("Nombre para guardar filtro", text: $filterName)
                    Button("Guardar") { Task { await saveFilter() } }
                        .disabled(availableTemplates.isEmpty || filterName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || from > to)
                }
                Button("Generar reporte") { Task { await generate() } }
                    .buttonStyle(PrimaryButtonStyle()).disabled(availableTemplates.isEmpty || loading || from > to)
                if loading { ProgressView(activeExportID == nil ? "Consultando datos" : exportProgress) }
                if let activeExportID {
                    Button("Cancelar exportación", role: .cancel) { Task { await cancelExport(id: activeExportID) } }
                        .disabled(exportProgress == "Cancelando")
                }
                if let error { Text(error).foregroundStyle(DLCTheme.red).font(.footnote) }
                if let page {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(page.rowCount) registros · \(page.unit) · \(page.currency)").font(.headline)
                        if appState.remoteCapabilities?.permissions.contains("report.export") == true {
                            HStack {
                                if let csvURL { ShareLink(item: csvURL) { Label("CSV", systemImage: "tablecells") } }
                                else { Button("CSV") { Task { await export(runID: page.id, format: "csv") } } }
                                if let xlsxURL { ShareLink(item: xlsxURL) { Label("Excel", systemImage: "tablecells.fill") } }
                                else { Button("Excel") { Task { await export(runID: page.id, format: "xlsx") } } }
                                if let pdfURL { ShareLink(item: pdfURL) { Label("PDF", systemImage: "doc.richtext") } }
                                else { Button("PDF") { Task { await export(runID: page.id, format: "pdf") } } }
                            }.disabled(loading)
                        }
                        Text("Fuente: \(page.sourceWatermark?.formatted(date: .abbreviated, time: .shortened) ?? "sin registros") · Corte: \(page.asOf.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(DLCTheme.muted)
                        if page.rows.isEmpty { Text("Sin resultados para el periodo seleccionado") }
                        ForEach(Array(page.rows.enumerated()), id: \.offset) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(page.columns, id: \.self) { name in
                                    if let value = entry.element[name], !value.isEmpty {
                                        HStack(alignment: .top) {
                                            Text(name).font(.caption).foregroundStyle(DLCTheme.muted)
                                            Spacer()
                                            Text(value).font(.caption).multilineTextAlignment(.trailing)
                                        }
                                    }
                                }
                            }.dlcCard()
                        }
                        if let next = page.nextOffset {
                            Button("Siguiente página") { Task { await load(runID: page.id, offset: next) } }
                        }
                    }
                }
            }.padding(20)
        }.confirmationDialog("¿Eliminar este filtro guardado?", isPresented: $showingDeleteFilter, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { if let filterToDelete { Task { await deleteFilter(filterToDelete) } } }
            Button("Cancelar", role: .cancel) { filterToDelete = nil }
        }.dlcScreen().task {
            if !availableTemplates.contains(where: { $0.0 == reportType }), let first = availableTemplates.first {
                reportType = first.0
            }
            await loadFilters()
            if appState.remoteCapabilities?.permissions.contains("infrastructure.read") == true {
                do {
                    let response = try await client.dispensers(branchId: branchID, query: nil, cursor: nil, limit: 200)
                    dispensers = response.data
                } catch { self.error = error.localizedDescription }
            }
        }
        .onChange(of: reportType) { _, _ in
            selectedProduct = nil; selectedDispenser = nil; selectedServiceMode = nil
            selectedGroupBy = nil; selectedStatus = nil; page = nil
            csvURL = nil; xlsxURL = nil; pdfURL = nil
        }
    }
    private func generate() async {
        loading = true; error = nil; page = nil; csvURL = nil; xlsxURL = nil; pdfURL = nil
        defer { loading = false }
        do {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(identifier: "America/El_Salvador")
            formatter.dateFormat = "yyyy-MM-dd"
            let created = try await client.createReport(branchID: branchID, type: reportType,
                from: formatter.string(from: from), to: formatter.string(from: to),
                productId: filterProduct, dispenserId: filterDispenser, serviceMode: filterServiceMode,
                groupBy: filterGroupBy, status: filterStatus)
            page = try await client.reportPage(branchID: branchID, runID: created.id)
        } catch { self.error = error.localizedDescription }
    }
    private func load(runID: UUID, offset: Int) async {
        loading = true; defer { loading = false }
        do { page = try await client.reportPage(branchID: branchID, runID: runID, offset: offset); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func export(runID: UUID, format: String) async {
        loading = true; defer { loading = false }
        do {
            let url = try await client.reportExport(branchID: branchID, runID: runID, format: format) { id, progress in
                activeExportID = id; exportProgress = progress
            }
            switch format { case "xlsx": xlsxURL = url; case "pdf": pdfURL = url; default: csvURL = url }
            activeExportID = nil; exportProgress = ""; error = nil
        }
        catch {
            if activeExportID != nil { self.error = error.localizedDescription }
            activeExportID = nil; exportProgress = ""
        }
    }
    private func cancelExport(id: UUID) async {
        exportProgress = "Cancelando"
        do { try await client.cancelReportExport(branchID: branchID, exportID: id); activeExportID = nil; error = nil }
        catch { activeExportID = nil; self.error = error.localizedDescription }
    }
    private func reportDate(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "America/El_Salvador")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }
    private func apply(_ saved: RemoteSavedReportFilter) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "America/El_Salvador")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let start = formatter.date(from: saved.filters.from), let end = formatter.date(from: saved.filters.to) else { return }
        reportType = saved.type; from = start; to = end; page = nil; csvURL = nil; xlsxURL = nil; pdfURL = nil
        selectedProduct = saved.filters.productId; selectedDispenser = saved.filters.dispenserId
        selectedServiceMode = saved.filters.serviceMode; selectedGroupBy = saved.filters.groupBy
        selectedStatus = saved.filters.status
    }
    private func loadFilters() async {
        do { savedFilters = try await client.savedReportFilters(branchID: branchID) }
        catch { self.error = error.localizedDescription }
    }
    private func saveFilter() async {
        loading = true; defer { loading = false }
        do {
            try await client.saveReportFilter(branchID: branchID, name: filterName.trimmingCharacters(in: .whitespacesAndNewlines),
                type: reportType, from: reportDate(from), to: reportDate(to), productId: filterProduct,
                dispenserId: filterDispenser, serviceMode: filterServiceMode, groupBy: filterGroupBy,
                status: filterStatus)
            filterName = ""; await loadFilters(); error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func deleteFilter(_ saved: RemoteSavedReportFilter) async {
        loading = true; defer { loading = false; filterToDelete = nil }
        do { try await client.deleteReportFilter(branchID: branchID, filterID: saved.id); await loadFilters(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

#Preview("Inicio de sesión") {
    LoginView()
        .environmentObject(AppState())
        .preferredColorScheme(.light)
}
