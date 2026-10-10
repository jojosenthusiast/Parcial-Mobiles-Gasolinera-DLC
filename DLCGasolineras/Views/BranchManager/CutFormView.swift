import SwiftUI

struct CutFormView: View {
    @StateObject private var vm: CutFlowViewModel
    @State private var movementKind: MovementKind = .receipt
    @State private var selectedFuel: FuelType = .regular
    @State private var quantity = ""
    @State private var supplier = ""
    @State private var reference = ""
    @State private var lossCause: LossCause = .merma
    @State private var explanation = ""
    @State private var formError = ""
    @State private var addedCount = 0
    @State private var failedCount = 0

    init(cut: DailyCut) {
        _vm = StateObject(wrappedValue: CutFlowViewModel(cut: cut))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if vm.cut.isClosed {
                    NavigationLink(destination: CutSummaryView(vm: vm)) {
                        Label("Ver resumen del corte", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    movementForm
                    movementList
                    NavigationLink(destination: PumpsStatusView(vm: vm)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Lecturas de bombas").font(.headline)
                                Text("\(vm.completedPumpCount) de 6 completas")
                                    .font(.caption).foregroundStyle(.white.opacity(0.84))
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill").font(.title2)
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(20)
        }
        .navigationTitle("\(vm.cut.type.rawValue) · \(vm.cut.type.schedule)")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .sensoryFeedback(.impact, trigger: addedCount)
        .sensoryFeedback(.error, trigger: failedCount)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.cut.isClosed ? "Corte cerrado" : "Registro del corte")
                .font(.largeTitle.weight(.bold))
            Text("\(vm.cut.date.formatted(date: .abbreviated, time: .omitted)) · \(vm.cut.type.schedule)")
                .font(.subheadline).foregroundStyle(DLCTheme.muted)
            Text("Lecturas de totalizador en galones · inventario y movimientos en litros")
                .font(.caption).foregroundStyle(DLCTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var movementForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Movimientos de combustible").font(.headline)
            Picker("Tipo de movimiento", selection: $movementKind) {
                ForEach(MovementKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
            }
            .pickerStyle(.segmented)

            Picker("Combustible", selection: $selectedFuel) {
                ForEach(FuelType.allCases) { fuel in Text(fuel.rawValue).tag(fuel) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Cantidad recibida o perdida (L)", text: $quantity)
                .keyboardType(.decimalPad)
                .textFieldStyle(DLCTextFieldStyle())

            if movementKind == .receipt {
                TextField("Proveedor", text: $supplier).textFieldStyle(DLCTextFieldStyle())
                TextField("Documento o folio", text: $reference).textFieldStyle(DLCTextFieldStyle())
            } else {
                Picker("Causa", selection: $lossCause) {
                    ForEach(LossCause.allCases) { cause in Text(cause.rawValue).tag(cause) }
                }
                .pickerStyle(.menu)
                TextField("Explica la pérdida o daño", text: $explanation, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(DLCTextFieldStyle())
            }

            if quantityIsInvalid {
                Label("La cantidad debe ser un número mayor que 0.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.red)
            }
            if !formError.isEmpty {
                Label(formError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(DLCTheme.red)
            }
            if !missingFields.isEmpty {
                Label("Falta: \(missingFields.joined(separator: ", ")).", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: addMovement) {
                Label(movementKind == .receipt ? "Agregar recepción" : "Agregar pérdida / daño", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!missingFields.isEmpty)
        }
        .dlcCard(color: DLCTheme.surface)
    }

    private var movementList: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Movimientos registrados").font(.headline)
                Spacer()
                Text("\(vm.cut.movements.count)").font(.caption.bold()).foregroundStyle(DLCTheme.muted)
            }
            if vm.cut.movements.isEmpty {
                Text("Aún no hay recepciones ni pérdidas en este corte.")
                    .font(.subheadline).foregroundStyle(DLCTheme.muted)
            } else {
                ForEach(vm.cut.movements) { movement in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: movement.kind == .receipt ? "arrow.down.left.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(movement.kind == .receipt ? DLCTheme.green : DLCTheme.red)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(movement.fuel.rawValue) · \(movement.kind.rawValue)")
                                .font(.subheadline.weight(.semibold))
                            Text(movement.kind == .receipt
                                 ? "\(movement.supplier) · \(movement.documentReference)"
                                 : "\(movement.cause?.rawValue ?? "Sin categoría") · \(movement.explanation)")
                                .font(.caption).foregroundStyle(DLCTheme.muted)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 5) {
                            Text("\(Int(movement.quantityLiters.rounded()).formatted()) L")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(movement.kind == .receipt ? DLCTheme.green : DLCTheme.red)
                            Button(role: .destructive) {
                                formError = vm.removeMovement(id: movement.id) ?? ""
                            } label: {
                                Image(systemName: "trash").font(.caption)
                            }
                            .accessibilityLabel("Eliminar movimiento")
                        }
                    }
                    if movement.id != vm.cut.movements.last?.id { Divider() }
                }
            }
        }
        .dlcCard()
    }

    // MARK: - Real-time validation (the checks in the view model remain the authority)

    private func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var validQuantity: Double? {
        guard let value = parseNumber(quantity), value.isFinite, value > 0 else { return nil }
        return value
    }

    private var quantityIsInvalid: Bool {
        !isBlank(quantity) && validQuantity == nil
    }

    private var missingFields: [String] {
        var items: [String] = []
        if validQuantity == nil { items.append("cantidad en litros") }
        if movementKind == .receipt {
            if isBlank(supplier) { items.append("proveedor") }
            if isBlank(reference) { items.append("documento o folio") }
        } else if isBlank(explanation) {
            items.append("explicación de la pérdida")
        }
        return items
    }

    private func addMovement() {
        guard let liters = parseNumber(quantity) else {
            formError = "Ingresa una cantidad válida en litros."
            failedCount += 1
            return
        }
        if movementKind == .receipt {
            formError = vm.addReceipt(fuel: selectedFuel, liters: liters, supplier: supplier, reference: reference) ?? ""
            if formError.isEmpty { quantity = ""; supplier = ""; reference = "" }
        } else {
            formError = vm.addLoss(fuel: selectedFuel, liters: liters, cause: lossCause, explanation: explanation) ?? ""
            if formError.isEmpty { quantity = ""; explanation = "" }
        }
        if formError.isEmpty { addedCount += 1 } else { failedCount += 1 }
    }

    private func parseNumber(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }
}

private struct DLCTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(13)
            .background(DLCTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(DLCTheme.border, lineWidth: 1))
    }
}
