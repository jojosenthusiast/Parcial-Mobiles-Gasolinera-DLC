import SwiftUI

struct BranchDashboardView: View {
    @ObservedObject var vm: BranchManagerViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeCut: DailyCut? {
        vm.cuts.first(where: { !$0.isClosed })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeaderView(role: "Gerente de Sucursal", location: vm.branch.city)
                Text(vm.branch.name).font(.largeTitle.weight(.bold))
                Text("Operación de hoy · \(Date.now.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline).foregroundStyle(DLCTheme.muted)

                if let activeCut {
                    NavigationLink(destination: CutsView(vm: vm)) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "fuelpump.fill").font(.title2).foregroundStyle(Color.white)
                                    .frame(width: 46, height: 46)
                                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(activeCut.type.rawValue) · \(activeCut.type.schedule)")
                                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.84))
                                    Text("\(activeCut.completedPumpCount) de 6 bombas registradas")
                                        .font(.headline).foregroundStyle(.white)
                                        .contentTransition(.numericText())
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill").font(.title2).foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.31))
                            }
                            ProgressView(value: Double(activeCut.completedPumpCount), total: 6)
                                .tint(Color(red: 0.98, green: 0.72, blue: 0.31))
                                .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.78), value: activeCut.completedPumpCount)
                        }
                        .padding(17)
                        .background(LinearGradient(colors: [DLCTheme.forest, Color(red: 0.08, green: 0.31, blue: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .scrollTransition(.animated(.spring(duration: 0.4))) { content, phase in
                        reduceMotion ? content : content.opacity(phase.isIdentity ? 1 : 0.9).scaleEffect(phase.isIdentity ? 1 : 0.98)
                    }
                }

                if !vm.needsAttention.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Atención de inventario", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundStyle(DLCTheme.red)
                        ForEach(vm.needsAttention) { tank in
                            NavigationLink {
                                FuelTankDetailView(tank: tank, branchName: vm.branch.name)
                            } label: {
                                HStack {
                                    Text("\(tank.type.rawValue): \(tank.percentage)% · \(Int(tank.currentLiters.rounded()).formatted()) L")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .font(.subheadline.weight(.medium)).foregroundStyle(DLCTheme.ink)
                            }
                            .buttonStyle(.plain)
                        }
                        Text("Revisa autonomía y programa reabastecimiento.")
                            .font(.caption).foregroundStyle(DLCTheme.muted)
                    }
                    .dlcCard(color: DLCTheme.redBG)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Tanques").font(.headline)
                        Spacer()
                        Text("Litros actuales / capacidad").font(.caption).foregroundStyle(DLCTheme.muted)
                    }
                    ForEach(vm.branch.tanks) { tank in
                        NavigationLink {
                            FuelTankDetailView(tank: tank, branchName: vm.branch.name)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                FuelProgressRow(tank: tank)
                                Text(vm.autonomyLabel(for: tank))
                                    .font(.caption2).foregroundStyle(DLCTheme.muted)
                                    .padding(.leading, 12)
                            }
                        }
                        .buttonStyle(.plain)
                        .scrollTransition(.animated(.spring(duration: 0.4))) { content, phase in
                            reduceMotion ? content : content.opacity(phase.isIdentity ? 1 : 0.9).scaleEffect(phase.isIdentity ? 1 : 0.98)
                        }
                    }
                    HStack(spacing: 12) {
                        statusKey(.critical)
                        statusKey(.medium)
                        statusKey(.optimal)
                    }
                }
                .dlcCard()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Cortes de hoy").font(.headline)
                        Spacer()
                        NavigationLink("Ver cortes", destination: CutsView(vm: vm))
                            .font(.caption.weight(.semibold))
                    }
                    ForEach(CutType.allCases) { type in
                        let cut = vm.latestCut(for: type)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(type.rawValue).font(.subheadline.weight(.semibold))
                                Text(type.schedule).font(.caption).foregroundStyle(DLCTheme.muted)
                            }
                            Spacer()
                            Text(cut?.isClosed == true ? "Cerrado" : "\(cut?.completedPumpCount ?? 0)/6")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(cut?.isClosed == true ? DLCTheme.green : DLCTheme.orange)
                        }
                        if type != .evening { Divider() }
                    }
                }
                .dlcCard(color: DLCTheme.orangeBG)

                VStack(alignment: .leading, spacing: 11) {
                    Text("Ventas de cortes cerrados hoy").font(.headline)
                    ForEach(FuelType.allCases) { fuel in
                        HStack {
                            Circle().fill(DLCTheme.fuelColor(fuel)).frame(width: 9, height: 9)
                            Text(fuel.rawValue)
                            Spacer()
                            Text("\(Int(vm.salesGallonsToday(for: fuel).rounded()).formatted()) gal")
                                .foregroundStyle(DLCTheme.muted)
                            Text(vm.salesUSDToday(for: fuel), format: .currency(code: "USD"))
                                .fontWeight(.semibold).frame(minWidth: 72, alignment: .trailing)
                        }
                        .font(.subheadline)
                    }
                    Text("Importes calculados con precios de demostración.")
                        .font(.caption2).foregroundStyle(DLCTheme.muted)
                }
                .dlcCard()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Tienda hoy").font(.headline)
                        Spacer()
                        Text((Double(vm.storeSalesTodayCents) / 100).formatted(.currency(code: "USD")))
                            .font(.subheadline.weight(.bold))
                    }
                    Text("\(vm.storeSalesToday.count) tickets completados")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                    if vm.storeStockAlerts.isEmpty && vm.expiredStoreLotCount == 0 {
                        Label("Sin alertas de existencias de tienda.", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium)).foregroundStyle(DLCTheme.green)
                    } else {
                        ForEach(vm.storeStockAlerts.prefix(2)) { alert in
                            Label("\(alert.product.name): \(alert.quantity) disponibles, mínimo \(alert.product.minimumStock)", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(DLCTheme.red)
                        }
                        if vm.expiredStoreLotCount > 0 {
                            Text("\(vm.expiredStoreLotCount) lote(s) vencidos requieren retiro.")
                                .font(.caption).foregroundStyle(DLCTheme.red)
                        }
                    }
                    if let actor = appState.currentUser {
                        NavigationLink(destination: OperationsRootView(actor: actor, branchID: vm.branch.id, section: .store)) {
                            Label("Abrir tienda e inventario", systemImage: "arrow.right.circle.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.orange)
                        }
                    }
                }
                .dlcCard(color: DLCTheme.surface)
            }
            .padding(20)
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: vm.needsAttention.map(\.id))
        }
        .dlcScreen()
        .navigationBarHidden(true)
        .onAppear { vm.reload() }
        .sensoryFeedback(.warning, trigger: vm.needsAttention.count) { oldValue, newValue in
            newValue > oldValue
        }
    }

    private func statusKey(_ status: InventoryStatus) -> some View {
        HStack(spacing: 4) {
            Circle().fill(statusColor(status)).frame(width: 7, height: 7)
            Text(status.rawValue).font(.caption2)
        }
        .foregroundStyle(DLCTheme.muted)
    }

    private func statusColor(_ status: InventoryStatus) -> Color {
        switch status {
        case .critical: DLCTheme.red
        case .medium: DLCTheme.yellow
        case .optimal: DLCTheme.green
        }
    }
}
