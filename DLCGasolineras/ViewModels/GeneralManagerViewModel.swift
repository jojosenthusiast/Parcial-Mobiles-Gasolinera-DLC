import Combine
import Foundation

struct BranchTankAlert: Identifiable {
    let branch: Branch
    let tank: FuelTank
    var id: UUID { tank.id }
}

@MainActor
final class GeneralManagerViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedBranchID: UUID?
    @Published var selectedPeriod: MetricsPeriod = .last7Days
    @Published private(set) var branches: [Branch] = []
    @Published private(set) var managers: [AppUser] = []

    private let repository: MockRepository

    init() {
        self.repository = .shared
        reload()
    }

    func reload() {
        branches = repository.branches
        managers = repository.users.filter { $0.role == .branchManager }
    }

    var filteredBranches: [Branch] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return branches }
        return branches.filter { branch in
            [branch.name, branch.code, branch.city, branch.department, branch.address]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var scopeBranches: [Branch] {
        let active = branches.filter(\.isActive)
        guard let selectedBranchID else { return active }
        return active.filter { $0.id == selectedBranchID }
    }

    var activeBranches: [Branch] { branches.filter(\.isActive) }

    func fuelMetrics(period: MetricsPeriod? = nil, branchID: UUID? = nil) -> [FuelMetric] {
        let selectedPeriod = period ?? self.selectedPeriod
        let end = Date()
        let start = selectedPeriod.startDate(relativeTo: end)
        let cuts = repository.allCuts(from: start, through: end, branchID: branchID)
            .filter(\.isClosed)

        return FuelType.allCases.map { fuel in
            let gallons = cuts.reduce(0) { $0 + $1.soldGallons(for: fuel) }
            let sales = cuts.reduce(0.0) { partial, cut in
                let price = repository.branch(withID: cut.branchID)?.pricePerGallonUSD[fuel] ?? 0
                return partial + cut.soldGallons(for: fuel) * price
            }
            return FuelMetric(fuel: fuel, gallons: gallons, salesUSD: sales)
        }
    }

    var dashboardMetrics: [FuelMetric] {
        fuelMetrics(branchID: selectedBranchID)
    }

    var totalSalesUSD: Double { dashboardMetrics.reduce(0) { $0 + $1.salesUSD } }
    var totalConsumptionGallons: Double { dashboardMetrics.reduce(0) { $0 + $1.gallons } }

    var totalInventoryLiters: Double { scopeBranches.reduce(0) { $0 + $1.totalInventoryLiters } }
    var totalCapacityLiters: Double { scopeBranches.reduce(0) { $0 + $1.totalCapacityLiters } }

    var criticalTankCount: Int {
        scopeBranches.flatMap(\.tanks).filter { $0.status == .critical }.count
    }

    var closedCutsCount: Int {
        let start = selectedPeriod.startDate()
        return repository.allCuts(from: start, through: Date(), branchID: selectedBranchID).filter(\.isClosed).count
    }

    var scheduledCutsCount: Int {
        let numberOfDays = selectedPeriod == .today ? 1 : (selectedPeriod == .last7Days ? 7 : 30)
        return scopeBranches.count * numberOfDays * CutType.allCases.count
    }

    var storeSalesCents: Int {
        repository.sales(from: selectedPeriod.startDate(), through: Date(), branchID: selectedBranchID)
            .reduce(0) { $0 + $1.totalCents }
    }

    var storeInventoryAlertCount: Int {
        scopeBranches.reduce(0) { count, branch in
            count + repository.products.filter(\.isActive).filter { product in
                repository.storeStock(branchID: branch.id, productID: product.id) <= product.minimumStock
            }.count
        }
    }

    var expiredStoreLotCount: Int {
        repository.lots.filter { lot in
            scopeBranches.contains(where: { $0.id == lot.branchID }) && lot.remainingQuantity > 0 && lot.isExpired()
        }.count
    }

    var activeStaffCount: Int {
        repository.staff.filter { member in
            member.status == .active && scopeBranches.contains(where: { $0.id == member.branchID })
        }.count
    }

    var priorityAlerts: [BranchTankAlert] {
        scopeBranches.flatMap { branch in
            branch.tanks.filter { $0.status == .critical }.map { BranchTankAlert(branch: branch, tank: $0) }
        }
    }

    func branch(withID id: UUID) -> Branch? {
        repository.branch(withID: id)
    }

    func todayCuts(for branchID: UUID) -> [DailyCut] {
        repository.todayCuts(for: branchID)
    }

    func createBranch(
        name: String, code: String, city: String, department: String,
        address: String, capacities: [FuelType: Double]
    ) -> String? {
        let error = repository.addBranch(
            name: name, code: code, city: city, department: department,
            address: address, capacities: capacities
        )
        reload()
        return error
    }

    func createManager(name: String, username: String, password: String, branchID: UUID) -> String? {
        let error = repository.addManager(name: name, username: username, password: password, branchID: branchID)
        reload()
        return error
    }

    func assignManager(_ managerID: UUID, to branchID: UUID?) -> String? {
        let error = repository.assignManager(managerID, to: branchID)
        reload()
        return error
    }

    func updateBranch(id: UUID, name: String, code: String, city: String, department: String, address: String, capacities: [FuelType: Double]) -> String? {
        let error = repository.updateBranch(id: id, name: name, code: code, city: city, department: department, address: address, capacities: capacities)
        reload()
        return error
    }

    func setBranchActive(_ branchID: UUID, active: Bool) -> String? {
        let error = repository.setBranchActive(branchID, active: active)
        reload()
        return error
    }

    func updateManager(id: UUID, name: String, email: String, branchID: UUID?) -> String? {
        let error = repository.updateManager(id: id, name: name, email: email, branchID: branchID)
        reload()
        return error
    }

    func setManagerActive(_ managerID: UUID, active: Bool) -> String? {
        let error = repository.setUserActive(managerID, active: active)
        reload()
        return error
    }

    func resetManagerPassword(_ managerID: UUID, password: String, confirmation: String) -> String? {
        repository.resetUserPassword(id: managerID, password: password, confirmation: confirmation)
    }
}

enum RemoteBranchFilter: String, CaseIterable, Identifiable {
    case all = "Todas"
    case active = "Activas"
    case configured = "Configuradas"
    case draft = "Borrador"
    case suspended = "Suspendidas"
    case archived = "Archivadas"

    var id: String { rawValue }
    var apiStatus: String? {
        switch self {
        case .all: nil
        case .active: "active"
        case .configured: "configured"
        case .draft: "draft"
        case .suspended: "suspended"
        case .archived: "archived"
        }
    }
}

@MainActor
final class RemoteBranchesViewModel: ObservableObject {
    @Published var query = ""
    @Published var filter: RemoteBranchFilter = .all
    @Published private(set) var branches: [RemoteBranchSummary] = []
    @Published private(set) var selectedBranch: RemoteBranchDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var isStale = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage = ""
    @Published private(set) var isDetailStale = false
    @Published private(set) var detailLastUpdated: Date?
    @Published private(set) var detailErrorMessage = ""

    private let repository: RemoteBranchRepository
    private let offlineStore: RemoteOfflineStore
    private let scope: RemoteDataScope
    private var cursor: String?
    private var loadGeneration = 0
    private var detailGeneration = 0
    private let pageSize = 50

    init(repository: RemoteBranchRepository, offlineStore: RemoteOfflineStore, scope: RemoteDataScope) {
        self.repository = repository
        self.offlineStore = offlineStore
        self.scope = scope
    }

    var hasMore: Bool { cursor != nil }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = ""
        branches = []
        cursor = nil
        isStale = false
        lastUpdated = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let page = try await repository.branches(query: query, status: filter.apiStatus, cursor: nil, limit: pageSize)
            guard generation == loadGeneration else { return }
            branches = page.data
            cursor = page.meta.nextCursor
            lastUpdated = Date()
            isStale = false
            try? offlineStore.saveRead(page, resource: cacheResource, scope: scope)
        } catch {
            guard generation == loadGeneration else { return }
            if let cached = offlineStore.loadRead(resource: cacheResource, scope: scope, as: RemotePage<RemoteBranchSummary>.self, maxAge: 300) {
                branches = cached.value.data
                cursor = cached.value.meta.nextCursor
                lastUpdated = cached.savedAt
                isStale = true
                errorMessage = "No se pudo actualizar la lista. Se muestran datos guardados."
            } else {
                branches = []
                cursor = nil
                isStale = false
                lastUpdated = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMore() async {
        guard !isLoadingMore, !isLoading, let cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = loadGeneration
        do {
            let page = try await repository.branches(query: query, status: filter.apiStatus, cursor: cursor, limit: pageSize)
            guard generation == loadGeneration else { return }
            let knownIDs = Set(branches.map(\.id))
            branches.append(contentsOf: page.data.filter { !knownIDs.contains($0.id) })
            self.cursor = page.meta.nextCursor
            lastUpdated = Date()
            isStale = false
            try? offlineStore.saveRead(RemotePage(data: branches, meta: page.meta), resource: cacheResource, scope: scope)
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadBranch(_ branchID: UUID) async {
        detailGeneration += 1
        let generation = detailGeneration
        isLoadingDetail = true
        detailErrorMessage = ""
        detailLastUpdated = nil
        isDetailStale = false
        defer { if generation == detailGeneration { isLoadingDetail = false } }
        let resource = "branch-\(branchID.uuidString.lowercased())"
        do {
            let detail = try await repository.branchDetail(branchID: branchID)
            guard generation == detailGeneration else { return }
            selectedBranch = detail
            detailLastUpdated = Date()
            try? offlineStore.saveRead(detail, resource: resource, scope: scope)
        } catch {
            guard generation == detailGeneration else { return }
            if let cached = offlineStore.loadRead(resource: resource, scope: scope, as: RemoteBranchDetail.self, maxAge: 300) {
                selectedBranch = cached.value
                detailLastUpdated = cached.savedAt
                isDetailStale = true
                detailErrorMessage = "No se pudo actualizar la ficha. Se muestran datos guardados."
            } else {
                selectedBranch = nil
                detailLastUpdated = nil
                isDetailStale = false
                detailErrorMessage = error.localizedDescription
            }
        }
    }

    private var cacheResource: String {
        let key = "\(filter.apiStatus ?? "all")|\(query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        var hash: UInt64 = 14695981039346656037
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return "branches-\(String(hash, radix: 16))"
    }
}
