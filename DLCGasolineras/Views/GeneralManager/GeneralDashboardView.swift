import SwiftUI

struct GeneralDashboardView: View {
    @ObservedObject var vm: GeneralManagerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeaderView(role: "Gerente General", location: "Red DLC")
                Text("Resumen de la red").font(.largeTitle.weight(.bold))
                Text("Ventas y consumo de Súper, Regular y Diésel.")
                    .font(.subheadline)
                    .foregroundStyle(DLCTheme.muted)

                scopePicker
                periodPicker

                SalesCard(amount: vm.totalSalesUSD, title: "VENTAS CONSOLIDADAS · \(vm.selectedPeriod.rawValue.uppercased())")

                HStack(spacing: 12) {
                    metricTile(title: "Consumo", value: "\(Int(vm.totalConsumptionGallons.rounded()).formatted()) gal", detail: "Suma de los cortes cerrados", symbol: "drop.fill", color: DLCTheme.orange)
                    metricTile(title: "Cortes cerrados", value: "\(vm.closedCutsCount) / \(vm.scheduledCutsCount)", detail: "En el período seleccionado", symbol: "checkmark.circle.fill", color: DLCTheme.green)
                }

                HStack(spacing: 12) {
                    metricTile(title: "Ventas de tienda", value: (Double(vm.storeSalesCents) / 100).formatted(.currency(code: "USD")), detail: "Tickets completados en el período", symbol: "cart.fill", color: DLCTheme.blue)
                    metricTile(title: "Alertas de tienda", value: "\(vm.storeInventoryAlertCount + vm.expiredStoreLotCount)", detail: "\(vm.storeInventoryAlertCount) productos bajos · \(vm.expiredStoreLotCount) lotes vencidos", symbol: "shippingbox.fill", color: vm.storeInventoryAlertCount + vm.expiredStoreLotCount > 0 ? DLCTheme.red : DLCTheme.green)
                }

                VStack(alignment: .leading, spacing: 13) {
                    sectionTitle("Consumo y ventas por combustible", subtitle: "Galones de bomba · venta estimada en USD")
                    ForEach(vm.dashboardMetrics) { metric in
                        HStack(spacing: 10) {
                            Capsule().fill(DLCTheme.fuelColor(metric.fuel)).frame(width: 4, height: 38)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(metric.fuel.rawValue).font(.headline)
                                Text("\(Int(metric.gallons.rounded()).formatted()) gal")
                                    .font(.caption)
                                    .foregroundStyle(DLCTheme.muted)
                            }
                            Spacer()
                            Text(metric.salesUSD, format: .currency(code: "USD"))
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.vertical, 6)
                        if metric.fuel != FuelType.allCases.last { Divider() }
                    }
                }
                .dlcCard()

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Inventario de la red", subtitle: "Litros disponibles frente a capacidad instalada")
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(vm.totalInventoryLiters.rounded()).formatted()) L")
                            .font(.title2.weight(.bold))
                        Spacer()
                        Text("de \(Int(vm.totalCapacityLiters.rounded()).formatted()) L")
                            .font(.caption)
                            .foregroundStyle(DLCTheme.muted)
                    }
                    ProgressView(value: vm.totalCapacityLiters > 0 ? vm.totalInventoryLiters / vm.totalCapacityLiters : 0)
                        .tint(DLCTheme.forest)
                    Text("\(vm.criticalTankCount) tanques en nivel crítico")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(vm.criticalTankCount > 0 ? DLCTheme.red : DLCTheme.green)
                }
                .dlcCard(color: DLCTheme.surface)

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Atención prioritaria", subtitle: "Tanques que requieren revisión o reabastecimiento")
                    if vm.priorityAlerts.isEmpty {
                        Label("No hay tanques críticos en este alcance.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(DLCTheme.green)
                            .font(.subheadline)
                    } else {
                        ForEach(vm.priorityAlerts.prefix(4)) { alert in
                            NavigationLink(destination: BranchDetailView(vm: vm, branchID: alert.branch.id)) {
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(DLCTheme.red)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(alert.branch.name) · \(alert.tank.type.rawValue)")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(DLCTheme.forest)
                                        Text("\(Int(alert.tank.currentLiters.rounded()).formatted()) L · \(alert.tank.percentage)% de capacidad")
                                            .font(.caption)
                                            .foregroundStyle(DLCTheme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(DLCTheme.muted)
                                }
                                .padding(12)
                                .background(DLCTheme.redBG.opacity(0.72))
                                .clipShape(RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .dlcCard()

                Text("Precios por galón y cifras de inventario: valores de demostración.")
                    .font(.caption2)
                    .foregroundStyle(DLCTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)
            }
            .padding(20)
        }
        .dlcScreen()
        .navigationBarHidden(true)
        .onAppear { vm.reload() }
    }

    private var scopePicker: some View {
        Picker("Alcance de sucursales", selection: $vm.selectedBranchID) {
            Text("Toda la red").tag(UUID?.none)
            ForEach(vm.activeBranches) { branch in
                Text(branch.name).tag(Optional(branch.id))
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(DLCTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DLCTheme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Filtrar por toda la red o por una sucursal")
    }

    private var periodPicker: some View {
        Picker("Período", selection: $vm.selectedPeriod) {
            ForEach(MetricsPeriod.allCases) { period in Text(period.rawValue).tag(period) }
        }
        .pickerStyle(.segmented)
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(DLCTheme.muted)
        }
    }

    private func metricTile(title: String, value: String, detail: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.muted)
            Text(value).font(.title3.weight(.bold)).minimumScaleFactor(0.8).lineLimit(1)
            Text(detail).font(.caption2).foregroundStyle(DLCTheme.muted).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .background(DLCTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(DLCTheme.border))
        .clipShape(RoundedRectangle(cornerRadius: 17))
    }
}
