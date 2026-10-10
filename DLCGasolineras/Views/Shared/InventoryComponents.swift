import SwiftUI

struct StatusBadge: View {
    let status: InventoryStatus
    let percentage: Int

    var body: some View {
        Label("\(status.rawValue) · \(percentage)%", systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(background)
            .clipShape(Capsule())
            .accessibilityLabel("Inventario \(status.rawValue), \(percentage) por ciento")
    }

    private var symbol: String {
        switch status {
        case .optimal: "checkmark.circle.fill"
        case .medium: "exclamationmark.circle.fill"
        case .critical: "exclamationmark.triangle.fill"
        }
    }

    private var foreground: Color {
        switch status {
        case .optimal: DLCTheme.green
        case .medium: DLCTheme.yellow
        case .critical: DLCTheme.red
        }
    }

    private var background: Color {
        switch status {
        case .optimal: DLCTheme.greenBG
        case .medium: DLCTheme.yellowBG
        case .critical: DLCTheme.redBG
        }
    }
}

struct FuelProgressRow: View {
    let tank: FuelTank
    var showStatus = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Capsule().fill(DLCTheme.fuelColor(tank.type)).frame(width: 4, height: 27)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tank.type.rawValue).font(.headline)
                        Text("\(Int(tank.currentLiters.rounded()).formatted()) / \(Int(tank.capacityLiters.rounded()).formatted()) L")
                            .font(.caption)
                            .foregroundStyle(DLCTheme.muted)
                    }
                }
                Spacer(minLength: 8)
                if showStatus { StatusBadge(status: tank.status, percentage: tank.percentage) }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(DLCTheme.border.opacity(0.55))
                    Capsule().fill(statusColor).frame(width: proxy.size.width * CGFloat(tank.percentage) / 100)
                }
            }
            .frame(height: 8)
            .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.78), value: tank.percentage)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch tank.status {
        case .optimal: DLCTheme.green
        case .medium: DLCTheme.yellow
        case .critical: DLCTheme.red
        }
    }
}

struct FuelTankDetailView: View {
    let tank: FuelTank
    let branchName: String

    private var remainingCapacity: Double { max(0, tank.capacityLiters - tank.currentLiters) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tank.type.rawValue).font(.largeTitle.weight(.bold))
                    Text("Tanque · \(branchName)").font(.subheadline).foregroundStyle(DLCTheme.muted)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Nivel registrado").font(.headline)
                        Spacer()
                        StatusBadge(status: tank.status, percentage: tank.percentage)
                    }
                    FuelProgressRow(tank: tank, showStatus: false)
                    Divider()
                    tankValue("Existencia actual", value: tank.currentLiters, suffix: "L")
                    tankValue("Capacidad", value: tank.capacityLiters, suffix: "L")
                    tankValue("Espacio disponible", value: remainingCapacity, suffix: "L")
                }
                .dlcCard()
                Text("El porcentaje se calcula con la existencia y capacidad registradas para este tanque.")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            }
            .padding(20)
        }
        .navigationTitle("Detalle del tanque")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
    }

    private func tankValue(_ title: String, value: Double, suffix: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(DLCTheme.muted)
            Spacer()
            Text("\(Int(value.rounded()).formatted()) \(suffix)")
                .font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SalesCard: View {
    let amount: Double
    var title = "VENTAS DE COMBUSTIBLE · ÚLTIMOS 7 DÍAS"

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.85))
            Text(amount, format: .currency(code: "USD").precision(.fractionLength(2)))
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
            Text("Estimación demostrativa basada en galones consolidados y precio por producto.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DLCTheme.forest)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(DLCTheme.orangeFill.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .opacity(isEnabled ? 1 : 0.45)
    }
}
