import Foundation

enum FuelType: String, CaseIterable, Identifiable, Codable, Hashable {
    case superFuel = "Súper"
    case regular = "Regular"
    case diesel = "Diésel"

    var id: String { rawValue }
}

enum UserRole: String, Codable, Hashable {
    case generalManager
    case branchManager
}

struct AppUser: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var username: String
    var role: UserRole
    var branchID: UUID?
    var email: String = ""
    var isActive: Bool = true

    var roleLabel: String {
        role == .generalManager ? "Gerente General" : "Gerente de Sucursal"
    }
}

enum InventoryStatus: String, Codable {
    case optimal = "Óptimo"
    case medium = "Medio"
    case critical = "Crítico"
}

struct FuelTank: Identifiable, Hashable, Codable {
    let id: UUID
    var type: FuelType
    var currentLiters: Double
    var capacityLiters: Double

    var percentage: Int {
        guard capacityLiters > 0 else { return 0 }
        let ratio = min(max(currentLiters / capacityLiters, 0), 1)
        return Int((ratio * 100).rounded())
    }

    var status: InventoryStatus {
        if percentage <= 30 { return .critical }
        if percentage <= 60 { return .medium }
        return .optimal
    }
}

struct Branch: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var code: String
    var city: String
    var department: String
    var address: String
    var tanks: [FuelTank]
    /// Valores de demostración por galón. Una integración real debe cargar precios vigentes.
    var pricePerGallonUSD: [FuelType: Double]
    var isActive: Bool = true

    var totalInventoryLiters: Double { tanks.reduce(0) { $0 + $1.currentLiters } }
    var totalCapacityLiters: Double { tanks.reduce(0) { $0 + $1.capacityLiters } }
}

struct FuelReading: Identifiable, Hashable, Codable {
    let id: UUID
    var type: FuelType
    /// Las lecturas del totalizador de bomba y las ventas derivadas se expresan en galones.
    var initialGallons: Double
    var finalGallons: Double

    var soldGallons: Double { max(finalGallons - initialGallons, 0) }
    var isValid: Bool {
        initialGallons.isFinite && finalGallons.isFinite
            && initialGallons >= 0 && finalGallons >= initialGallons
    }
}

struct PumpReading: Identifiable, Hashable, Codable {
    let id: UUID
    var pumpNumber: Int
    var readings: [FuelReading]

    var isComplete: Bool {
        guard (1...6).contains(pumpNumber), readings.count == FuelType.allCases.count else { return false }
        guard Set(readings.map(\.type)).count == FuelType.allCases.count else { return false }
        return readings.allSatisfy(\.isValid)
    }

    func soldGallons(for fuel: FuelType) -> Double {
        readings.first(where: { $0.type == fuel })?.soldGallons ?? 0
    }
}

enum CutType: String, CaseIterable, Identifiable, Codable {
    case morning = "Matutino"
    case evening = "Vespertino"

    var id: String { rawValue }
    var schedule: String { self == .morning ? "06:00–14:00" : "14:00–22:00" }
}

enum MovementKind: String, CaseIterable, Identifiable, Codable {
    case receipt = "Compra / recepción"
    case loss = "Pérdida / daño"

    var id: String { rawValue }
}

enum LossCause: String, CaseIterable, Identifiable, Codable {
    case merma = "Merma"
    case leak = "Fuga"
    case technicalFailure = "Falla técnica"
    case spill = "Derrame"

    var id: String { rawValue }
}

struct FuelMovement: Identifiable, Hashable, Codable {
    let id: UUID
    var kind: MovementKind
    var fuel: FuelType
    /// Recepciones y pérdidas se expresan en litros para cuadrar contra el inventario del tanque.
    var quantityLiters: Double
    var cause: LossCause?
    var explanation: String
    var supplier: String
    var documentReference: String
    var recordedAt: Date
}

struct DailyCut: Identifiable, Hashable, Codable {
    let id: UUID
    var branchID: UUID
    var type: CutType
    var date: Date
    var movements: [FuelMovement]
    var pumpReadings: [PumpReading]
    var isClosed: Bool
    /// Evita volver a aplicar al tanque movimientos de un corte ya consolidado.
    var inventoryApplied: Bool

    var completedPumpCount: Int {
        Set(pumpReadings.filter(\.isComplete).map(\.pumpNumber)).count
    }

    var canClose: Bool {
        guard !isClosed, pumpReadings.count == 6 else { return false }
        let numbers = Set(pumpReadings.map(\.pumpNumber))
        return numbers == Set(1...6) && pumpReadings.allSatisfy(\.isComplete)
    }

    func soldGallons(for fuel: FuelType) -> Double {
        pumpReadings.reduce(0) { $0 + $1.soldGallons(for: fuel) }
    }

    var totalSoldGallons: Double {
        FuelType.allCases.reduce(0) { $0 + soldGallons(for: $1) }
    }

    func movementLiters(kind: MovementKind, fuel: FuelType) -> Double {
        movements.filter { $0.kind == kind && $0.fuel == fuel }.reduce(0) { $0 + $1.quantityLiters }
    }
}

enum MetricsPeriod: String, CaseIterable, Identifiable {
    case today = "Hoy"
    case last7Days = "Últimos 7 días"
    case last30Days = "Últimos 30 días"

    var id: String { rawValue }

    func startDate(relativeTo date: Date = Date(), calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        switch self {
        case .today: return day
        case .last7Days: return calendar.date(byAdding: .day, value: -6, to: day) ?? day
        case .last30Days: return calendar.date(byAdding: .day, value: -29, to: day) ?? day
        }
    }
}

struct FuelMetric: Identifiable {
    let fuel: FuelType
    let gallons: Double
    let salesUSD: Double

    var id: FuelType { fuel }
}

// MARK: - Tienda, inventario, personal y mantenimiento

enum StoreCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case beverages = "Bebidas"
    case snacks = "Alimentos y snacks"
    case automotive = "Automotriz"
    case lubricants = "Lubricantes"
    case convenience = "Conveniencia"
    case other = "Otros"

    var id: String { rawValue }
}

struct StoreProduct: Identifiable, Hashable, Codable {
    let id: UUID
    var sku: String
    var barcode: String
    var name: String
    var brand: String
    var category: StoreCategory
    var unitName: String
    var unitCostCents: Int
    var unitPriceCents: Int
    var minimumStock: Int
    var isActive: Bool

    var marginCents: Int { unitPriceCents - unitCostCents }
}

enum SupplierScope: String, CaseIterable, Identifiable, Codable, Hashable {
    case fuel = "Combustible"
    case store = "Tienda"
    case both = "Combustible y tienda"

    var id: String { rawValue }
}

struct StoreSupplier: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var taxIdentifier: String
    var contactName: String
    var phone: String
    var email: String
    var address: String
    var scope: SupplierScope
    var isActive: Bool

    var supportsStore: Bool { scope == .store || scope == .both }
    var supportsFuel: Bool { scope == .fuel || scope == .both }
}

struct StoreLot: Identifiable, Hashable, Codable {
    let id: UUID
    var branchID: UUID
    var productID: UUID
    var supplierID: UUID
    var lotCode: String
    var documentReference: String
    var receivedAt: Date
    var expiresAt: Date?
    var receivedQuantity: Int
    var remainingQuantity: Int
    var unitCostCents: Int

    func isExpired(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let expiresAt else { return false }
        return calendar.startOfDay(for: expiresAt) < calendar.startOfDay(for: date)
    }

    func expiresWithin(days: Int, from date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let expiresAt, !isExpired(on: date, calendar: calendar),
              let limit = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) else { return false }
        return calendar.startOfDay(for: expiresAt) <= limit
    }
}

enum StockMovementKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case receipt = "Recepción"
    case sale = "Venta"
    case returnToStock = "Devolución"
    case adjustment = "Ajuste"
    case damaged = "Daño"
    case expired = "Vencimiento"

    var id: String { rawValue }
}

struct StockMovement: Identifiable, Hashable, Codable {
    let id: UUID
    var branchID: UUID
    var productID: UUID
    var lotID: UUID?
    var kind: StockMovementKind
    /// Cantidad firmada: positiva para entradas y negativa para salidas.
    var quantityDelta: Int
    var unitCostCents: Int
    var reference: String
    var reason: String
    var actorID: UUID
    var recordedAt: Date
}

struct SaleLineLotAllocation: Hashable, Codable {
    var lotID: UUID
    var quantity: Int
}

struct StoreSaleLine: Identifiable, Hashable, Codable {
    let id: UUID
    var productID: UUID
    var productName: String
    var quantity: Int
    var unitPriceCents: Int
    var unitCostCents: Int
    var lotAllocations: [SaleLineLotAllocation]

    var lineTotalCents: Int { quantity * unitPriceCents }
}

enum PaymentMethod: String, CaseIterable, Identifiable, Codable, Hashable {
    case cash = "Efectivo"
    case card = "Tarjeta"
    case transfer = "Transferencia"

    var id: String { rawValue }
}

enum SaleStatus: String, Codable, Hashable {
    case completed = "Completada"
    case voided = "Anulada"
}

struct StoreSale: Identifiable, Hashable, Codable {
    let id: UUID
    var folio: String
    var branchID: UUID
    var cashierID: UUID
    var lines: [StoreSaleLine]
    var paymentMethod: PaymentMethod
    var tenderedCents: Int
    var changeCents: Int
    var status: SaleStatus
    var soldAt: Date
    var voidReason: String

    var totalCents: Int { lines.reduce(0) { $0 + $1.lineTotalCents } }
    var itemCount: Int { lines.reduce(0) { $0 + $1.quantity } }
}

enum StaffStatus: String, CaseIterable, Identifiable, Codable, Hashable {
    case active = "Activo"
    case leave = "Permiso"
    case inactive = "Inactivo"

    var id: String { rawValue }
}

struct StaffMember: Identifiable, Hashable, Codable {
    let id: UUID
    var employeeCode: String
    var branchID: UUID
    var fullName: String
    var position: String
    var phone: String
    var email: String
    var hiredAt: Date
    var status: StaffStatus
}

enum WorkShift: String, CaseIterable, Identifiable, Codable, Hashable {
    case morning = "Mañana"
    case afternoon = "Tarde"
    case night = "Noche"

    var id: String { rawValue }
    var timeRange: String {
        switch self {
        case .morning: "06:00–14:00"
        case .afternoon: "14:00–22:00"
        case .night: "22:00–06:00"
        }
    }
}

struct ShiftAssignment: Identifiable, Hashable, Codable {
    let id: UUID
    var branchID: UUID
    var employeeID: UUID
    /// Calendar weekday: 1 = domingo, 7 = sábado.
    var weekday: Int
    var shift: WorkShift
}

enum EquipmentCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case pump = "Bomba"
    case tank = "Tanque"
    case refrigeration = "Refrigeración"
    case pointOfSale = "Punto de venta"
    case safety = "Seguridad"
    case other = "Otro"

    var id: String { rawValue }
}

enum EquipmentStatus: String, CaseIterable, Identifiable, Codable, Hashable {
    case operational = "Operativo"
    case maintenance = "En mantenimiento"
    case outOfService = "Fuera de servicio"

    var id: String { rawValue }
}

struct StationEquipment: Identifiable, Hashable, Codable {
    let id: UUID
    var branchID: UUID
    var assetCode: String
    var name: String
    var category: EquipmentCategory
    var serialNumber: String
    var status: EquipmentStatus
    var installedAt: Date?
}

enum MaintenancePriority: String, CaseIterable, Identifiable, Codable, Hashable {
    case low = "Baja"
    case normal = "Normal"
    case high = "Alta"
    case urgent = "Urgente"

    var id: String { rawValue }
}

enum MaintenanceStatus: String, CaseIterable, Identifiable, Codable, Hashable {
    case open = "Abierta"
    case inProgress = "En proceso"
    case completed = "Completada"
    case cancelled = "Cancelada"

    var id: String { rawValue }
}

struct MaintenanceOrder: Identifiable, Hashable, Codable {
    let id: UUID
    var branchID: UUID
    var equipmentID: UUID
    var title: String
    var description: String
    var priority: MaintenancePriority
    var status: MaintenanceStatus
    var openedAt: Date
    var completedAt: Date?
    var providerName: String
    var costCents: Int
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case last7Days = "7 días"
    case last30Days = "30 días"

    var id: String { rawValue }
    var dayCount: Int { self == .last7Days ? 7 : 30 }
}

extension Double {
    static let litersPerUSGallon = 3.78541
}
