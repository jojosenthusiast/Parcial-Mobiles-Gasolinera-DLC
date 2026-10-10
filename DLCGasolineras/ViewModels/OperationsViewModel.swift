import Combine
import Foundation

struct StoreStockAlert: Identifiable {
    let branch: Branch
    let product: StoreProduct
    let quantity: Int
    var id: String { "\(branch.id.uuidString)-\(product.id.uuidString)" }
}

@MainActor
final class OperationsViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedBranchID: UUID?
    @Published var selectedCategory: StoreCategory?
    @Published var showInactiveProducts = false
    @Published private(set) var lastError = ""

    let actor: AppUser
    let fixedBranchID: UUID?
    let repository: MockRepository
    private var cancellables = Set<AnyCancellable>()

    init(actor: AppUser, branchID: UUID? = nil) {
        self.actor = actor
        self.fixedBranchID = branchID
        self.selectedBranchID = branchID
        self.repository = .shared
        repository.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var activeBranches: [Branch] {
        repository.branches.filter(\.isActive).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var scopedBranches: [Branch] {
        if let fixedBranchID { return activeBranches.filter { $0.id == fixedBranchID } }
        if let selectedBranchID { return activeBranches.filter { $0.id == selectedBranchID } }
        return activeBranches
    }

    var localBranch: Branch? {
        guard let id = fixedBranchID ?? selectedBranchID else { return nil }
        return repository.branch(withID: id)
    }

    var filteredProducts: [StoreProduct] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return repository.products.filter { product in
            guard showInactiveProducts || product.isActive else { return false }
            if let selectedCategory, product.category != selectedCategory { return false }
            guard !query.isEmpty else { return true }
            return [product.name, product.sku, product.barcode, product.brand]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var filteredSuppliers: [StoreSupplier] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return repository.suppliers.filter { supplier in
            supplier.supportsStore && (query.isEmpty || [supplier.name, supplier.contactName, supplier.phone, supplier.email]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var filteredStaff: [StaffMember] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return repository.staff.filter { member in
            scopedBranches.contains(where: { $0.id == member.branchID })
                && (query.isEmpty || [member.employeeCode, member.fullName, member.position, member.phone, member.email]
                    .contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    var filteredEquipment: [StationEquipment] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return repository.equipment.filter { asset in
            scopedBranches.contains(where: { $0.id == asset.branchID })
                && (query.isEmpty || [asset.assetCode, asset.name, asset.serialNumber, asset.category.rawValue]
                    .contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { $0.assetCode.localizedCaseInsensitiveCompare($1.assetCode) == .orderedAscending }
    }

    var filteredMaintenanceOrders: [MaintenanceOrder] {
        repository.maintenanceOrders.filter { order in
            scopedBranches.contains(where: { $0.id == order.branchID })
                && (searchText.isEmpty || order.title.localizedCaseInsensitiveContains(searchText)
                    || order.description.localizedCaseInsensitiveContains(searchText))
        }.sorted { $0.openedAt > $1.openedAt }
    }

    var stockAlerts: [StoreStockAlert] {
        scopedBranches.flatMap { branch in
            repository.products.filter(\.isActive).compactMap { product in
                let stock = repository.storeStock(branchID: branch.id, productID: product.id)
                return stock <= product.minimumStock ? StoreStockAlert(branch: branch, product: product, quantity: stock) : nil
            }
        }.sorted { $0.quantity < $1.quantity }
    }

    var expiredLots: [StoreLot] {
        repository.lots.filter { lot in
            scopedBranches.contains(where: { $0.id == lot.branchID }) && lot.remainingQuantity > 0 && lot.isExpired()
        }.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }

    var expiringSoonLots: [StoreLot] {
        repository.lots.filter { lot in
            scopedBranches.contains(where: { $0.id == lot.branchID }) && lot.remainingQuantity > 0 && lot.expiresWithin(days: 30)
        }.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }

    var openMaintenanceCount: Int {
        filteredMaintenanceOrders.filter { $0.status == .open || $0.status == .inProgress }.count
    }

    var activeStaffCount: Int { filteredStaff.filter { $0.status == .active }.count }

    func stock(for product: StoreProduct, branchID: UUID) -> Int {
        repository.storeStock(branchID: branchID, productID: product.id)
    }

    func lotCount(branchID: UUID, productID: UUID) -> Int {
        repository.storeLots(branchID: branchID, productID: productID).filter { $0.remainingQuantity > 0 }.count
    }

    func sales(
        from start: Date,
        through end: Date,
        branchID: UUID? = nil,
        includeVoided: Bool = false
    ) -> [StoreSale] {
        repository.sales(
            from: start,
            through: end,
            branchID: branchID ?? selectedBranchID ?? fixedBranchID,
            includeVoided: includeVoided
        )
    }

    func salesTotalCents(from start: Date, through end: Date, branchID: UUID? = nil) -> Int {
        sales(from: start, through: end, branchID: branchID).reduce(0) { $0 + $1.totalCents }
    }

    func createProduct(sku: String, barcode: String, name: String, brand: String, category: StoreCategory, unitName: String, costCents: Int, priceCents: Int, minimumStock: Int) -> String? {
        finish(repository.createStoreProduct(
            actorID: actor.id, sku: sku, barcode: barcode, name: name, brand: brand,
            category: category, unitName: unitName, unitCostCents: costCents,
            unitPriceCents: priceCents, minimumStock: minimumStock
        ))
    }

    func saveProduct(_ product: StoreProduct) -> String? {
        finish(repository.updateStoreProduct(product, actorID: actor.id))
    }

    func createSupplier(name: String, taxID: String, contact: String, phone: String, email: String, address: String, scope: SupplierScope) -> String? {
        finish(repository.createSupplier(actorID: actor.id, name: name, taxIdentifier: taxID, contactName: contact, phone: phone, email: email, address: address, scope: scope))
    }

    func saveSupplier(_ supplier: StoreSupplier) -> String? {
        finish(repository.updateSupplier(supplier, actorID: actor.id))
    }

    func receiveLot(branchID: UUID, productID: UUID, supplierID: UUID, lotCode: String, reference: String, quantity: Int, costCents: Int, receivedAt: Date, expiresAt: Date?) -> String? {
        finish(repository.receiveStoreLot(
            actorID: actor.id, branchID: branchID, productID: productID, supplierID: supplierID,
            lotCode: lotCode, reference: reference, quantity: quantity, unitCostCents: costCents,
            receivedAt: receivedAt, expiresAt: expiresAt
        ))
    }

    func checkout(branchID: UUID, quantities: [UUID: Int], payment: PaymentMethod, tenderedCents: Int) -> StoreSale? {
        let result = repository.checkoutStoreSale(
            actorID: actor.id, branchID: branchID, quantities: quantities,
            paymentMethod: payment, cashReceivedCents: tenderedCents
        )
        lastError = result.error ?? ""
        return result.sale
    }

    func voidSale(_ sale: StoreSale, reason: String) -> String? {
        finish(repository.voidStoreSale(actorID: actor.id, saleID: sale.id, reason: reason))
    }

    func adjustLot(id: UUID, delta: Int, kind: StockMovementKind, reason: String) -> String? {
        finish(repository.adjustStoreLot(actorID: actor.id, lotID: id, quantityDelta: delta, kind: kind, reason: reason))
    }

    func createStaff(branchID: UUID, code: String, name: String, position: String, phone: String, email: String, hiredAt: Date) -> String? {
        finish(repository.createStaffMember(actorID: actor.id, branchID: branchID, employeeCode: code, fullName: name, position: position, phone: phone, email: email, hiredAt: hiredAt))
    }

    func saveStaff(_ member: StaffMember) -> String? {
        finish(repository.updateStaffMember(member, actorID: actor.id))
    }

    func setStaffStatus(_ member: StaffMember, status: StaffStatus) -> String? {
        finish(repository.setStaffStatus(id: member.id, status: status, actorID: actor.id))
    }

    func assignShift(branchID: UUID, employeeID: UUID, weekday: Int, shift: WorkShift) -> String? {
        finish(repository.assignShift(actorID: actor.id, branchID: branchID, employeeID: employeeID, weekday: weekday, shift: shift))
    }

    func removeShift(_ assignment: ShiftAssignment) -> String? {
        finish(repository.removeShift(id: assignment.id, actorID: actor.id))
    }

    func createEquipment(branchID: UUID, code: String, name: String, category: EquipmentCategory, serial: String) -> String? {
        finish(repository.createEquipment(actorID: actor.id, branchID: branchID, assetCode: code, name: name, category: category, serialNumber: serial))
    }

    func setEquipmentStatus(_ asset: StationEquipment, status: EquipmentStatus) -> String? {
        finish(repository.updateEquipmentStatus(id: asset.id, status: status, actorID: actor.id))
    }

    func saveEquipment(_ asset: StationEquipment, assetCode: String, name: String, serialNumber: String) -> String? {
        finish(repository.updateEquipmentDetails(
            id: asset.id, assetCode: assetCode, name: name, serialNumber: serialNumber, actorID: actor.id
        ))
    }

    func openMaintenance(branchID: UUID, equipmentID: UUID, title: String, description: String, priority: MaintenancePriority, provider: String) -> String? {
        finish(repository.openMaintenanceOrder(actorID: actor.id, branchID: branchID, equipmentID: equipmentID, title: title, description: description, priority: priority, providerName: provider))
    }

    func updateMaintenance(_ order: MaintenanceOrder, status: MaintenanceStatus, provider: String, costCents: Int) -> String? {
        finish(repository.updateMaintenanceOrder(id: order.id, status: status, providerName: provider, costCents: costCents, actorID: actor.id))
    }

    private func finish(_ error: String?) -> String? {
        lastError = error ?? ""
        return error
    }
}
