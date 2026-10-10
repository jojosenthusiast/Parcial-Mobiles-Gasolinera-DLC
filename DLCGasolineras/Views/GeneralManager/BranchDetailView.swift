import SwiftUI

struct BranchDetailView: View {
    @ObservedObject var vm: GeneralManagerViewModel
    let branchID: UUID

    private var branch: Branch? { vm.branch(withID: branchID) }
    private var metrics: [FuelMetric] { vm.fuelMetrics(branchID: branchID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeaderView(role: "Detalle de sucursal", location: branch?.code)
                if let branch {
                    Text(branch.name).font(.largeTitle.weight(.bold))
                    Text("\(branch.address) · \(branch.city), \(branch.department)")
                        .font(.subheadline).foregroundStyle(DLCTheme.muted)

                    SalesCard(amount: metrics.reduce(0) { $0 + $1.salesUSD }, title: "VENTAS · \(vm.selectedPeriod.rawValue.uppercased())")

                    VStack(alignment: .leading, spacing: 13) {
                        Text("Consumo por combustible").font(.headline)
                        ForEach(metrics) { metric in
                            HStack {
                                Circle().fill(DLCTheme.fuelColor(metric.fuel)).frame(width: 9, height: 9)
                                Text(metric.fuel.rawValue)
                                Spacer()
                                Text("\(Int(metric.gallons.rounded()).formatted()) gal").foregroundStyle(DLCTheme.muted)
                                Text(metric.salesUSD, format: .currency(code: "USD"))
                                    .fontWeight(.semibold).frame(minWidth: 72, alignment: .trailing)
                            }
                            .font(.subheadline)
                            if metric.fuel != FuelType.allCases.last { Divider() }
                        }
                    }
                    .dlcCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tanques · existencia / capacidad")
                            .font(.headline)
                        ForEach(branch.tanks) { tank in
                            NavigationLink {
                                FuelTankDetailView(tank: tank, branchName: branch.name)
                            } label: {
                                FuelProgressRow(tank: tank)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .dlcCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cortes de hoy").font(.headline)
                        ForEach(vm.todayCuts(for: branch.id)) { cut in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(cut.type.rawValue).font(.subheadline.weight(.semibold))
                                    Text(cut.type.schedule).font(.caption).foregroundStyle(DLCTheme.muted)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(cut.isClosed ? "Cerrado" : "En curso")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(cut.isClosed ? DLCTheme.green : DLCTheme.orange)
                                    Text("\(cut.completedPumpCount) / 6 bombas")
                                        .font(.caption).foregroundStyle(DLCTheme.muted)
                                }
                            }
                            if cut.type != CutType.allCases.last { Divider() }
                        }
                    }
                    .dlcCard()

                    Text("Los precios por galón son de demostración; las cifras reales deben venir de la configuración comercial.")
                        .font(.caption2).foregroundStyle(DLCTheme.muted)
                } else {
                    ContentUnavailableView("Sucursal no disponible", systemImage: "building.2", description: Text("Regresa al listado e intenta de nuevo."))
                }
            }
            .padding(20)
        }
        .dlcScreen()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.reload() }
    }
}
