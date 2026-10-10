import Combine
import Foundation

@MainActor
final class BranchManagerViewModel: ObservableObject {
    @Published private(set) var branch: Branch
    @Published private(set) var cuts: [DailyCut] = []

    private let repository: MockRepository

    init(branch: Branch) {
        self.repository = .shared
        self.branch = repository.branch(withID: branch.id) ?? branch
        reload()
    }

    func reload() {
        if let updatedBranch = repository.branch(withID: branch.id) { branch = updatedBranch }
        cuts = repository.todayCuts(for: branch.id)
    }

    func history(range: HistoryRange, type: CutType?) -> [DailyCut] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(range.dayCount - 1), to: Calendar.current.startOfDay(for: end)) ?? end
        let result = repository.cuts(for: branch.id, from: start, through: end)
        guard let type else { return result }
        return result.filter { $0.type == type }
    }

    func averageDailyConsumptionLiters(for fuel: FuelType) -> Double? {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: end)) ?? end
        let closedCuts = repository.cuts(for: branch.id, from: start, through: end).filter(\.isClosed)
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: closedCuts) { calendar.startOfDay(for: $0.date) }
        let completeDays = grouped.filter { _, cuts in
            Set(cuts.map(\.type)).isSuperset(of: Set(CutType.allCases))
        }
        guard completeDays.count >= 3 else { return nil }
        let soldGallons = completeDays.values.flatMap { $0 }.reduce(0) { $0 + $1.soldGallons(for: fuel) }
        return soldGallons * .litersPerUSGallon / Double(completeDays.count)
    }

    var completeRecentDaysCount: Int {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: end)) ?? end
        let closedCuts = repository.cuts(for: branch.id, from: start, through: end).filter(\.isClosed)
        let grouped = Dictionary(grouping: closedCuts) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.values.filter { cuts in
            Set(cuts.map(\.type)).isSuperset(of: Set(CutType.allCases))
        }.count
    }

    func autonomyHours(for tank: FuelTank) -> Double? {
        guard let dailyUse = averageDailyConsumptionLiters(for: tank.type), dailyUse > 0 else { return nil }
        return tank.currentLiters / dailyUse * 24
    }

    func latestCut(for type: CutType) -> DailyCut? {
        cuts.first(where: { $0.type == type })
    }

    func salesGallonsToday(for fuel: FuelType) -> Double {
        cuts.filter { $0.isClosed }.reduce(0) { $0 + $1.soldGallons(for: fuel) }
    }

    func salesUSDToday(for fuel: FuelType) -> Double {
        salesGallonsToday(for: fuel) * (branch.pricePerGallonUSD[fuel] ?? 0)
    }

    var storeSalesToday: [StoreSale] {
        repository.sales(from: Date(), through: Date(), branchID: branch.id)
    }

    var storeSalesTodayCents: Int { storeSalesToday.reduce(0) { $0 + $1.totalCents } }

    var storeStockAlerts: [StoreStockAlert] {
        repository.products.filter(\.isActive).compactMap { product in
            let quantity = repository.storeStock(branchID: branch.id, productID: product.id)
            return quantity <= product.minimumStock ? StoreStockAlert(branch: branch, product: product, quantity: quantity) : nil
        }
    }

    var expiredStoreLotCount: Int {
        repository.lots.filter { $0.branchID == branch.id && $0.remainingQuantity > 0 && $0.isExpired() }.count
    }

    var openMaintenanceCount: Int {
        repository.maintenanceOrders.filter { $0.branchID == branch.id && ($0.status == .open || $0.status == .inProgress) }.count
    }

    func autonomyLabel(for tank: FuelTank) -> String {
        guard let hours = autonomyHours(for: tank), hours.isFinite else {
            return "Autonomía no estimada · \(completeRecentDaysCount)/3 días completos"
        }
        if hours >= 48 { return "Autonomía estimada · \(Int((hours / 24).rounded())) días" }
        return "Autonomía estimada · \(Int(hours.rounded())) h"
    }

    var needsAttention: [FuelTank] {
        branch.tanks.filter { tank in
            tank.status == .critical || (autonomyHours(for: tank).map { $0 <= 48 } ?? false)
        }
    }
}

struct RemoteNozzleSnapshot: Codable, Sendable {
    let availability: RemoteNozzleAvailability?
    let meterHistory: RemoteNozzleMeterHistory?
}

struct RemoteDispenserSnapshot: Codable, Sendable {
    let detail: RemoteDispenserDetail
    let nozzles: [UUID: RemoteNozzleSnapshot]
}

@MainActor
final class RemotePumpsViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var dispensers: [RemoteDispenserSummary] = []
    @Published private(set) var selectedDispenser: RemoteDispenserSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isStale = false
    @Published private(set) var hasPartialDetail = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage = ""
    @Published private(set) var authorizations: [RemoteDispenseAuthorization] = []
    @Published private(set) var isLoadingAuthorizations = false
    @Published private(set) var isLoadingMoreAuthorizations = false
    @Published private(set) var authorizationErrorMessage = ""
    @Published private(set) var authorizationsAreStale = false

    let canReadSales: Bool
    let canCreateSales: Bool

    private let repository: RemotePumpRepository
    private let offlineStore: RemoteOfflineStore
    private let scope: RemoteDataScope
    private let branchID: UUID
    private var nextCursor: String?
    private var loadGeneration = 0
    private var detailGeneration = 0
    private var authorizationGeneration = 0
    private var authorizationCursor: String?
    private var authorizationStatus: String? = "active"
    private let pageSize = 50

    init(repository: RemotePumpRepository, offlineStore: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID, canReadSales: Bool = false, canCreateSales: Bool = false) {
        self.canReadSales = canReadSales
        self.canCreateSales = canCreateSales
        self.repository = repository
        self.offlineStore = offlineStore
        self.scope = scope
        self.branchID = branchID
    }

    func fuelSale(for authorizationID: UUID) async throws -> RemoteFuelSale? {
        try await repository.fuelSale(branchId: branchID, authorizationId: authorizationID)
    }
    func createFuelSale(for authorizationID: UUID, commandID: UUID) async throws -> RemoteFuelSale {
        try await repository.createFuelSale(branchId: branchID, authorizationId: authorizationID, commandId: commandID)
    }
    func fuelSales(query: String?, cursor: String?) async throws -> RemotePage<RemoteFuelSaleSummary> {
        try await repository.fuelSales(branchId: branchID, query: query, cursor: cursor)
    }
    func fuelSaleDetail(_ id: UUID) async throws -> RemoteFuelSale {
        try await repository.fuelSaleDetail(branchId: branchID, saleId: id)
    }

    var hasMore: Bool { nextCursor != nil }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = ""
        dispensers = []
        nextCursor = nil
        isStale = false
        lastUpdated = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let page = try await repository.dispensers(branchId: branchID, query: query, cursor: nil, limit: pageSize)
            guard generation == loadGeneration else { return }
            dispensers = page.data
            nextCursor = page.meta.nextCursor
            lastUpdated = Date()
            isStale = false
            try? offlineStore.saveRead(page, resource: cacheResource, scope: scope)
        } catch {
            guard generation == loadGeneration else { return }
            if let cached = offlineStore.loadRead(resource: cacheResource, scope: scope, as: RemotePage<RemoteDispenserSummary>.self, maxAge: 300) {
                dispensers = cached.value.data
                nextCursor = cached.value.meta.nextCursor
                lastUpdated = cached.savedAt
                isStale = true
                errorMessage = "No se pudo actualizar. Se muestran datos guardados."
            } else {
                dispensers = []
                nextCursor = nil
                isStale = false
                lastUpdated = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMore() async {
        guard !isLoadingMore, !isLoading, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = loadGeneration
        do {
            let page = try await repository.dispensers(branchId: branchID, query: query, cursor: cursor, limit: pageSize)
            guard generation == loadGeneration else { return }
            let known = Set(dispensers.map(\.id))
            dispensers.append(contentsOf: page.data.filter { !known.contains($0.id) })
            nextCursor = page.meta.nextCursor
            lastUpdated = Date()
            isStale = false
            try? offlineStore.saveRead(RemotePage(data: dispensers, meta: page.meta), resource: cacheResource, scope: scope)
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    var hasMoreAuthorizations: Bool { authorizationCursor != nil }

    func loadAuthorizations(status: String? = "active") async {
        authorizationGeneration += 1
        let generation = authorizationGeneration
        authorizationStatus = status
        isLoadingAuthorizations = true
        authorizationErrorMessage = ""
        authorizationsAreStale = false
        authorizations = []
        authorizationCursor = nil
        defer { if generation == authorizationGeneration { isLoadingAuthorizations = false } }
        let resource = authorizationCacheResource(status: status)
        do {
            let page = try await repository.dispenseAuthorizations(branchId: branchID, status: status, cursor: nil, limit: pageSize)
            guard generation == authorizationGeneration else { return }
            authorizations = page.data
            authorizationCursor = page.meta.nextCursor
            try? offlineStore.saveRead(page, resource: resource, scope: scope)
        } catch {
            guard generation == authorizationGeneration else { return }
            if let cached = offlineStore.loadRead(resource: resource, scope: scope, as: RemotePage<RemoteDispenseAuthorization>.self, maxAge: 300) {
                authorizations = cached.value.data
                authorizationCursor = cached.value.meta.nextCursor
                authorizationsAreStale = true
                authorizationErrorMessage = "No se pudo actualizar. Se muestran despachos guardados."
            } else {
                authorizationErrorMessage = error.localizedDescription
            }
        }
    }

    func loadMoreAuthorizations() async {
        guard !isLoadingAuthorizations, !isLoadingMoreAuthorizations, let cursor = authorizationCursor else { return }
        isLoadingMoreAuthorizations = true
        defer { isLoadingMoreAuthorizations = false }
        let generation = authorizationGeneration
        do {
            let page = try await repository.dispenseAuthorizations(branchId: branchID, status: authorizationStatus, cursor: cursor, limit: pageSize)
            guard generation == authorizationGeneration else { return }
            let known = Set(authorizations.map(\.id))
            authorizations.append(contentsOf: page.data.filter { !known.contains($0.id) })
            authorizationCursor = page.meta.nextCursor
            try? offlineStore.saveRead(RemotePage(data: authorizations, meta: page.meta), resource: authorizationCacheResource(status: authorizationStatus), scope: scope)
        } catch {
            guard generation == authorizationGeneration else { return }
            authorizationErrorMessage = error.localizedDescription
        }
    }

    private func authorizationCacheResource(status: String?) -> String {
        "dispense-\(status ?? "all")"
    }

    func createAuthorization(nozzleID: UUID, commandID: UUID, amountUsd: String?, volume: String?, volumeUnit: String?) async throws -> RemoteDispenseAuthorization {
        let hasAmount = !(amountUsd?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasVolume = !(volume?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard hasAmount != hasVolume, hasVolume == (volumeUnit != nil) else {
            throw RemoteAPIError.http(status: 400, code: "INVALID_REQUEST", message: "Indica un importe o un volumen con unidad; no ambos.", correlationId: nil)
        }
        let normalizedAmount = amountUsd?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let normalizedVolume = volume?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if let normalizedAmount, hasAmount {
            guard normalizedAmount.range(of: #"^(?=.*[1-9])(?:0|[1-9]\d{0,11})(?:\.\d{1,2})?$"#, options: .regularExpression) != nil else {
                throw RemoteAPIError.http(status: 400, code: "INVALID_AMOUNT", message: "El importe debe ser positivo y tener hasta dos decimales.", correlationId: nil)
            }
        }
        if let normalizedVolume, hasVolume {
            guard normalizedVolume.range(of: #"^(?=.*[1-9])(?:0|[1-9]\d{0,11})(?:\.\d{1,9})?$"#, options: .regularExpression) != nil,
                  ["gallon_us", "liter"].contains(volumeUnit ?? "") else {
                throw RemoteAPIError.http(status: 400, code: "INVALID_VOLUME", message: "El volumen debe ser positivo, tener unidad y hasta nueve decimales.", correlationId: nil)
            }
        }
        let authorization = try await repository.createDispenseAuthorization(
            branchId: branchID, nozzleId: nozzleID, commandId: commandID,
            amountUsd: hasAmount ? normalizedAmount : nil,
            volume: hasVolume ? normalizedVolume : nil,
            volumeUnit: volumeUnit
        )
        return authorization
    }

    func deviceCapabilities() async throws -> RemoteDeviceCapabilities { try await repository.deviceCapabilities() }

    func deviceOperation(_ authorization: RemoteDispenseAuthorization, commandID: UUID, operation: String, expectedVersion: Int, scenario: String?) async throws -> RemoteDeviceResponse {
        try await repository.deviceOperation(branchId: branchID, authorizationId: authorization.id, commandId: commandID, operation: operation, expectedVersion: expectedVersion, scenario: scenario)
    }

    func refreshAuthorization(_ authorizationID: UUID) async throws -> RemoteDispenseAuthorization {
        try await repository.dispenseAuthorization(branchId: branchID, authorizationId: authorizationID)
    }

    func startAuthorization(_ authorization: RemoteDispenseAuthorization, commandID: UUID) async throws -> RemoteDispenseAuthorization {
        try await repository.startDispense(branchId: branchID, authorizationId: authorization.id, commandId: commandID, expectedVersion: authorization.version)
    }

    func reportProgress(_ authorization: RemoteDispenseAuthorization, commandID: UUID, quantity: String, unit: String) async throws -> RemoteDispenseAuthorization {
        let normalized = try validatedDispenseQuantity(quantity, unit: unit)
        return try await repository.reportDispenseProgress(branchId: branchID, authorizationId: authorization.id, commandId: commandID, quantity: normalized, unit: unit, expectedVersion: authorization.version)
    }

    func completeAuthorization(_ authorization: RemoteDispenseAuthorization, commandID: UUID, quantity: String, unit: String, documentReference: String?, expectedVersion: Int? = nil) async throws -> RemoteDispenseAuthorization {
        let normalized = try validatedDispenseQuantity(quantity, unit: unit)
        if let documentReference, documentReference.count > 120 {
            throw RemoteAPIError.http(status: 400, code: "INVALID_REFERENCE", message: "La referencia no puede superar 120 caracteres.", correlationId: nil)
        }
        if authorization.status == "unknown", documentReference?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw RemoteAPIError.http(status: 400, code: "EVIDENCE_REQUIRED", message: "Para conciliar un resultado desconocido se requiere una referencia de comprobación.", correlationId: nil)
        }
        return try await repository.completeDispense(branchId: branchID, authorizationId: authorization.id, commandId: commandID, quantity: normalized, unit: unit, expectedVersion: expectedVersion ?? authorization.version, documentReference: documentReference)
    }

    private func validatedDispenseQuantity(_ quantity: String, unit: String) throws -> String {
        let normalized = quantity.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let pattern = #"^(?=.*[1-9])(?:0|[1-9]\d{0,11})(?:\.\d{1,9})?$"#
        guard normalized.range(of: pattern, options: .regularExpression) != nil,
              ["gallon_us", "liter"].contains(unit) else {
            throw RemoteAPIError.http(status: 400, code: "INVALID_VOLUME", message: "Ingresa una cantidad positiva válida en galones US o litros.", correlationId: nil)
        }
        return normalized
    }

    func cancelAuthorization(_ authorization: RemoteDispenseAuthorization, commandID: UUID, reason: String) async throws -> RemoteDispenseAuthorization {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.count <= 240 else {
            throw RemoteAPIError.http(status: 400, code: "INVALID_REASON", message: "Indica un motivo de hasta 240 caracteres.", correlationId: nil)
        }
        try await repository.cancelDispense(branchId: branchID, authorizationId: authorization.id, commandId: commandID, expectedVersion: authorization.version, reason: reason)
    }

    func markAuthorizationUnknown(_ authorization: RemoteDispenseAuthorization, commandID: UUID, reason: String) async throws -> RemoteDispenseAuthorization {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.count <= 240 else {
            throw RemoteAPIError.http(status: 400, code: "INVALID_REASON", message: "Indica un motivo de hasta 240 caracteres.", correlationId: nil)
        }
        try await repository.markDispenseUnknown(branchId: branchID, authorizationId: authorization.id, commandId: commandID, expectedVersion: authorization.version, reason: reason)
    }

    func reconcileAuthorizationNoFlow(_ authorization: RemoteDispenseAuthorization, commandID: UUID, evidenceReference: String, reason: String) async throws -> RemoteDispenseAuthorization {
        guard !evidenceReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              evidenceReference.count <= 120,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              reason.count <= 240 else {
            throw RemoteAPIError.http(status: 400, code: "INVALID_RECONCILIATION", message: "Indica evidencia (hasta 120 caracteres) y un motivo (hasta 240 caracteres).", correlationId: nil)
        }
        try await repository.reconcileDispenseNoFlow(branchId: branchID, authorizationId: authorization.id, commandId: commandID, expectedVersion: authorization.version, evidenceReference: evidenceReference, reason: reason)
    }

    func recordMeterReading(
        dispenserID: UUID,
        nozzle: RemoteDispenserNozzle,
        value: String,
        meterSerial: String?,
        note: String?,
        commandID: UUID
    ) async throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let pattern = #"^(?:0|[1-9]\d{0,11})(?:\.\d{1,9})?$"#
        guard normalized.range(of: pattern, options: .regularExpression) != nil else {
            throw RemoteAPIError.http(status: 400, code: "INVALID_READING", message: "Ingresa una lectura no negativa con hasta 12 enteros y 9 decimales.", correlationId: nil)
        }
        let serial = meterSerial?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSerial = serial?.isEmpty == true ? nil : serial
        if let cleanSerial, cleanSerial.count > 80 {
            throw RemoteAPIError.http(status: 400, code: "INVALID_SERIAL", message: "La serie del medidor no puede superar 80 caracteres.", correlationId: nil)
        }
        if let note, note.count > 120 {
            throw RemoteAPIError.http(status: 400, code: "INVALID_NOTE", message: "La nota no puede superar 120 caracteres.", correlationId: nil)
        }

        if let expectedVersion = nozzle.meterVersion {
            _ = try await repository.captureMeterReading(
                branchId: branchID, nozzleId: nozzle.id, commandId: commandID,
                value: normalized, meterSerial: cleanSerial ?? nozzle.meterSerial,
                expectedVersion: expectedVersion, source: .manual
            )
        } else {
            _ = try await repository.captureMeterBaseline(
                branchId: branchID, nozzleId: nozzle.id, commandId: commandID,
                value: normalized, meterSerial: cleanSerial, source: .manual, note: note
            )
        }
        await loadDispenser(dispenserID)
    }

    func loadDispenser(_ dispenserID: UUID) async {
        detailGeneration += 1
        let generation = detailGeneration
        isLoadingDetail = true
        errorMessage = ""
        hasPartialDetail = false
        isStale = false
        lastUpdated = nil
        defer { if generation == detailGeneration { isLoadingDetail = false } }
        let resource = "dispenser-\(dispenserID.uuidString.lowercased())"
        do {
            let detail = try await repository.dispenser(branchId: branchID, dispenserId: dispenserID)
            guard generation == detailGeneration else { return }
            var snapshots: [UUID: RemoteNozzleSnapshot] = [:]
            var partial = false
            for nozzle in detail.nozzles {
                do {
                    let availability = try await repository.nozzleAvailability(branchId: branchID, nozzleId: nozzle.id)
                    let history = try await repository.nozzleMeterReadings(branchId: branchID, nozzleId: nozzle.id)
                    snapshots[nozzle.id] = RemoteNozzleSnapshot(availability: availability, meterHistory: history)
                } catch { partial = true }
            }
            guard generation == detailGeneration else { return }
            let snapshot = RemoteDispenserSnapshot(detail: detail, nozzles: snapshots)
            selectedDispenser = snapshot
            lastUpdated = Date()
            isStale = false
            hasPartialDetail = partial
            if partial { errorMessage = "No se pudo actualizar toda la disponibilidad o el historial de lectura." }
            else { try? offlineStore.saveRead(snapshot, resource: resource, scope: scope) }
        } catch {
            guard generation == detailGeneration else { return }
            if let cached = offlineStore.loadRead(resource: resource, scope: scope, as: RemoteDispenserSnapshot.self, maxAge: 300) {
                selectedDispenser = cached.value
                lastUpdated = cached.savedAt
                isStale = true
                hasPartialDetail = false
                errorMessage = "No se pudo actualizar la ficha. Se muestran datos guardados."
            } else {
                selectedDispenser = nil
                isStale = false
                lastUpdated = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private var cacheResource: String {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt64 = 14695981039346656037
        for byte in normalized.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return "dispensers-\(String(hash, radix: 16))"
    }
}

@MainActor
final class RemoteCutsDirectoryViewModel: ObservableObject {
    @Published var selectedDate = Date()
    @Published private(set) var cuts: [RemoteOperationalCut] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isGenerating = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var lastUpdated: Date?

    let canGenerate: Bool
    private let repository: RemoteCutRepository
    private let branchID: UUID
    private let timeZone: TimeZone
    private var requestGeneration = 0

    init(repository: RemoteCutRepository, branchID: UUID, timezoneIdentifier: String, canGenerate: Bool) {
        self.repository = repository
        self.branchID = branchID
        self.timeZone = TimeZone(identifier: timezoneIdentifier) ?? TimeZone(identifier: "America/El_Salvador")!
        self.canGenerate = canGenerate
    }

    var operationalDate: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: selectedDate)
    }

    var isFutureDate: Bool {
        let calendar = Calendar(identifier: .gregorian)
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        return operationalDate > localCalendar.dateComponents([.year, .month, .day], from: Date()).dateKey
    }

    func load() async {
        requestGeneration += 1
        let generation = requestGeneration
        isLoading = true
        errorMessage = ""
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            let result = try await repository.dailyCuts(branchID: branchID, date: operationalDate)
            guard generation == requestGeneration else { return }
            cuts = result.sorted { $0.slot < $1.slot }
            lastUpdated = Date()
        } catch {
            guard generation == requestGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    func generatePair() async {
        guard canGenerate, !isFutureDate, !isGenerating, cuts.isEmpty else { return }
        isGenerating = true
        errorMessage = ""
        defer { isGenerating = false }
        do {
            let generated = try await repository.generateDailyCuts(branchID: branchID, date: operationalDate)
            guard generated.count == 2, Set(generated.map(\.slot)) == Set([1, 2]) else {
                errorMessage = "El servidor no devolvió los dos cortes esperados. Actualiza antes de continuar."
                return
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class RemoteCutWorkflowViewModel: ObservableObject {
    @Published private(set) var cut: RemoteOperationalCut
    @Published private(set) var assets: RemoteCutAssets?
    @Published private(set) var progress: RemoteCutProgress?
    @Published private(set) var reconciliation: RemoteCutReconciliation?
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var statusMessage = ""
    @Published private(set) var lastUpdated: Date?

    let canCapture: Bool
    let canMeasureMeters: Bool
    let canSubmit: Bool
    let canReviewOrClose: Bool
    let currentUserID: UUID

    private let repository: RemoteCutRepository
    private let pumpRepository: RemotePumpRepository?
    private let branchID: UUID
    private var meterCommandIDs: [String: UUID] = [:]

    init(
        cut: RemoteOperationalCut,
        repository: RemoteCutRepository,
        pumpRepository: RemotePumpRepository?,
        branchID: UUID,
        currentUserID: UUID,
        canCapture: Bool,
        canMeasureMeters: Bool,
        canSubmit: Bool,
        canReviewOrClose: Bool
    ) {
        self.cut = cut
        self.repository = repository
        self.pumpRepository = pumpRepository
        self.branchID = branchID
        self.currentUserID = currentUserID
        self.canCapture = canCapture
        self.canMeasureMeters = canMeasureMeters
        self.canSubmit = canSubmit
        self.canReviewOrClose = canReviewOrClose
    }

    var expectedNozzles: [RemoteCutAssets.Nozzle] {
        (assets?.nozzles ?? []).filter { $0.participation == "expected" }
    }

    var capturedNozzles: Int { expectedNozzles.filter { $0.cutReadingId != nil }.count }
    var tankMeasurementCount: Int { (assets?.tanks ?? []).filter { $0.measuredLiters != nil }.count }
    var allEvidenceRecorded: Bool {
        guard assets != nil, !expectedNozzles.isEmpty else { return false }
        return capturedNozzles == expectedNozzles.count && tankMeasurementCount == (assets?.tanks.count ?? 0)
    }

    var canReview: Bool {
        guard canReviewOrClose, cut.status == "inReview",
              let reconciliation, reconciliation.reviewRequired, reconciliation.review == nil else { return false }
        return reconciliation.preparedBy != currentUserID
    }

    var canClose: Bool {
        guard canReviewOrClose, Date() >= cut.endsAt else { return false }
        if cut.status == "prepared" { return reconciliation?.reviewRequired == false }
        if cut.status == "inReview" { return reconciliation?.review != nil }
        return false
    }

    func canLinkLatestReading(_ nozzle: RemoteCutAssets.Nozzle) -> Bool {
        canCapture && cut.status == "open" && nozzle.participation == "expected"
            && nozzle.cutReadingId == nil && nozzle.lastReadingId != nil
            && nozzle.lastReadingType == "regular"
            && nozzle.lastReadingAt.map { $0 >= cut.startsAt && $0 <= cut.endsAt.addingTimeInterval(86_400) } == true
    }

    var waitForWindowToEnd: Bool { Date() < cut.endsAt }

    func load() async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }
        do {
            if let current = try await repository.dailyCuts(branchID: branchID, date: cut.operationalDate).first(where: { $0.id == cut.id }) {
                cut = current
            }
            if cut.status == "scheduled" {
                assets = nil
                progress = nil
                reconciliation = nil
            } else {
                async let assetTask = repository.cutAssets(branchID: branchID, cutID: cut.id)
                async let progressTask = repository.cutProgress(branchID: branchID, cutID: cut.id)
                let (loadedAssets, loadedProgress) = try await (assetTask, progressTask)
                assets = loadedAssets
                progress = loadedProgress
                if ["prepared", "inReview", "closed"].contains(cut.status) {
                    reconciliation = try await repository.cutReconciliation(branchID: branchID, cutID: cut.id)
                } else {
                    reconciliation = nil
                }
            }
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open() async {
        guard canCapture, cut.status == "scheduled", !isWorking else { return }
        await perform {
            _ = try await repository.openCut(branchID: branchID, cutID: cut.id, expectedVersion: cut.version)
            statusMessage = "Corte abierto. La configuración de bombas y tanques quedó registrada para este turno."
            await load()
        }
    }

    func captureMeter(nozzle: RemoteCutAssets.Nozzle, value: String) async {
        guard canCapture, canMeasureMeters, cut.status == "open", let pumpRepository,
              nozzle.participation == "expected", nozzle.cutReadingId == nil else { return }
        guard let normalizedValue = Self.normalizedDecimal(value),
              let finalValue = Decimal(string: normalizedValue, locale: Locale(identifier: "en_US_POSIX")),
              let previousRaw = nozzle.lastMeterValue,
              let previousValue = Decimal(string: previousRaw, locale: Locale(identifier: "en_US_POSIX")),
              finalValue >= previousValue,
              let expectedVersion = nozzle.meterVersion else {
            errorMessage = "Ingresa una lectura final válida y mayor o igual al totalizador anterior. Si falta línea base, regístrala primero desde la ficha de la bomba."
            return
        }
        let commandKey = "\(nozzle.id.uuidString)|\(normalizedValue)"
        let commandID = meterCommandIDs[commandKey] ?? UUID()
        meterCommandIDs[commandKey] = commandID
        await perform {
            let reading = try await pumpRepository.captureMeterReading(
                branchId: branchID,
                nozzleId: nozzle.id,
                commandId: commandID,
                value: normalizedValue,
                meterSerial: nozzle.meterSerial,
                expectedVersion: expectedVersion,
                source: .manual
            )
            let result = try await repository.captureCutMeter(
                branchID: branchID,
                cutID: cut.id,
                nozzleID: nozzle.id,
                readingID: reading.id,
                expectedVersion: cut.version
            )
            meterCommandIDs.removeValue(forKey: commandKey)
            statusMessage = "Lectura de \(nozzle.code) vinculada al corte."
            _ = result
            await load()
        }
    }

    func linkLatestReading(for nozzle: RemoteCutAssets.Nozzle) async {
        guard canLinkLatestReading(nozzle), let readingID = nozzle.lastReadingId else { return }
        await perform {
            _ = try await repository.captureCutMeter(
                branchID: branchID,
                cutID: cut.id,
                nozzleID: nozzle.id,
                readingID: readingID,
                expectedVersion: cut.version
            )
            statusMessage = "La lectura existente de \(nozzle.code) quedó vinculada al corte."
            await load()
        }
    }

    func measureTank(tank: RemoteCutAssets.Tank, measured: String, water: String, temperature: String) async {
        guard canCapture, cut.status == "open" else { return }
        guard let measuredValue = Self.normalizedDecimal(measured),
              let measuredDecimal = Decimal(string: measuredValue, locale: Locale(identifier: "en_US_POSIX")),
              let capacity = Decimal(string: tank.capacityLiters, locale: Locale(identifier: "en_US_POSIX")),
              measuredDecimal > 0, measuredDecimal <= capacity else {
            errorMessage = "El nivel debe ser mayor que cero y no superar la capacidad del tanque."
            return
        }
        let waterValue = water.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Self.normalizedDecimal(water)
        if !water.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let waterValue, let waterDecimal = Decimal(string: waterValue, locale: Locale(identifier: "en_US_POSIX")),
                  waterDecimal >= 0, waterDecimal <= measuredDecimal else {
                errorMessage = "El nivel de agua debe ser cero o mayor y no puede superar el nivel medido."
                return
            }
        }
        let temperatureValue = temperature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Self.normalizedDecimal(temperature)
        if !temperature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && temperatureValue == nil {
            errorMessage = "La temperatura debe ser un número válido en °C."
            return
        }
        await perform {
            _ = try await repository.measureCutTank(
                branchID: branchID,
                cutID: cut.id,
                tankID: tank.id,
                expectedVersion: cut.version,
                measuredLiters: measuredValue,
                waterLiters: waterValue,
                temperatureC: temperatureValue,
                observedAt: Date()
            )
            statusMessage = "Medición de tanque \(tank.code) guardada."
            await load()
        }
    }

    func prepare() async {
        guard canSubmit, cut.status == "open", allEvidenceRecorded else { return }
        await perform {
            let result = try await repository.prepareCut(branchID: branchID, cutID: cut.id, expectedVersion: cut.version)
            statusMessage = result.automaticClosureId == nil
                ? (result.reviewRequired ? "Conciliación preparada; hace falta una revisión independiente." : "Conciliación preparada; el corte puede cerrarse al terminar el turno.")
                : "Conciliación preparada y corte cerrado automáticamente según la política de la sucursal."
            await load()
        }
    }

    func review(reason: String) async {
        guard canReview else {
            errorMessage = reconciliation?.preparedBy == currentUserID
                ? "La revisión debe hacerla otra persona distinta de quien preparó el corte."
                : "Este perfil no puede revisar el corte."
            return
        }
        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanReason.count >= 8, cleanReason.count <= 500 else {
            errorMessage = "Describe la revisión en al menos 8 caracteres."
            return
        }
        await perform {
            _ = try await repository.reviewCut(branchID: branchID, cutID: cut.id, expectedVersion: cut.version, reason: cleanReason)
            statusMessage = "Revisión independiente registrada."
            await load()
        }
    }

    func close() async {
        guard canClose else {
            errorMessage = waitForWindowToEnd
                ? "El corte solo se puede cerrar al terminar su ventana operativa."
                : "Completa primero el corte anterior y la revisión requerida."
            return
        }
        await perform {
            _ = try await repository.closeCut(branchID: branchID, cutID: cut.id, expectedVersion: cut.version)
            statusMessage = "Corte cerrado y conciliación conservada en el historial."
            await load()
        }
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = ""
        statusMessage = ""
        defer { isWorking = false }
        do { try await operation() }
            catch {
                let message = error.localizedDescription
                await load()
                errorMessage = message
            }
    }

    private static func normalizedDecimal(_ input: String) -> String? {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !clean.isEmpty, clean.filter({ $0 == "." }).count <= 1,
              clean.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }),
              Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")) != nil else { return nil }
        return clean
    }
}

private extension DateComponents {
    var dateKey: String {
        guard let year, let month, let day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

enum RemoteTankFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case active = "Activos"
    case maintenance = "Mantenimiento"
    case offline = "Fuera de servicio"
    case decommissioned = "Dados de baja"

    var id: String { rawValue }
    var apiStatus: String? {
        switch self {
        case .all: nil
        case .active: "active"
        case .maintenance: "maintenance"
        case .offline: "offline"
        case .decommissioned: "decommissioned"
        }
    }
}

struct RemoteTankSnapshot: Codable, Sendable {
    var detail: RemoteTankDetail
    var inventory: RemoteTankInventorySnapshot?
    var movements: [RemoteInventoryMovement]
    var nextMovementCursor: String?
}

@MainActor
final class RemoteTanksViewModel: ObservableObject {
    @Published var query = ""
    @Published var filter: RemoteTankFilter = .all
    @Published private(set) var tanks: [RemoteTankSummary] = []
    @Published private(set) var selectedTank: RemoteTankSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var isStale = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage = ""
    @Published private(set) var detailIsStale = false
    @Published private(set) var detailLastUpdated: Date?
    @Published private(set) var detailErrorMessage = ""

    private let repository: RemoteTankRepository
    private let offlineStore: RemoteOfflineStore
    private let scope: RemoteDataScope
    private let branchID: UUID
    private var cursor: String?
    private var loadGeneration = 0
    private var detailGeneration = 0
    private let pageSize = 50

    init(repository: RemoteTankRepository, offlineStore: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID) {
        self.repository = repository
        self.offlineStore = offlineStore
        self.scope = scope
        self.branchID = branchID
    }

    var hasMore: Bool { cursor != nil }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = ""
        tanks = []
        cursor = nil
        isStale = false
        lastUpdated = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let page = try await repository.tanks(branchId: branchID, query: query, status: filter.apiStatus, cursor: nil, limit: pageSize)
            guard generation == loadGeneration else { return }
            tanks = page.data
            cursor = page.meta.nextCursor
            lastUpdated = Date()
            try? offlineStore.saveRead(page, resource: cacheResource, scope: scope)
        } catch {
            guard generation == loadGeneration else { return }
            if let cached = offlineStore.loadRead(resource: cacheResource, scope: scope, as: RemotePage<RemoteTankSummary>.self, maxAge: 300) {
                tanks = cached.value.data
                cursor = cached.value.meta.nextCursor
                lastUpdated = cached.savedAt
                isStale = true
                errorMessage = "No se pudo actualizar la lista. Se muestran datos guardados."
            } else {
                tanks = []
                cursor = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, let cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = loadGeneration
        do {
            let page = try await repository.tanks(branchId: branchID, query: query, status: filter.apiStatus, cursor: cursor, limit: pageSize)
            guard generation == loadGeneration else { return }
            let known = Set(tanks.map(\.id))
            tanks.append(contentsOf: page.data.filter { !known.contains($0.id) })
            self.cursor = page.meta.nextCursor
            lastUpdated = Date()
            try? offlineStore.saveRead(RemotePage(data: tanks, meta: page.meta), resource: cacheResource, scope: scope)
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadTank(_ tankID: UUID) async {
        detailGeneration += 1
        let generation = detailGeneration
        isLoadingDetail = true
        detailErrorMessage = ""
        detailIsStale = false
        detailLastUpdated = nil
        defer { if generation == detailGeneration { isLoadingDetail = false } }
        let resource = "tank-\(tankID.uuidString.lowercased())"
        do {
            let detail = try await repository.tank(branchId: branchID, tankId: tankID)
            guard generation == detailGeneration else { return }
            let inventoryResult = try? await repository.inventoryBalance(branchId: branchID, tankId: tankID)
            let movementResult = try? await repository.inventoryMovements(branchId: branchID, tankId: tankID, cursor: nil, limit: 30)
            guard generation == detailGeneration else { return }
            let snapshot = RemoteTankSnapshot(
                detail: detail,
                inventory: inventoryResult,
                movements: movementResult?.data ?? [],
                nextMovementCursor: movementResult?.meta.nextCursor
            )
            selectedTank = snapshot
            detailLastUpdated = Date()
            var unavailable: [String] = []
            if case nil = inventoryResult { unavailable.append("saldo de inventario") }
            if case nil = movementResult { unavailable.append("movimientos") }
            if !unavailable.isEmpty { detailErrorMessage = "No se pudo cargar: \(unavailable.joined(separator: " y "))." }
            else { try? offlineStore.saveRead(snapshot, resource: resource, scope: scope) }
        } catch {
            guard generation == detailGeneration else { return }
            if let cached = offlineStore.loadRead(resource: resource, scope: scope, as: RemoteTankSnapshot.self, maxAge: 300) {
                selectedTank = cached.value
                detailLastUpdated = cached.savedAt
                detailIsStale = true
                detailErrorMessage = "No se pudo actualizar el tanque. Se muestran datos guardados."
            } else {
                selectedTank = nil
                detailLastUpdated = nil
                detailIsStale = false
                detailErrorMessage = error.localizedDescription
            }
        }
    }

    func loadMoreMovements() async {
        guard !isLoadingMore, let snapshot = selectedTank, let cursor = snapshot.nextMovementCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = detailGeneration
        do {
            let page = try await repository.inventoryMovements(branchId: branchID, tankId: snapshot.detail.id, cursor: cursor, limit: 30)
            guard generation == detailGeneration, var current = selectedTank, current.detail.id == snapshot.detail.id else { return }
            let known = Set(current.movements.map(\.id))
            current.movements.append(contentsOf: page.data.filter { !known.contains($0.id) })
            current.nextMovementCursor = page.meta.nextCursor
            selectedTank = current
            try? offlineStore.saveRead(current, resource: "tank-\(snapshot.detail.id.uuidString.lowercased())", scope: scope)
        } catch { detailErrorMessage = error.localizedDescription }
    }

    private var cacheResource: String {
        let key = "\(filter.apiStatus ?? "all")|\(query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        var hash: UInt64 = 14695981039346656037
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return "tanks-\(String(hash, radix: 16))"
    }
}
