import SwiftUI

struct NewBranchView: View {
    @ObservedObject var vm: GeneralManagerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var code = ""
    @State private var city = ""
    @State private var department = "Santa Ana"
    @State private var address = ""
    @State private var superCapacity = "12000"
    @State private var regularCapacity = "12000"
    @State private var dieselCapacity = "10000"
    @State private var errorMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HeaderView(role: "Administración", location: "Nueva estación")
                Text("Registrar sucursal").font(.largeTitle.weight(.bold))
                Text("Identidad, ubicación y capacidad para iniciar la operación.")
                    .font(.subheadline).foregroundStyle(DLCTheme.muted)

                formField("Nombre de sucursal", placeholder: "Ej. DLC Santa Ana", text: $name)
                formField("Código único", placeholder: "Ej. SA-01", text: $code)
                formField("Ciudad o municipio", placeholder: "Ej. Santa Ana", text: $city)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Departamento").font(.subheadline.weight(.semibold))
                    Picker("Departamento", selection: $department) {
                        ForEach(["Ahuachapán", "Cabañas", "Chalatenango", "Cuscatlán", "La Libertad", "La Paz", "La Unión", "Morazán", "San Miguel", "San Salvador", "San Vicente", "Santa Ana", "Sonsonate", "Usulután"], id: \.self) { item in
                            Text(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(DLCTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(DLCTheme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                formField("Dirección", placeholder: "Calle, número y referencia", text: $address)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Capacidad de tanques").font(.headline)
                    Text("En litros. El inventario empieza en cero; se carga con una recepción.")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                    capacityField(.regular, text: $regularCapacity)
                    capacityField(.superFuel, text: $superCapacity)
                    capacityField(.diesel, text: $dieselCapacity)
                }
                .dlcCard()

                if !errorMessage.isEmpty {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline).foregroundStyle(DLCTheme.red)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DLCTheme.redBG).clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button("Guardar sucursal") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 3)
            }
            .padding(20)
        }
        .dlcScreen()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
                .padding(14)
                .background(DLCTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DLCTheme.border))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func capacityField(_ fuel: FuelType, text: Binding<String>) -> some View {
        HStack(spacing: 9) {
            Capsule().fill(DLCTheme.fuelColor(fuel)).frame(width: 4, height: 34)
            Text(fuel.rawValue).font(.subheadline.weight(.semibold))
            Spacer()
            TextField("Litros", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
            Text("L").foregroundStyle(DLCTheme.muted)
        }
        .padding(11)
        .background(DLCTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DLCTheme.border))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func parse(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private func save() {
        guard let regular = parse(regularCapacity), let premium = parse(superCapacity), let diesel = parse(dieselCapacity) else {
            errorMessage = "Revisa las capacidades: deben ser números válidos en litros."
            return
        }
        errorMessage = vm.createBranch(
            name: name, code: code, city: city, department: department,
            address: address,
            capacities: [.regular: regular, .superFuel: premium, .diesel: diesel]
        ) ?? ""
        if errorMessage.isEmpty { dismiss() }
    }
}
