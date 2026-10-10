import SwiftUI

struct PumpsStatusView: View {
    @ObservedObject var vm: CutFlowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Lecturas de bombas").font(.largeTitle.weight(.bold))
                    Text("Captura los totalizadores iniciales y finales de Súper, Regular y Diésel.")
                        .font(.subheadline).foregroundStyle(DLCTheme.muted)
                }

                VStack(spacing: 10) {
                    ForEach(1...6, id: \.self) { number in
                        NavigationLink(destination: PumpRegistrationView(vm: vm, pumpNumber: number)) {
                            PumpStatusRow(number: number, reading: vm.pumpReading(number: number))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Text("Avance").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(vm.completedPumpCount) / 6 completas")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(vm.completedPumpCount == 6 ? DLCTheme.green : DLCTheme.orange)
                }
                .dlcCard(color: vm.completedPumpCount == 6 ? DLCTheme.greenBG : DLCTheme.orangeBG)

                if vm.cut.isClosed {
                    NavigationLink(destination: CutSummaryView(vm: vm)) {
                        Label("Ver resumen final", systemImage: "doc.text.magnifyingglass").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    NavigationLink(destination: CutSummaryView(vm: vm)) {
                        Label("Revisar ventas y cerrar corte", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!vm.canClose)
                    if !vm.canClose {
                        Text("Completa las seis bombas antes de revisar el cierre.")
                            .font(.caption).foregroundStyle(DLCTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(vm.cut.type.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
    }
}

private struct PumpStatusRow: View {
    let number: Int
    let reading: PumpReading?

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(complete ? DLCTheme.greenBG : DLCTheme.background)
                Text("\(number)").font(.headline).foregroundStyle(complete ? DLCTheme.green : DLCTheme.ink)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text("Bomba \(number)").font(.headline).foregroundStyle(DLCTheme.ink)
                if let reading {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(FuelType.allCases) { fuel in
                            let gallons = reading.soldGallons(for: fuel)
                            HStack(spacing: 4) {
                                Circle().fill(DLCTheme.fuelColor(fuel)).frame(width: 6, height: 6)
                                Text(fuel.rawValue).frame(width: 54, alignment: .leading)
                                Text("\(Int(gallons.rounded()).formatted()) gal vendidas")
                                    .fontWeight(.semibold)
                            }
                            .font(.caption).foregroundStyle(DLCTheme.muted)
                        }
                    }
                } else {
                    Text("Sin lecturas").font(.caption).foregroundStyle(DLCTheme.muted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: complete ? "checkmark.circle.fill" : "chevron.right")
                .foregroundStyle(complete ? DLCTheme.green : DLCTheme.muted)
        }
        .dlcCard()
        .accessibilityElement(children: .combine)
    }

    private var complete: Bool { reading?.isComplete == true }
}
