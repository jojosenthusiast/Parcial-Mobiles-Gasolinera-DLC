import SwiftUI

struct PumpRegistrationView: View {
    @ObservedObject var vm: CutFlowViewModel
    let pumpNumber: Int

    @State private var values: [FuelType: ReadingDraft]
    @State private var error = ""
    @State private var saved = false
    @Environment(\.dismiss) private var dismiss

    init(vm: CutFlowViewModel, pumpNumber: Int) {
        self.vm = vm
        self.pumpNumber = pumpNumber
        var drafts: [FuelType: ReadingDraft] = [:]
        let existing = vm.pumpReading(number: pumpNumber)
        for fuel in FuelType.allCases {
            if let value = existing?.readings.first(where: { $0.type == fuel }) {
                drafts[fuel] = ReadingDraft(initial: Self.format(value.initialGallons), final: Self.format(value.finalGallons))
            } else {
                drafts[fuel] = ReadingDraft()
            }
        }
        _values = State(initialValue: drafts)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bomba \(pumpNumber)").font(.largeTitle.weight(.bold))
                    Text(vm.cut.isClosed
                         ? "Detalle de lecturas del corte cerrado. Solo consulta; los valores no se pueden modificar."
                         : "Lee el totalizador acumulado en galones. La venta se calcula como lectura final menos inicial.")
                        .font(.subheadline).foregroundStyle(DLCTheme.muted)
                }

                ForEach(FuelType.allCases) { fuel in
                    readingCard(for: fuel)
                }

                if !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline).foregroundStyle(DLCTheme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if saved {
                    Label("Lecturas guardadas para esta bomba.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.green)
                }

                if !vm.cut.isClosed {
                    Button(action: save) {
                        Label("Guardar lecturas", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(20)
        }
        .navigationTitle("Lectura de bomba")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
    }

    private func readingCard(for fuel: FuelType) -> AnyView {
        let draft = values[fuel] ?? ReadingDraft()
        if vm.cut.isClosed, let reading = vm.pumpReading(number: pumpNumber)?.readings.first(where: { $0.type == fuel }) {
            return AnyView(VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(DLCTheme.fuelColor(fuel)).frame(width: 10, height: 10)
                    Text(fuel.rawValue).font(.headline)
                }
                HStack(alignment: .top, spacing: 8) {
                    closedValue("Inicial", value: reading.initialGallons)
                    closedValue("Final", value: reading.finalGallons)
                    closedValue("Venta", value: reading.soldGallons, emphasized: true)
                }
            }.dlcCard())
        }
        if vm.cut.isClosed {
            return AnyView(VStack(alignment: .leading, spacing: 8) {
                Label(fuel.rawValue, systemImage: "drop.fill")
                    .font(.headline).foregroundStyle(DLCTheme.fuelColor(fuel))
                Text("No hay lectura registrada para este producto en este corte.")
                    .font(.subheadline).foregroundStyle(DLCTheme.muted)
            }.dlcCard())
        }
        return AnyView(VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(DLCTheme.fuelColor(fuel)).frame(width: 10, height: 10)
                Text(fuel.rawValue).font(.headline)
            }
            HStack(spacing: 11) {
                readingField(title: "Inicial (gal)", text: binding(for: fuel, keyPath: \.initial))
                readingField(title: "Final (gal)", text: binding(for: fuel, keyPath: \.final))
            }
            if let initial = parse(draft.initial), let final = parse(draft.final), final >= initial {
                HStack {
                    Text("Venta calculada")
                    Spacer()
                    Text("\(Int((final - initial).rounded()).formatted()) gal")
                        .fontWeight(.bold).foregroundStyle(DLCTheme.forest)
                }
                .font(.subheadline)
            }
        }
        .dlcCard())
    }

    private func closedValue(_ title: String, value: Double, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(DLCTheme.muted)
            Text(value, format: .number.precision(.fractionLength(2)))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(DLCTheme.forest)
            Text("gal").font(.caption2).foregroundStyle(DLCTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func readingField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.muted)
            TextField("0.00", text: text)
                .keyboardType(.decimalPad)
                .padding(12)
                .background(DLCTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DLCTheme.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(for fuel: FuelType, keyPath: WritableKeyPath<ReadingDraft, String>) -> Binding<String> {
        Binding(
            get: { values[fuel]?[keyPath: keyPath] ?? "" },
            set: { newValue in
                var draft = values[fuel] ?? ReadingDraft()
                draft[keyPath: keyPath] = newValue
                values[fuel] = draft
                saved = false
                error = ""
            }
        )
    }

    private func save() {
        var readings: [FuelType: (initial: Double, final: Double)] = [:]
        for fuel in FuelType.allCases {
            guard let draft = values[fuel], let initial = parse(draft.initial), let final = parse(draft.final),
                  initial >= 0, final >= initial else {
                error = "Completa las seis lecturas con números válidos; la lectura final debe ser igual o mayor que la inicial."
                saved = false
                return
            }
            readings[fuel] = (initial: initial, final: final)
        }
        if let message = vm.registerPump(number: pumpNumber, readings: readings) {
            error = message
            saved = false
        } else {
            error = ""
            saved = true
        }
    }

    private func parse(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private struct ReadingDraft {
    var initial = ""
    var final = ""
}
