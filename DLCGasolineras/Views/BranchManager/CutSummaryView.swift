import SwiftUI

struct CutSummaryView: View {
    @ObservedObject var vm: CutFlowViewModel
    @EnvironmentObject private var appState: AppState
    @State private var confirmClose = false
    @State private var closeError = ""

    private var totalUSD: Double {
        FuelType.allCases.reduce(0) { $0 + vm.salesUSD(for: $1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(vm.cut.isClosed ? "Resumen del corte" : "Revisión antes del cierre")
                        .font(.largeTitle.weight(.bold))
                    Text("\(vm.cut.type.rawValue) · \(vm.cut.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline).foregroundStyle(DLCTheme.muted)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(vm.cut.isClosed ? "VENTA ESTIMADA" : "VENTA ESTIMADA DEL CORTE")
                        .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.82))
                    Text(totalUSD, format: .currency(code: "USD").precision(.fractionLength(2)))
                        .font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                    Text("Calculada con galones vendidos × precio de demostración por combustible.")
                        .font(.caption).foregroundStyle(.white.opacity(0.78))
                }
                .padding(19).frame(maxWidth: .infinity, alignment: .leading)
                .background(DLCTheme.forest).clipShape(RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Ventas por combustible").font(.headline)
                    ForEach(FuelType.allCases) { fuel in
                        HStack(spacing: 9) {
                            Circle().fill(DLCTheme.fuelColor(fuel)).frame(width: 9, height: 9)
                            Text(fuel.rawValue).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("\(vm.salesGallons(for: fuel), specifier: "%.1f") gal")
                                    .font(.subheadline.weight(.bold))
                                Text(vm.salesUSD(for: fuel), format: .currency(code: "USD"))
                                    .font(.caption).foregroundStyle(DLCTheme.muted)
                            }
                        }
                        if fuel != FuelType.allCases.last { Divider() }
                    }
                }
                .dlcCard()

                movementSummary(kind: .receipt, title: "Recepciones", symbol: "arrow.down.left.circle.fill", color: DLCTheme.green)
                movementSummary(kind: .loss, title: "Pérdidas y daños", symbol: "exclamationmark.triangle.fill", color: DLCTheme.red)

                HStack {
                    Label("Bombas registradas", systemImage: "fuelpump.fill")
                    Spacer()
                    Text("\(vm.completedPumpCount) / 6")
                        .fontWeight(.bold).foregroundStyle(vm.completedPumpCount == 6 ? DLCTheme.green : DLCTheme.red)
                }
                .font(.subheadline)
                .dlcCard(color: vm.completedPumpCount == 6 ? DLCTheme.greenBG : DLCTheme.redBG)

                if !closeError.isEmpty {
                    Label(closeError, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline).foregroundStyle(DLCTheme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if vm.cut.isClosed {
                    Label("Corte cerrado y aplicado una sola vez al inventario.", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dlcCard(color: DLCTheme.greenBG)
                } else {
                    Button { confirmClose = true } label: {
                        Label("Confirmar cierre del corte", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!vm.canClose)
                    if !vm.canClose {
                        Text("El cierre se habilita cuando las seis bombas tienen tres lecturas válidas.")
                            .font(.caption).foregroundStyle(DLCTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Resumen")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .confirmationDialog("¿Cerrar este corte?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Cerrar y aplicar al inventario", role: .destructive, action: closeCut)
            Button("Seguir revisando", role: .cancel) { }
        } message: {
            Text("Se consolidarán ventas, recepciones y pérdidas. El inventario se actualizará una sola vez.")
        }
        .onChange(of: vm.cut.isClosed) { _, isClosed in
            if isClosed { appState.selectedBranch = appState.repository.branch(withID: vm.cut.branchID) }
        }
    }

    private func movementSummary(kind: MovementKind, title: String, symbol: String, color: Color) -> some View {
        let movements = vm.cut.movements.filter { $0.kind == kind }
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(title, systemImage: symbol).font(.headline).foregroundStyle(color)
                Spacer()
                Text("\(movements.count)").font(.caption.weight(.bold)).foregroundStyle(DLCTheme.muted)
            }
            if movements.isEmpty {
                Text("Sin movimientos registrados en este corte.")
                    .font(.subheadline).foregroundStyle(DLCTheme.muted)
            } else {
                ForEach(movements) { movement in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(movement.fuel.rawValue).font(.subheadline.weight(.semibold))
                            Text(kind == .receipt
                                 ? "\(movement.supplier) · folio \(movement.documentReference)"
                                 : "\(movement.cause?.rawValue ?? "Sin categoría") · \(movement.explanation)")
                                .font(.caption).foregroundStyle(DLCTheme.muted)
                        }
                        Spacer(minLength: 8)
                        Text("\(Int(movement.quantityLiters.rounded()).formatted()) L")
                            .font(.subheadline.weight(.bold)).foregroundStyle(color)
                    }
                    if movement.id != movements.last?.id { Divider() }
                }
            }
        }
        .dlcCard()
    }

    private func closeCut() {
        closeError = vm.close(branchID: vm.cut.branchID) ?? ""
        if closeError.isEmpty {
            appState.selectedBranch = appState.repository.branch(withID: vm.cut.branchID)
        }
    }
}
