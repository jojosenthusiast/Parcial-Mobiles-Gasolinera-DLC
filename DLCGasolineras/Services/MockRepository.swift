import Combine
import Foundation
import Security

private struct RepositorySnapshot: Codable {
    var schemaVersion: Int
    var branches: [Branch]
    var users: [AppUser]
    var cuts: [DailyCut]
    var products: [StoreProduct]
    var suppliers: [StoreSupplier]
    var lots: [StoreLot]
    var stockMovements: [StockMovement]
    var storeSales: [StoreSale]
    var staff: [StaffMember]
    var shiftAssignments: [ShiftAssignment]
    var equipment: [StationEquipment]
    var maintenanceOrders: [MaintenanceOrder]
}

private enum CredentialVault {
    private static let service = "sv.com.dlc.gasolineras.credentials"

    static func save(_ password: String, for userID: UUID) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userID.uuidString
        ]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func password(for userID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for userID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userID.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum InputNormalization {
    static func text(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func username(_ value: String) -> String {
        text(value).lowercased()
    }

    static func code(_ value: String) -> String {
        text(value).uppercased()
    }

    static func validEmail(_ value: String) -> Bool {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return true }
        guard clean.count <= 254, !clean.contains(where: \.isWhitespace) else { return false }
        let parts = clean.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...64).contains(parts[0].count) else { return false }
        let domainLabels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard domainLabels.count >= 2,
              domainLabels.allSatisfy({ !$0.isEmpty && $0.count <= 63 }),
              let topLevelDomain = domainLabels.last, topLevelDomain.count >= 2 else { return false }
        return true
    }
}

/// Repositorio local de demostración. Mantiene la lógica fuera de las vistas;
/// conserva los datos operativos en Application Support y las contraseñas en Keychain.
@MainActor
final class MockRepository: ObservableObject {
    static let shared = MockRepository()

    @Published private(set) var branches: [Branch] = []
    @Published private(set) var users: [AppUser] = []
    @Published private(set) var cutsByBranch: [UUID: [DailyCut]] = [:]
    @Published private(set) var products: [StoreProduct] = []
    @Published private(set) var suppliers: [StoreSupplier] = []
    @Published private(set) var lots: [StoreLot] = []
    @Published private(set) var stockMovements: [StockMovement] = []
    @Published private(set) var storeSales: [StoreSale] = []
    @Published private(set) var staff: [StaffMember] = []
    @Published private(set) var shiftAssignments: [ShiftAssignment] = []
    @Published private(set) var equipment: [StationEquipment] = []
    @Published private(set) var maintenanceOrders: [MaintenanceOrder] = []

    private let storageURL: URL
    private(set) var persistenceError: String?
    @Published private(set) var recoveryRequiredMessage: String?

    private init() {
        storageURL = Self.makeStorageURL()
        let storedFileExists = FileManager.default.fileExists(atPath: storageURL.path)
        if !loadPersistedState() {
            // A missing file is a first launch. An unreadable existing file is
            // a recovery case: never replace its data with demo state.
            guard !storedFileExists else {
                recoveryRequiredMessage = recoveryRequiredMessage
                    ?? "Los datos guardados requieren recuperación. No se cargaron datos de demostración."
                return
            }
            seedDemoData()
            seedOperationsData()
            _ = persistState()
        } else {
            for branch in branches where branch.isActive { ensureTodayCuts(for: branch.id) }
        }
    }

    func authenticate(username: String, password: String) -> AppUser? {
        let normalized = InputNormalization.username(username)
        guard let user = users.first(where: {
            $0.isActive && InputNormalization.username($0.username) == normalized
        }) else { return nil }
        guard CredentialVault.password(for: user.id) == password else { return nil }

        if user.role == .branchManager {
            guard let branchID = user.branchID, branch(withID: branchID)?.isActive == true else { return nil }
        }
        return user
    }

    func branch(withID id: UUID) -> Branch? {
        branches.first(where: { $0.id == id })
    }

    func manager(withID id: UUID) -> AppUser? {
        users.first(where: { $0.id == id && $0.role == .branchManager })
    }

    func storeStock(branchID: UUID, productID: UUID, includeExpired: Bool = false) -> Int {
        lots.filter { lot in
            lot.branchID == branchID && lot.productID == productID && lot.remainingQuantity > 0
                && (includeExpired || !lot.isExpired())
        }.reduce(0) { $0 + $1.remainingQuantity }
    }

    func storeLots(branchID: UUID, productID: UUID? = nil) -> [StoreLot] {
        lots.filter { $0.branchID == branchID && (productID == nil || $0.productID == productID) }
            .sorted { left, right in
                switch (left.expiresAt, right.expiresAt) {
                case let (a?, b?): return a == b ? left.receivedAt < right.receivedAt : a < b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return left.receivedAt < right.receivedAt
                }
            }
    }

    func sales(
        from startDate: Date,
        through endDate: Date,
        branchID: UUID? = nil,
        includeVoided: Bool = false
    ) -> [StoreSale] {
        let lower = Calendar.current.startOfDay(for: startDate)
        let upper = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate
        return storeSales.filter { sale in
            (includeVoided || sale.status == .completed)
                && sale.soldAt >= lower && sale.soldAt < upper
                && (branchID == nil || sale.branchID == branchID)
        }.sorted { $0.soldAt > $1.soldAt }
    }

    func todayCuts(for branchID: UUID) -> [DailyCut] {
        ensureTodayCuts(for: branchID)
        let today = Calendar.current.startOfDay(for: Date())
        return (cutsByBranch[branchID] ?? [])
            .filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
            .sorted { cutOrder($0.type) < cutOrder($1.type) }
    }

    func cuts(for branchID: UUID, from startDate: Date, through endDate: Date) -> [DailyCut] {
        let lowerBound = Calendar.current.startOfDay(for: startDate)
        let upperBound = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate
        return (cutsByBranch[branchID] ?? [])
            .filter { $0.date >= lowerBound && $0.date < upperBound }
            .sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return cutOrder($0.type) < cutOrder($1.type)
            }
    }

    func allCuts(from startDate: Date, through endDate: Date, branchID: UUID? = nil) -> [DailyCut] {
        let selectedBranches = branchID.map { [$0] } ?? branches.filter(\.isActive).map(\.id)
        return selectedBranches.flatMap { cuts(for: $0, from: startDate, through: endDate) }
    }

    func addBranch(
        name: String,
        code: String,
        city: String,
        department: String,
        address: String,
        capacities: [FuelType: Double]
    ) -> String? {
        let cleanName = InputNormalization.text(name)
        let cleanCode = InputNormalization.code(code)
        let cleanCity = InputNormalization.text(city)
        let cleanDepartment = InputNormalization.text(department)
        let cleanAddress = InputNormalization.text(address)
        guard !cleanName.isEmpty, !cleanCode.isEmpty, !cleanCity.isEmpty, !cleanDepartment.isEmpty, !cleanAddress.isEmpty else {
            return "Completa nombre, código, ciudad, departamento y dirección."
        }
        guard cleanName.count <= 90, cleanCode.count <= 24, cleanCity.count <= 70,
              cleanDepartment.count <= 70, cleanAddress.count <= 180 else {
            return "Revisa la longitud de los datos de la sucursal."
        }
        guard !branches.contains(where: { $0.code.caseInsensitiveCompare(cleanCode) == .orderedSame }) else {
            return "Ya existe una sucursal con ese código."
        }
        guard FuelType.allCases.allSatisfy({
            let capacity = capacities[$0] ?? 0
            return capacity.isFinite && capacity > 0 && capacity <= 1_000_000
        }) else {
            return "Cada tanque debe tener una capacidad mayor que cero."
        }

        let before = makeSnapshot()
        let branch = Branch(
            id: UUID(), name: cleanName, code: cleanCode, city: cleanCity,
            department: cleanDepartment, address: cleanAddress,
            tanks: FuelType.allCases.map {
                FuelTank(id: UUID(), type: $0, currentLiters: 0, capacityLiters: capacities[$0] ?? 0)
            },
            pricePerGallonUSD: Self.demoPrices()
        )
        branches.append(branch)
        cutsByBranch[branch.id] = []
        ensureTodayCuts(for: branch.id)
        return commit(before, message: "No se pudo guardar la sucursal en el almacenamiento local.")
    }

    func updateBranch(
        id: UUID, name: String, code: String, city: String, department: String,
        address: String, capacities: [FuelType: Double]
    ) -> String? {
        let cleanName = InputNormalization.text(name)
        let cleanCode = InputNormalization.code(code)
        let cleanCity = InputNormalization.text(city)
        let cleanDepartment = InputNormalization.text(department)
        let cleanAddress = InputNormalization.text(address)
        guard !cleanName.isEmpty, !cleanCode.isEmpty, !cleanCity.isEmpty,
              !cleanDepartment.isEmpty, !cleanAddress.isEmpty else {
            return "Completa nombre, código, ciudad, departamento y dirección."
        }
        guard cleanName.count <= 90, cleanCode.count <= 24, cleanCity.count <= 70,
              cleanDepartment.count <= 70, cleanAddress.count <= 180 else {
            return "Revisa la longitud de los datos de la sucursal."
        }
        guard let index = branches.firstIndex(where: { $0.id == id }) else { return "No se encontró la sucursal." }
        guard !branches.contains(where: { $0.id != id && $0.code.caseInsensitiveCompare(cleanCode) == .orderedSame }) else {
            return "Ya existe una sucursal con ese código."
        }
        guard FuelType.allCases.allSatisfy({
            let capacity = capacities[$0] ?? 0
            return capacity.isFinite && capacity > 0 && capacity <= 1_000_000
        }) else { return "Cada tanque debe tener una capacidad mayor que cero." }
        for fuel in FuelType.allCases {
            guard let tank = branches[index].tanks.first(where: { $0.type == fuel }),
                  let capacity = capacities[fuel], tank.currentLiters <= capacity else {
                return "La capacidad nueva de cada tanque debe cubrir su existencia actual."
            }
        }
        let before = makeSnapshot()
        branches[index].name = cleanName
        branches[index].code = cleanCode
        branches[index].city = cleanCity
        branches[index].department = cleanDepartment
        branches[index].address = cleanAddress
        for tankIndex in branches[index].tanks.indices {
            let fuel = branches[index].tanks[tankIndex].type
            branches[index].tanks[tankIndex].capacityLiters = capacities[fuel] ?? 0
        }
        return commit(before, message: "No se pudo guardar la edición de la sucursal.")
    }

    func setBranchActive(_ id: UUID, active: Bool) -> String? {
        guard let index = branches.firstIndex(where: { $0.id == id }) else { return "No se encontró la sucursal." }
        guard branches[index].isActive != active else { return nil }
        let before = makeSnapshot()
        branches[index].isActive = active
        return commit(before, message: "No se pudo actualizar el estado de la sucursal.")
    }

    func addManager(name: String, username: String, password: String, branchID: UUID) -> String? {
        let cleanName = InputNormalization.text(name)
        let cleanUsername = InputNormalization.username(username)
        guard !cleanName.isEmpty, !cleanUsername.isEmpty, validPassword(password) else {
            return "Ingresa nombre, usuario y una contraseña de 8 caracteres que incluya letras y números."
        }
        guard cleanName.count <= 90, (3...32).contains(cleanUsername.count),
              cleanUsername.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }) else {
            return "El nombre admite hasta 90 caracteres; el usuario debe tener 3 a 32 letras, números, puntos, guiones o guiones bajos."
        }
        guard branch(withID: branchID)?.isActive == true else { return "Selecciona una sucursal activa." }
        guard !users.contains(where: { InputNormalization.username($0.username) == cleanUsername }) else {
            return "Ese usuario ya está registrado."
        }

        let before = makeSnapshot()
        let manager = AppUser(
            id: UUID(), name: cleanName, username: cleanUsername,
            role: .branchManager, branchID: branchID
        )
        guard CredentialVault.save(password, for: manager.id) else { return "No se pudo guardar la contraseña de forma segura." }
        users.append(manager)
        if let error = commit(before, message: "No se pudo guardar el usuario.") {
            CredentialVault.delete(for: manager.id)
            return error
        }
        return nil
    }

    func assignManager(_ managerID: UUID, to branchID: UUID?) -> String? {
        guard let index = users.firstIndex(where: { $0.id == managerID && $0.role == .branchManager }) else {
            return "No se encontró el perfil de gerente."
        }
        if let branchID, branch(withID: branchID)?.isActive != true { return "La sucursal seleccionada no existe o está inactiva." }
        let before = makeSnapshot()
        users[index].branchID = branchID
        return commit(before, message: "No se pudo guardar la asignación del gerente.")
    }

    func updateManager(id: UUID, name: String, email: String, branchID: UUID?) -> String? {
        let cleanName = InputNormalization.text(name)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 90 else { return "Ingresa un nombre válido de hasta 90 caracteres." }
        guard InputNormalization.validEmail(cleanEmail) else { return "Revisa el formato del correo electrónico." }
        if let branchID, branch(withID: branchID)?.isActive != true { return "Selecciona una sucursal activa." }
        guard let index = users.firstIndex(where: { $0.id == id && $0.role == .branchManager }) else {
            return "No se encontró el gerente."
        }
        let before = makeSnapshot()
        users[index].name = cleanName
        users[index].email = cleanEmail
        users[index].branchID = branchID
        return commit(before, message: "No se pudo actualizar el perfil del gerente.")
    }

    func setUserActive(_ id: UUID, active: Bool) -> String? {
        guard let index = users.firstIndex(where: { $0.id == id }) else { return "No se encontró la cuenta." }
        guard users[index].isActive != active else { return nil }
        if users[index].role == .generalManager, active == false,
           users.filter({ $0.role == .generalManager && $0.isActive }).count <= 1 {
            return "Debe quedar al menos una cuenta activa de Gerente General."
        }
        let before = makeSnapshot()
        users[index].isActive = active
        return commit(before, message: "No se pudo actualizar el estado de la cuenta.")
    }

    func resetUserPassword(id: UUID, password: String, confirmation: String) -> String? {
        guard users.contains(where: { $0.id == id }) else { return "No se encontró la cuenta." }
        guard validPassword(password) else { return "La contraseña debe tener 8 caracteres e incluir letras y números." }
        guard password == confirmation else { return "Las contraseñas no coinciden." }
        guard CredentialVault.save(password, for: id) else { return "No se pudo actualizar la contraseña segura." }
        return nil
    }

    func saveOpenCut(_ cut: DailyCut) -> String? {
        guard !cut.isClosed else { return "El corte ya está cerrado y no se puede modificar." }
        guard branch(withID: cut.branchID)?.isActive == true else { return "La sucursal del corte ya no existe o está inactiva." }
        var list = cutsByBranch[cut.branchID] ?? []
        guard let index = list.firstIndex(where: { $0.id == cut.id }) else { return "No se encontró el corte." }
        // Reject a stale in-memory copy when the persisted cut has already
        // been closed or its inventory has already been consolidated.
        guard !list[index].isClosed, !list[index].inventoryApplied else {
            return "El corte ya está cerrado y no se puede modificar."
        }
        let before = makeSnapshot()
        list[index] = cut
        cutsByBranch[cut.branchID] = list
        return commit(before, message: "No se pudo guardar el corte en el almacenamiento local.")
    }

    func readingContinuityError(
        cutID: UUID,
        pumpNumber: Int,
        proposedReadings: [FuelType: (initial: Double, final: Double)]
    ) -> String? {
        guard let currentCut = cutsByBranch.values.flatMap({ $0 }).first(where: { $0.id == cutID }) else {
            return "No se encontró el corte para validar la continuidad."
        }
        guard let previousCut = previousOperationalCut(before: currentCut) else { return nil }
        guard previousCut.isClosed, previousCut.inventoryApplied else {
            return "Cierra y consolida el corte anterior antes de registrar nuevas lecturas."
        }
        guard let previousPump = previousCut.pumpReadings.first(where: { $0.pumpNumber == pumpNumber }) else {
            return "El corte anterior no tiene una lectura confirmada para la bomba \(pumpNumber)."
        }

        for fuel in FuelType.allCases {
            guard let previousFinal = previousPump.readings.first(where: { $0.type == fuel })?.finalGallons,
                  let proposed = proposedReadings[fuel] else {
                return "Falta la lectura de continuidad de \(fuel.rawValue) para la bomba \(pumpNumber)."
            }
            guard abs(proposed.initial - previousFinal) <= 0.01 else {
                return "La lectura inicial de \(fuel.rawValue) debe continuar desde \(String(format: "%.2f", previousFinal)) gal del corte anterior."
            }
        }
        return nil
    }

    /// Valida y consolida una sola vez las seis bombas, los movimientos y el inventario.
    func closeCut(id: UUID, branchID: UUID) -> String? {
        guard var branch = branch(withID: branchID) else { return "No se encontró la sucursal." }
        guard var list = cutsByBranch[branchID], let index = list.firstIndex(where: { $0.id == id }) else {
            return "No se encontró el corte del día."
        }
        var cut = list[index]
        guard !cut.isClosed else { return "El corte ya está cerrado." }
        guard cut.canClose else { return "Registra las seis bombas y revisa sus tres lecturas antes de cerrar." }
        guard !cut.inventoryApplied else { return "El inventario de este corte ya fue consolidado." }

        let before = makeSnapshot()

        for movement in cut.movements {
            guard movement.quantityLiters.isFinite, movement.quantityLiters > 0 else { return "Los movimientos deben ser mayores que cero y usar una cantidad válida." }
            if movement.kind == .loss, (movement.cause == nil || movement.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                return "Toda pérdida o daño requiere categoría y explicación."
            }
            if movement.kind == .receipt,
               (movement.supplier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || movement.documentReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                return "Cada recepción debe incluir proveedor y documento o folio."
            }
        }

        for fuel in FuelType.allCases {
            guard let tankIndex = branch.tanks.firstIndex(where: { $0.type == fuel }) else {
                return "Falta configurar el tanque de \(fuel.rawValue)."
            }
            let received = cut.movementLiters(kind: .receipt, fuel: fuel)
            let losses = cut.movementLiters(kind: .loss, fuel: fuel)
            let soldLiters = cut.soldGallons(for: fuel) * .litersPerUSGallon
            let resultingStock = branch.tanks[tankIndex].currentLiters + received - losses - soldLiters

            if resultingStock < -0.01 {
                return "El inventario de \(fuel.rawValue) no cubre las ventas y pérdidas registradas."
            }
            if resultingStock > branch.tanks[tankIndex].capacityLiters + 0.01 {
                return "La recepción de \(fuel.rawValue) supera la capacidad del tanque."
            }
            branch.tanks[tankIndex].currentLiters = max(resultingStock, 0)
        }

        cut.isClosed = true
        cut.inventoryApplied = true
        list[index] = cut
        replaceBranch(branch)
        cutsByBranch[branchID] = list
        return commit(before, message: "No se pudo guardar el cierre del corte.")
    }

    private func ensureTodayCuts(for branchID: UUID) {
        guard branch(withID: branchID) != nil else { return }
        let today = Calendar.current.startOfDay(for: Date())
        var list = cutsByBranch[branchID] ?? []
        var changed = false
        for type in CutType.allCases where !list.contains(where: {
            $0.type == type && Calendar.current.isDate($0.date, inSameDayAs: today)
        }) {
            list.append(DailyCut(
                id: UUID(), branchID: branchID, type: type, date: today,
                movements: [], pumpReadings: [], isClosed: false, inventoryApplied: false
            ))
            changed = true
        }
        if changed {
            cutsByBranch[branchID] = list
            _ = persistState()
        }
    }

    private func replaceBranch(_ branch: Branch) {
        guard let index = branches.firstIndex(where: { $0.id == branch.id }) else { return }
        branches[index] = branch
    }

    private func cutOrder(_ type: CutType) -> Int { type == .morning ? 0 : 1 }

    private func previousOperationalCut(before cut: DailyCut) -> DailyCut? {
        let targetDay = Calendar.current.startOfDay(for: cut.date)
        return (cutsByBranch[cut.branchID] ?? [])
            .filter { candidate in
                let candidateDay = Calendar.current.startOfDay(for: candidate.date)
                if candidateDay != targetDay { return candidateDay < targetDay }
                return cutOrder(candidate.type) < cutOrder(cut.type)
            }
            .max { lhs, rhs in
                let lhsDay = Calendar.current.startOfDay(for: lhs.date)
                let rhsDay = Calendar.current.startOfDay(for: rhs.date)
                if lhsDay != rhsDay { return lhsDay < rhsDay }
                return cutOrder(lhs.type) < cutOrder(rhs.type)
            }
    }

    private static func makeStorageURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("DLCGasolineras", isDirectory: true)
            .appendingPathComponent("repository-v1.json")
    }

    private func makeSnapshot() -> RepositorySnapshot {
        RepositorySnapshot(
            schemaVersion: 1,
            branches: branches,
            users: users,
            cuts: cutsByBranch.values.flatMap { $0 },
            products: products,
            suppliers: suppliers,
            lots: lots,
            stockMovements: stockMovements,
            storeSales: storeSales,
            staff: staff,
            shiftAssignments: shiftAssignments,
            equipment: equipment,
            maintenanceOrders: maintenanceOrders
        )
    }

    /// Creates a credential-free copy of the local business snapshot for a
    /// deliberate user initiated migration/backup. The live file is never moved
    /// or modified by this operation.
    func makeLegacyExportFile() throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(makeSnapshot())
        let filename = "dlc-respaldo-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    private func apply(_ snapshot: RepositorySnapshot) {
        branches = snapshot.branches
        users = snapshot.users
        cutsByBranch = Dictionary(grouping: snapshot.cuts, by: \.branchID)
        products = snapshot.products
        suppliers = snapshot.suppliers
        lots = snapshot.lots
        stockMovements = snapshot.stockMovements
        storeSales = snapshot.storeSales
        staff = snapshot.staff
        shiftAssignments = snapshot.shiftAssignments
        equipment = snapshot.equipment
        maintenanceOrders = snapshot.maintenanceOrders
    }

    @discardableResult
    private func commit(_ previous: RepositorySnapshot, message: String) -> String? {
        guard persistState() else {
            apply(previous)
            return persistenceError ?? message
        }
        return nil
    }

    @discardableResult
    private func persistState() -> Bool {
        do {
            let directory = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(makeSnapshot())
            try data.write(to: storageURL, options: .atomic)
            persistenceError = nil
            return true
        } catch {
            persistenceError = "No se guardaron los cambios locales: \(error.localizedDescription)"
            return false
        }
    }

    private func loadPersistedState() -> Bool {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return false }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(RepositorySnapshot.self, from: data)
            guard snapshot.schemaVersion == 1,
                  Set(snapshot.branches.map(\.id)).count == snapshot.branches.count,
                  Set(snapshot.users.map(\.id)).count == snapshot.users.count,
                  Set(snapshot.users.map { InputNormalization.username($0.username) }).count == snapshot.users.count,
                  snapshot.cuts.allSatisfy({ branchID in snapshot.branches.contains(where: { $0.id == branchID.branchID }) }),
                  snapshot.lots.allSatisfy({ lot in snapshot.branches.contains(where: { $0.id == lot.branchID }) && snapshot.products.contains(where: { $0.id == lot.productID }) }),
                  snapshot.staff.allSatisfy({ member in snapshot.branches.contains(where: { $0.id == member.branchID }) }) else {
                backupUnreadableStore(reason: "El archivo local no supera las validaciones de integridad.")
                return false
            }
            apply(snapshot)
            return true
        } catch {
            backupUnreadableStore(reason: "No se pudo leer el archivo local: \(error.localizedDescription)")
            return false
        }
    }

    private func backupUnreadableStore(reason: String) {
        recoveryRequiredMessage = "\(reason) La aplicación se detuvo antes de cargar datos de demostración."
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        let backup = storageURL.deletingLastPathComponent()
            .appendingPathComponent("repository-recovery-\(UUID().uuidString).json")
        do {
            // Copy rather than move so the original bytes remain available
            // even if backup creation or a later recovery attempt fails.
            try FileManager.default.copyItem(at: storageURL, to: backup)
        } catch {
            recoveryRequiredMessage = "\(recoveryRequiredMessage ?? reason) No se pudo crear la copia de recuperación (\(error.localizedDescription)); el archivo original permanece intacto."
        }
    }

    private func validPassword(_ password: String) -> Bool {
        password.count >= 8
            && password.rangeOfCharacter(from: .letters) != nil
            && password.rangeOfCharacter(from: .decimalDigits) != nil
            && !password.contains(where: \.isWhitespace)
    }

    private func canAccess(branchID: UUID, actorID: UUID, requireBranchManager: Bool = false) -> Bool {
        guard let actor = users.first(where: { $0.id == actorID && $0.isActive }),
              branch(withID: branchID)?.isActive == true else { return false }
        if actor.role == .generalManager { return !requireBranchManager }
        return actor.branchID == branchID
    }

    private func actorHasGeneralRole(_ actorID: UUID) -> Bool {
        users.contains(where: { $0.id == actorID && $0.isActive && $0.role == .generalManager })
    }

    private static func demoPrices() -> [FuelType: Double] {
        [.regular: 3.79, .superFuel: 3.99, .diesel: 3.58]
    }

    private func seedDemoData() {
        let santaID = UUID()
        let kiloID = UUID()
        let bartoloID = UUID()
        let soyapangoID = UUID()

        branches = [
            Branch(id: santaID, name: "DLC Santa Ana", code: "SA-01", city: "Santa Ana", department: "Santa Ana", address: "Avenida Independencia Sur y 21 Calle Poniente", tanks: [
                FuelTank(id: UUID(), type: .superFuel, currentLiters: 10_200, capacityLiters: 12_000),
                FuelTank(id: UUID(), type: .regular, currentLiters: 9_100, capacityLiters: 12_000),
                FuelTank(id: UUID(), type: .diesel, currentLiters: 7_800, capacityLiters: 10_000)
            ], pricePerGallonUSD: Self.demoPrices()),
            Branch(id: kiloID, name: "DLC Kilo 5", code: "SO-05", city: "Acajutla", department: "Sonsonate", address: "Carretera del Litoral, Km 5", tanks: [
                FuelTank(id: UUID(), type: .superFuel, currentLiters: 9_200, capacityLiters: 12_000),
                FuelTank(id: UUID(), type: .regular, currentLiters: 7_100, capacityLiters: 12_000),
                FuelTank(id: UUID(), type: .diesel, currentLiters: 6_200, capacityLiters: 10_000)
            ], pricePerGallonUSD: Self.demoPrices()),
            Branch(id: bartoloID, name: "DLC San Bartolo", code: "IL-02", city: "Ilopango", department: "San Salvador", address: "San Bartolo", tanks: [
                FuelTank(id: UUID(), type: .superFuel, currentLiters: 8_200, capacityLiters: 12_000),
                FuelTank(id: UUID(), type: .regular, currentLiters: 7_600, capacityLiters: 12_000),
                FuelTank(id: UUID(), type: .diesel, currentLiters: 5_100, capacityLiters: 10_000)
            ], pricePerGallonUSD: Self.demoPrices()),
            Branch(id: soyapangoID, name: "DLC Soyapango", code: "SS-11", city: "Soyapango", department: "San Salvador", address: "Bulevar del Ejército", tanks: [
                FuelTank(id: UUID(), type: .superFuel, currentLiters: 9_400, capacityLiters: 12_000),
                FuelTank(id: UUID(), type: .regular, currentLiters: 8_100, capacityLiters: 12_000),
                FuelTank(id: UUID(), type: .diesel, currentLiters: 6_900, capacityLiters: 10_000)
            ], pricePerGallonUSD: Self.demoPrices())
        ]

        let adminID = UUID()
        let santaManagerID = UUID()
        users = [
            AppUser(id: adminID, name: "Gerente General", username: "admin", role: .generalManager, branchID: nil),
            AppUser(id: santaManagerID, name: "Ana López", username: "santa", role: .branchManager, branchID: santaID)
        ]
        if !CredentialVault.save("admin123", for: adminID) || !CredentialVault.save("santa123", for: santaManagerID) {
            persistenceError = "No se pudieron preparar las credenciales de demostración en el llavero del dispositivo."
        }

        let branchIDs = [santaID, kiloID, bartoloID, soyapangoID]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for (branchIndex, branchID) in branchIDs.enumerated() {
            var branchCuts: [DailyCut] = []
            for daysBack in 0..<7 {
                let date = calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
                for type in CutType.allCases {
                    let isInProgress = daysBack == 0 && type == .evening
                    let pumpCount = isInProgress ? (branchIndex == 0 ? 4 : 3) : 6
                    let pumps = samplePumps(count: pumpCount, seed: branchIndex * 13 + daysBack * 3)
                    var movements: [FuelMovement] = []
                    if branchIndex == 0 && daysBack == 0 && type == .evening {
                        movements = [
                            FuelMovement(id: UUID(), kind: .receipt, fuel: .diesel, quantityLiters: 500, cause: nil, explanation: "", supplier: "Distribuidora de prueba", documentReference: "RC-2041", recordedAt: Date()),
                            FuelMovement(id: UUID(), kind: .loss, fuel: .regular, quantityLiters: 42, cause: .spill, explanation: "Diferencia detectada durante la revisión del tanque.", supplier: "", documentReference: "", recordedAt: Date())
                        ]
                    }
                    branchCuts.append(DailyCut(
                        id: UUID(), branchID: branchID, type: type, date: date,
                        movements: movements, pumpReadings: pumps,
                        isClosed: !isInProgress, inventoryApplied: !isInProgress
                    ))
                }
            }
            cutsByBranch[branchID] = branchCuts
        }
    }

    private func samplePumps(count: Int, seed: Int) -> [PumpReading] {
        (1...count).map { number in
            let base = Double(seed * 2_000 + number * 1_000)
            let readings = FuelType.allCases.enumerated().map { index, fuel in
                let initial = base + Double(index * 4_000)
                let sold = Double(54 + number * 9 + index * 7 + seed % 11)
                return FuelReading(id: UUID(), type: fuel, initialGallons: initial, finalGallons: initial + sold)
            }
            return PumpReading(id: UUID(), pumpNumber: number, readings: readings)
        }
    }

    func createStoreProduct(
        actorID: UUID, sku: String, barcode: String, name: String, brand: String,
        category: StoreCategory, unitName: String, unitCostCents: Int,
        unitPriceCents: Int, minimumStock: Int
    ) -> String? {
        guard actorHasGeneralRole(actorID) else { return "Solo el Gerente General puede administrar el catálogo." }
        let cleanSKU = InputNormalization.code(sku)
        let cleanName = InputNormalization.text(name)
        let cleanBrand = InputNormalization.text(brand)
        let cleanUnit = InputNormalization.text(unitName)
        let cleanBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSKU.isEmpty, !cleanName.isEmpty, !cleanUnit.isEmpty else { return "Completa código, nombre y unidad del producto." }
        guard cleanSKU.count <= 30, cleanBarcode.count <= 64, cleanName.count <= 90,
              cleanBrand.count <= 60, cleanUnit.count <= 24 else { return "Revisa la longitud de los datos del producto." }
        guard unitCostCents >= 0, unitPriceCents > 0, minimumStock >= 0,
              unitCostCents <= 50_000_000, unitPriceCents <= 50_000_000, minimumStock <= 100_000 else {
            return "Revisa costo, precio y mínimo de inventario."
        }
        guard !products.contains(where: { $0.sku.caseInsensitiveCompare(cleanSKU) == .orderedSame }) else {
            return "Ya existe un producto con ese código."
        }
        if !cleanBarcode.isEmpty, products.contains(where: { $0.barcode == cleanBarcode }) {
            return "El código de barras ya está asociado a otro producto."
        }
        let before = makeSnapshot()
        products.append(StoreProduct(
            id: UUID(), sku: cleanSKU, barcode: cleanBarcode, name: cleanName, brand: cleanBrand,
            category: category, unitName: cleanUnit, unitCostCents: unitCostCents,
            unitPriceCents: unitPriceCents, minimumStock: minimumStock, isActive: true
        ))
        return commit(before, message: "No se pudo guardar el producto.")
    }

    func updateStoreProduct(_ product: StoreProduct, actorID: UUID) -> String? {
        guard actorHasGeneralRole(actorID) else { return "Solo el Gerente General puede administrar el catálogo." }
        guard let index = products.firstIndex(where: { $0.id == product.id }) else { return "No se encontró el producto." }
        let cleanSKU = InputNormalization.code(product.sku)
        let cleanName = InputNormalization.text(product.name)
        let cleanUnit = InputNormalization.text(product.unitName)
        let cleanBarcode = product.barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBrand = InputNormalization.text(product.brand)
        guard !cleanSKU.isEmpty, !cleanName.isEmpty, !cleanUnit.isEmpty,
              cleanSKU.count <= 30, cleanBarcode.count <= 64, cleanName.count <= 90, cleanUnit.count <= 24,
              cleanBrand.count <= 60,
              product.unitCostCents >= 0, product.unitCostCents <= 50_000_000,
              product.unitPriceCents > 0, product.unitPriceCents <= 50_000_000,
              product.minimumStock >= 0, product.minimumStock <= 100_000 else {
            return "Revisa los datos y cantidades del producto."
        }
        guard !products.contains(where: { $0.id != product.id && $0.sku.caseInsensitiveCompare(cleanSKU) == .orderedSame }) else {
            return "Ya existe otro producto con ese código."
        }
        if !cleanBarcode.isEmpty, products.contains(where: { $0.id != product.id && $0.barcode == cleanBarcode }) {
            return "El código de barras ya está asociado a otro producto."
        }
        let before = makeSnapshot()
        products[index] = StoreProduct(
            id: product.id, sku: cleanSKU, barcode: cleanBarcode, name: cleanName,
            brand: cleanBrand, category: product.category,
            unitName: cleanUnit, unitCostCents: product.unitCostCents,
            unitPriceCents: product.unitPriceCents, minimumStock: product.minimumStock,
            isActive: product.isActive
        )
        return commit(before, message: "No se pudo actualizar el producto.")
    }

    func createSupplier(
        actorID: UUID, name: String, taxIdentifier: String, contactName: String,
        phone: String, email: String, address: String, scope: SupplierScope
    ) -> String? {
        guard actorHasGeneralRole(actorID) else { return "Solo el Gerente General puede administrar proveedores." }
        let cleanName = InputNormalization.text(name)
        let cleanTaxID = InputNormalization.code(taxIdentifier)
        let cleanContact = InputNormalization.text(contactName)
        let cleanPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanAddress = InputNormalization.text(address)
        guard !cleanName.isEmpty, !cleanContact.isEmpty else { return "Completa el proveedor y la persona de contacto." }
        guard InputNormalization.validEmail(cleanEmail), Self.validPhone(cleanPhone) else { return "Revisa el correo o el teléfono del proveedor." }
        guard cleanName.count <= 100, cleanTaxID.count <= 32, cleanContact.count <= 90,
              cleanPhone.count <= 24, cleanEmail.count <= 254, cleanAddress.count <= 180 else {
            return "Revisa la longitud de los datos del proveedor."
        }
        guard !suppliers.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) else {
            return "Ya existe un proveedor con ese nombre."
        }
        let before = makeSnapshot()
        suppliers.append(StoreSupplier(
            id: UUID(), name: cleanName, taxIdentifier: cleanTaxID, contactName: cleanContact,
            phone: cleanPhone, email: cleanEmail, address: cleanAddress, scope: scope, isActive: true
        ))
        return commit(before, message: "No se pudo guardar el proveedor.")
    }

    func updateSupplier(_ supplier: StoreSupplier, actorID: UUID) -> String? {
        guard actorHasGeneralRole(actorID) else { return "Solo el Gerente General puede administrar proveedores." }
        guard let index = suppliers.firstIndex(where: { $0.id == supplier.id }) else { return "No se encontró el proveedor." }
        let cleanName = InputNormalization.text(supplier.name)
        let cleanPhone = supplier.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = supplier.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanName.isEmpty, !InputNormalization.text(supplier.contactName).isEmpty,
              Self.validPhone(cleanPhone), InputNormalization.validEmail(cleanEmail) else {
            return "Revisa nombre, contacto, correo y teléfono."
        }
        guard cleanName.count <= 100, supplier.taxIdentifier.count <= 32,
              supplier.contactName.count <= 90, cleanPhone.count <= 24,
              cleanEmail.count <= 254, supplier.address.count <= 180 else {
            return "Revisa la longitud de los datos del proveedor."
        }
        guard !suppliers.contains(where: { $0.id != supplier.id && $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) else {
            return "Ya existe otro proveedor con ese nombre."
        }
        let before = makeSnapshot()
        suppliers[index] = StoreSupplier(
            id: supplier.id, name: cleanName, taxIdentifier: InputNormalization.code(supplier.taxIdentifier),
            contactName: InputNormalization.text(supplier.contactName), phone: cleanPhone, email: cleanEmail,
            address: InputNormalization.text(supplier.address), scope: supplier.scope, isActive: supplier.isActive
        )
        return commit(before, message: "No se pudo actualizar el proveedor.")
    }

    func receiveStoreLot(
        actorID: UUID, branchID: UUID, productID: UUID, supplierID: UUID,
        lotCode: String, reference: String, quantity: Int, unitCostCents: Int,
        receivedAt: Date, expiresAt: Date?
    ) -> String? {
        guard canAccess(branchID: branchID, actorID: actorID) else { return "No tienes acceso a esta sucursal." }
        let cleanLot = InputNormalization.code(lotCode)
        let cleanReference = InputNormalization.code(reference)
        guard let product = products.first(where: { $0.id == productID && $0.isActive }) else { return "Selecciona un producto activo." }
        guard let supplier = suppliers.first(where: { $0.id == supplierID && $0.isActive && $0.supportsStore }) else {
            return "Selecciona un proveedor activo de tienda."
        }
        guard !cleanLot.isEmpty, !cleanReference.isEmpty, cleanLot.count <= 48, cleanReference.count <= 48 else {
            return "Ingresa un lote y un documento o folio válidos."
        }
        guard quantity > 0, quantity <= 100_000, unitCostCents >= 0, unitCostCents <= 50_000_000 else {
            return "La cantidad debe ser positiva y el costo válido."
        }
        guard receivedAt <= Date() else { return "La fecha de recepción no puede ser futura." }
        if let expiresAt, Calendar.current.startOfDay(for: expiresAt) < Calendar.current.startOfDay(for: receivedAt) {
            return "La fecha de vencimiento no puede preceder a la recepción."
        }
        guard !lots.contains(where: {
            $0.branchID == branchID && $0.productID == productID && $0.lotCode.caseInsensitiveCompare(cleanLot) == .orderedSame
        }) else { return "Ese código de lote ya existe para este producto en la sucursal." }

        let before = makeSnapshot()
        let lot = StoreLot(
            id: UUID(), branchID: branchID, productID: productID, supplierID: supplierID,
            lotCode: cleanLot, documentReference: cleanReference, receivedAt: receivedAt,
            expiresAt: expiresAt, receivedQuantity: quantity, remainingQuantity: quantity,
            unitCostCents: unitCostCents
        )
        lots.append(lot)
        stockMovements.append(StockMovement(
            id: UUID(), branchID: branchID, productID: productID, lotID: lot.id,
            kind: .receipt, quantityDelta: quantity, unitCostCents: unitCostCents,
            reference: cleanReference, reason: "Recepción de inventario de tienda de \(supplier.name)",
            actorID: actorID, recordedAt: Date()
        ))
        return commit(before, message: "No se pudo guardar la recepción del lote.")
    }

    func adjustStoreLot(
        actorID: UUID, lotID: UUID, quantityDelta: Int,
        kind: StockMovementKind, reason: String
    ) -> String? {
        guard let index = lots.firstIndex(where: { $0.id == lotID }) else { return "No se encontró el lote." }
        let lot = lots[index]
        guard canAccess(branchID: lot.branchID, actorID: actorID) else { return "No tienes acceso a esta sucursal." }
        guard [.adjustment, .damaged, .expired].contains(kind),
              quantityDelta != 0, (-100_000...100_000).contains(quantityDelta) else {
            return "Selecciona un tipo y una cantidad válidos."
        }
        let cleanReason = InputNormalization.text(reason)
        guard !cleanReason.isEmpty, cleanReason.count >= 5 else { return "Explica el motivo del ajuste con al menos 5 caracteres." }
        guard kind == .adjustment || quantityDelta < 0 else { return "Daños y vencimientos solo pueden reducir existencias." }
        if kind == .expired, !lot.isExpired() { return "Solo se pueden retirar lotes que ya vencieron." }
        if quantityDelta > 0, lot.isExpired() { return "No se puede agregar existencia a un lote vencido." }
        let (newRemaining, remainingOverflow) = lot.remainingQuantity.addingReportingOverflow(quantityDelta)
        guard !remainingOverflow, newRemaining >= 0 else { return "La salida supera la existencia del lote." }
        guard newRemaining <= 100_000 else { return "La existencia del lote no puede superar 100,000 unidades." }
        let (newReceived, receivedOverflow) = lot.receivedQuantity.addingReportingOverflow(max(quantityDelta, 0))
        guard !receivedOverflow, newReceived <= 1_000_000 else { return "El historial del lote supera el límite permitido." }

        let before = makeSnapshot()
        lots[index].remainingQuantity = newRemaining
        if quantityDelta > 0 { lots[index].receivedQuantity = newReceived }
        stockMovements.append(StockMovement(
            id: UUID(), branchID: lot.branchID, productID: lot.productID, lotID: lot.id,
            kind: kind, quantityDelta: quantityDelta, unitCostCents: lot.unitCostCents,
            reference: "AJ-\(UUID().uuidString.prefix(8))", reason: cleanReason,
            actorID: actorID, recordedAt: Date()
        ))
        return commit(before, message: "No se pudo registrar el ajuste de inventario.")
    }

    func checkoutStoreSale(
        actorID: UUID, branchID: UUID, quantities: [UUID: Int],
        paymentMethod: PaymentMethod, cashReceivedCents: Int
    ) -> (sale: StoreSale?, error: String?) {
        guard canAccess(branchID: branchID, actorID: actorID, requireBranchManager: true) else {
            return (nil, "El punto de venta solo está disponible para el Gerente de Sucursal asignado.")
        }
        let cart = quantities.filter { $0.value > 0 }
        guard !cart.isEmpty, cart.count <= 80, quantities.allSatisfy({ $0.value >= 0 && $0.value <= 999 }) else {
            return (nil, "Agrega artículos y revisa las cantidades del carrito.")
        }
        let selectedProducts = cart.keys.compactMap { id in products.first(where: { $0.id == id && $0.isActive }) }
        guard selectedProducts.count == cart.count else { return (nil, "Uno de los productos ya no está disponible.") }
        for (productID, quantity) in cart where storeStock(branchID: branchID, productID: productID) < quantity {
            let productName = products.first(where: { $0.id == productID })?.name ?? "Producto"
            return (nil, "Existencia insuficiente de \(productName); se excluyen lotes vencidos.")
        }

        let ordered = selectedProducts.sorted { $0.sku < $1.sku }
        let total = ordered.reduce(0) { $0 + (cart[$1.id, default: 0] * $1.unitPriceCents) }
        if paymentMethod == .cash, cashReceivedCents < total { return (nil, "El efectivo recibido no cubre el total de la venta.") }
        guard total > 0 else { return (nil, "El total de la venta debe ser mayor que cero.") }

        let before = makeSnapshot()
        var lines: [StoreSaleLine] = []
        for product in ordered {
            var remaining = cart[product.id, default: 0]
            var allocations: [SaleLineLotAllocation] = []
            for lot in storeLots(branchID: branchID, productID: product.id) where remaining > 0 && !lot.isExpired() {
                guard let lotIndex = lots.firstIndex(where: { $0.id == lot.id }) else { continue }
                let used = min(remaining, lots[lotIndex].remainingQuantity)
                guard used > 0 else { continue }
                lots[lotIndex].remainingQuantity -= used
                remaining -= used
                allocations.append(SaleLineLotAllocation(lotID: lot.id, quantity: used))
                stockMovements.append(StockMovement(
                    id: UUID(), branchID: branchID, productID: product.id, lotID: lot.id,
                    kind: .sale, quantityDelta: -used, unitCostCents: lot.unitCostCents,
                    reference: "POS-\(UUID().uuidString.prefix(8))", reason: "Salida por venta",
                    actorID: actorID, recordedAt: Date()
                ))
            }
            guard remaining == 0 else {
                apply(before)
                return (nil, "No se pudo completar la salida por lote de \(product.name).")
            }
            lines.append(StoreSaleLine(
                id: UUID(), productID: product.id, productName: product.name,
                quantity: cart[product.id, default: 0], unitPriceCents: product.unitPriceCents,
                unitCostCents: product.unitCostCents, lotAllocations: allocations
            ))
        }
        let sale = StoreSale(
            id: UUID(), folio: "POS-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(4))",
            branchID: branchID, cashierID: actorID, lines: lines, paymentMethod: paymentMethod,
            tenderedCents: paymentMethod == .cash ? cashReceivedCents : total,
            changeCents: paymentMethod == .cash ? cashReceivedCents - total : 0,
            status: .completed, soldAt: Date(), voidReason: ""
        )
        storeSales.append(sale)
        if let error = commit(before, message: "No se pudo guardar la venta.") { return (nil, error) }
        return (sale, nil)
    }

    /// Anula una venta local, registra la devolución al lote original y conserva el folio.
    func voidStoreSale(actorID: UUID, saleID: UUID, reason: String) -> String? {
        guard let saleIndex = storeSales.firstIndex(where: { $0.id == saleID }) else {
            return "No se encontró la venta."
        }
        let sale = storeSales[saleIndex]
        guard sale.status == .completed else { return "La venta ya fue anulada." }
        guard canAccess(branchID: sale.branchID, actorID: actorID, requireBranchManager: true) else {
            return "Solo el gerente asignado puede anular ventas de esta sucursal."
        }
        let cleanReason = InputNormalization.text(reason)
        guard cleanReason.count >= 8, cleanReason.count <= 240 else {
            return "Explica el motivo de la anulación con 8 a 240 caracteres."
        }

        for line in sale.lines {
            guard line.quantity > 0 else {
                return "El detalle de lotes de esta venta está incompleto; no se puede anular automáticamente."
            }
            var allocatedQuantity = 0
            for allocation in line.lotAllocations {
                guard allocation.quantity > 0, allocation.quantity <= 100_000,
                      let lot = lots.first(where: { $0.id == allocation.lotID }),
                      lot.branchID == sale.branchID, lot.productID == line.productID else {
                    return "No se encontró un lote válido para reponer el producto."
                }
                let (nextAllocatedQuantity, allocationOverflow) = allocatedQuantity.addingReportingOverflow(allocation.quantity)
                guard !allocationOverflow else { return "El detalle de lotes de esta venta no es válido." }
                allocatedQuantity = nextAllocatedQuantity
                let (restoredQuantity, overflow) = lot.remainingQuantity.addingReportingOverflow(allocation.quantity)
                guard !overflow, restoredQuantity <= 100_000 else {
                    return "La devolución superaría el límite de existencia del lote."
                }
            }
            guard allocatedQuantity == line.quantity else {
                return "El detalle de lotes de esta venta está incompleto; no se puede anular automáticamente."
            }
        }

        let before = makeSnapshot()
        for line in sale.lines {
            for allocation in line.lotAllocations {
                guard let lotIndex = lots.firstIndex(where: { $0.id == allocation.lotID }) else {
                    apply(before)
                    return "No se encontró un lote válido para reponer el producto."
                }
                lots[lotIndex].remainingQuantity += allocation.quantity
                stockMovements.append(StockMovement(
                    id: UUID(), branchID: sale.branchID, productID: line.productID,
                    lotID: allocation.lotID, kind: .returnToStock,
                    quantityDelta: allocation.quantity, unitCostCents: line.unitCostCents,
                    reference: sale.folio, reason: "Anulación de venta: \(cleanReason)",
                    actorID: actorID, recordedAt: Date()
                ))
            }
        }
        storeSales[saleIndex].status = .voided
        storeSales[saleIndex].voidReason = cleanReason
        return commit(before, message: "No se pudo anular la venta.")
    }

    func createStaffMember(
        actorID: UUID, branchID: UUID, employeeCode: String, fullName: String,
        position: String, phone: String, email: String, hiredAt: Date
    ) -> String? {
        guard canAccess(branchID: branchID, actorID: actorID) else { return "No tienes acceso a esta sucursal." }
        let code = InputNormalization.code(employeeCode)
        let name = InputNormalization.text(fullName)
        let role = InputNormalization.text(position)
        let cleanPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !code.isEmpty, !name.isEmpty, !role.isEmpty else { return "Completa código, nombre y cargo." }
        guard code.count <= 24, name.count <= 90, role.count <= 50,
              cleanPhone.count <= 24, cleanEmail.count <= 254 else { return "Revisa la longitud de los datos del colaborador." }
        guard Self.validPhone(cleanPhone), InputNormalization.validEmail(cleanEmail) else { return "Revisa el teléfono o el correo." }
        guard Calendar.current.startOfDay(for: hiredAt) <= Calendar.current.startOfDay(for: Date()) else { return "La fecha de ingreso no puede ser futura." }
        guard !staff.contains(where: { $0.branchID == branchID && $0.employeeCode.caseInsensitiveCompare(code) == .orderedSame }) else {
            return "Ese código ya está asignado a una persona de esta sucursal."
        }
        let before = makeSnapshot()
        staff.append(StaffMember(
            id: UUID(), employeeCode: code, branchID: branchID, fullName: name,
            position: role, phone: cleanPhone, email: cleanEmail, hiredAt: hiredAt, status: .active
        ))
        return commit(before, message: "No se pudo guardar el perfil del colaborador.")
    }

    func updateStaffMember(_ member: StaffMember, actorID: UUID) -> String? {
        guard canAccess(branchID: member.branchID, actorID: actorID) else { return "No tienes acceso a esta sucursal." }
        guard let index = staff.firstIndex(where: { $0.id == member.id }) else { return "No se encontró el perfil del colaborador." }
        let code = InputNormalization.code(member.employeeCode)
        let name = InputNormalization.text(member.fullName)
        let role = InputNormalization.text(member.position)
        let cleanPhone = member.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = member.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !code.isEmpty, !name.isEmpty, !role.isEmpty,
              Self.validPhone(cleanPhone), InputNormalization.validEmail(cleanEmail) else {
            return "Revisa código, nombre, cargo, teléfono y correo."
        }
        guard code.count <= 24, name.count <= 90, role.count <= 50,
              cleanPhone.count <= 24, cleanEmail.count <= 254 else {
            return "Revisa la longitud de los datos del colaborador."
        }
        guard !staff.contains(where: { $0.id != member.id && $0.branchID == member.branchID && $0.employeeCode.caseInsensitiveCompare(code) == .orderedSame }) else {
            return "Ese código ya está asignado a otra persona de la sucursal."
        }
        guard Calendar.current.startOfDay(for: member.hiredAt) <= Calendar.current.startOfDay(for: Date()) else { return "La fecha de ingreso no puede ser futura." }
        let before = makeSnapshot()
        staff[index] = StaffMember(
            id: member.id, employeeCode: code, branchID: member.branchID, fullName: name,
            position: role, phone: cleanPhone, email: cleanEmail, hiredAt: member.hiredAt, status: member.status
        )
        return commit(before, message: "No se pudo actualizar el perfil del colaborador.")
    }

    func setStaffStatus(id: UUID, status: StaffStatus, actorID: UUID) -> String? {
        guard let index = staff.firstIndex(where: { $0.id == id }) else { return "No se encontró el perfil del colaborador." }
        guard canAccess(branchID: staff[index].branchID, actorID: actorID) else { return "No tienes acceso a esta sucursal." }
        let before = makeSnapshot()
        staff[index].status = status
        if status == .inactive { shiftAssignments.removeAll { $0.employeeID == id } }
        return commit(before, message: "No se pudo actualizar el estado del colaborador.")
    }

    func assignShift(actorID: UUID, branchID: UUID, employeeID: UUID, weekday: Int, shift: WorkShift) -> String? {
        guard canAccess(branchID: branchID, actorID: actorID) else { return "No tienes acceso a esta sucursal." }
        guard (1...7).contains(weekday),
              let member = staff.first(where: { $0.id == employeeID && $0.branchID == branchID && $0.status == .active }) else {
            return "Selecciona un colaborador activo y un día válido."
        }
        guard !shiftAssignments.contains(where: { $0.employeeID == employeeID && $0.weekday == weekday }) else {
            return "Ese colaborador ya tiene un turno asignado para ese día."
        }
        _ = member
        let before = makeSnapshot()
        shiftAssignments.append(ShiftAssignment(id: UUID(), branchID: branchID, employeeID: employeeID, weekday: weekday, shift: shift))
        return commit(before, message: "No se pudo guardar el turno.")
    }

    func removeShift(id: UUID, actorID: UUID) -> String? {
        guard let assignment = shiftAssignments.first(where: { $0.id == id }) else { return "No se encontró el turno." }
        guard canAccess(branchID: assignment.branchID, actorID: actorID) else { return "No tienes acceso a esta sucursal." }
        let before = makeSnapshot()
        shiftAssignments.removeAll { $0.id == id }
        return commit(before, message: "No se pudo eliminar el turno.")
    }

    func createEquipment(
        actorID: UUID, branchID: UUID, assetCode: String, name: String,
        category: EquipmentCategory, serialNumber: String
    ) -> String? {
        guard canAccess(branchID: branchID, actorID: actorID) else { return "No tienes acceso a esta sucursal." }
        guard category != .pump && category != .tank else { return "Las seis bombas y los tanques configurados no se crean desde este formulario." }
        let code = InputNormalization.code(assetCode)
        let cleanName = InputNormalization.text(name)
        guard !code.isEmpty, !cleanName.isEmpty else { return "Completa código de activo y nombre." }
        guard !equipment.contains(where: { $0.branchID == branchID && $0.assetCode.caseInsensitiveCompare(code) == .orderedSame }) else {
            return "Ya existe un activo con ese código en la sucursal."
        }
        let before = makeSnapshot()
        equipment.append(StationEquipment(
            id: UUID(), branchID: branchID, assetCode: code, name: cleanName,
            category: category, serialNumber: InputNormalization.text(serialNumber), status: .operational, installedAt: Date()
        ))
        return commit(before, message: "No se pudo guardar el activo.")
    }

    func updateEquipmentStatus(id: UUID, status: EquipmentStatus, actorID: UUID) -> String? {
        guard let index = equipment.firstIndex(where: { $0.id == id }) else { return "No se encontró el activo." }
        guard canAccess(branchID: equipment[index].branchID, actorID: actorID) else { return "No tienes acceso a esta sucursal." }
        let equipmentID = equipment[index].id
        let hasOpenOrder = maintenanceOrders.contains {
            $0.equipmentID == equipmentID && ($0.status == .open || $0.status == .inProgress)
        }
        guard status != .operational || !hasOpenOrder else {
            return "Completa o cancela las órdenes abiertas antes de marcar el activo como operativo."
        }
        let before = makeSnapshot()
        equipment[index].status = status
        return commit(before, message: "No se pudo actualizar el estado del activo.")
    }

    func updateEquipmentDetails(
        id: UUID, assetCode: String, name: String, serialNumber: String, actorID: UUID
    ) -> String? {
        guard let index = equipment.firstIndex(where: { $0.id == id }) else { return "No se encontró el activo." }
        let current = equipment[index]
        guard canAccess(branchID: current.branchID, actorID: actorID) else { return "No tienes acceso a esta sucursal." }
        let cleanCode = InputNormalization.code(assetCode)
        let cleanName = InputNormalization.text(name)
        let cleanSerial = InputNormalization.text(serialNumber)
        guard !cleanCode.isEmpty, !cleanName.isEmpty,
              cleanCode.count <= 32, cleanName.count <= 90, cleanSerial.count <= 80 else {
            return "Completa código y nombre; revisa la longitud de los datos."
        }
        guard !equipment.contains(where: {
            $0.id != id && $0.branchID == current.branchID
                && $0.assetCode.caseInsensitiveCompare(cleanCode) == .orderedSame
        }) else { return "Ya existe un activo con ese código en la sucursal." }

        let before = makeSnapshot()
        equipment[index].assetCode = cleanCode
        equipment[index].name = cleanName
        equipment[index].serialNumber = cleanSerial
        return commit(before, message: "No se pudo guardar la ficha del activo.")
    }

    func openMaintenanceOrder(
        actorID: UUID, branchID: UUID, equipmentID: UUID, title: String,
        description: String, priority: MaintenancePriority, providerName: String
    ) -> String? {
        guard canAccess(branchID: branchID, actorID: actorID) else { return "No tienes acceso a esta sucursal." }
        let cleanTitle = InputNormalization.text(title)
        let cleanDescription = InputNormalization.text(description)
        guard let equipmentIndex = equipment.firstIndex(where: { $0.id == equipmentID && $0.branchID == branchID }) else {
            return "Selecciona un activo de la sucursal."
        }
        guard !cleanTitle.isEmpty, cleanDescription.count >= 8 else { return "Ingresa un título y describe el problema con al menos 8 caracteres." }
        let before = makeSnapshot()
        let order = MaintenanceOrder(
            id: UUID(), branchID: branchID, equipmentID: equipmentID,
            title: cleanTitle, description: cleanDescription, priority: priority,
            status: .open, openedAt: Date(), completedAt: nil,
            providerName: InputNormalization.text(providerName), costCents: 0
        )
        maintenanceOrders.append(order)
        equipment[equipmentIndex].status = .maintenance
        return commit(before, message: "No se pudo registrar la orden de mantenimiento.")
    }

    func updateMaintenanceOrder(
        id: UUID, status: MaintenanceStatus, providerName: String,
        costCents: Int, actorID: UUID
    ) -> String? {
        guard let orderIndex = maintenanceOrders.firstIndex(where: { $0.id == id }) else { return "No se encontró la orden." }
        let order = maintenanceOrders[orderIndex]
        guard canAccess(branchID: order.branchID, actorID: actorID) else { return "No tienes acceso a esta sucursal." }
        guard costCents >= 0, costCents <= 100_000_000 else { return "Ingresa un costo válido." }
        guard status != .completed || order.status != .cancelled else { return "Una orden cancelada no puede marcarse como completada." }
        let before = makeSnapshot()
        maintenanceOrders[orderIndex].status = status
        maintenanceOrders[orderIndex].providerName = InputNormalization.text(providerName)
        maintenanceOrders[orderIndex].costCents = costCents
        maintenanceOrders[orderIndex].completedAt = (status == .completed || status == .cancelled) ? Date() : nil
        if let equipmentIndex = equipment.firstIndex(where: { $0.id == order.equipmentID }) {
            let otherOpen = maintenanceOrders.contains(where: {
                $0.id != id && $0.equipmentID == order.equipmentID && ($0.status == .open || $0.status == .inProgress)
            })
            if status == .open || status == .inProgress || otherOpen {
                equipment[equipmentIndex].status = .maintenance
            } else if equipment[equipmentIndex].status == .maintenance {
                equipment[equipmentIndex].status = .operational
            }
        }
        return commit(before, message: "No se pudo actualizar la orden de mantenimiento.")
    }

    private static func validPhone(_ value: String) -> Bool {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return true }
        let digits = clean.filter(\.isNumber)
        return (8...15).contains(digits.count) && clean.allSatisfy { $0.isNumber || "+-() ".contains($0) }
    }

    private func seedOperationsData() {
        suppliers = [
            StoreSupplier(id: UUID(), name: "Distribuidora Central", taxIdentifier: "", contactName: "Ana Ruiz", phone: "2222-0101", email: "ventas@central.example", address: "San Salvador", scope: .store, isActive: true),
            StoreSupplier(id: UUID(), name: "Abastecimientos DLC", taxIdentifier: "", contactName: "Carlos Mejía", phone: "2222-0202", email: "pedidos@dlc.example", address: "Santa Ana", scope: .both, isActive: true)
        ]
        let beverages = StoreProduct(id: UUID(), sku: "BEB-AGUA-600", barcode: "7410000000011", name: "Agua 600 ml", brand: "DLC demo", category: .beverages, unitName: "unidad", unitCostCents: 40, unitPriceCents: 75, minimumStock: 12, isActive: true)
        let snack = StoreProduct(id: UUID(), sku: "SNK-CHIPS-001", barcode: "7410000000028", name: "Snack salado", brand: "DLC demo", category: .snacks, unitName: "bolsa", unitCostCents: 65, unitPriceCents: 100, minimumStock: 10, isActive: true)
        let oil = StoreProduct(id: UUID(), sku: "AUT-LUB-1L", barcode: "7410000000035", name: "Lubricante 1 L", brand: "DLC demo", category: .lubricants, unitName: "botella", unitCostCents: 425, unitPriceCents: 575, minimumStock: 4, isActive: true)
        products = [beverages, snack, oil]

        let lead = users.first(where: { $0.role == .branchManager })
        staff = branches.flatMap { branch in
            [
                StaffMember(id: UUID(), employeeCode: "EMP-\(branch.code)-01", branchID: branch.id, fullName: "María Operadora", position: "Atención de pista", phone: "7000-1101", email: "", hiredAt: Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date(), status: .active),
                StaffMember(id: UUID(), employeeCode: "EMP-\(branch.code)-02", branchID: branch.id, fullName: "José Cajero", position: "Cajero de tienda", phone: "7000-1102", email: "", hiredAt: Calendar.current.date(byAdding: .month, value: -8, to: Date()) ?? Date(), status: .active)
            ]
        }
        if let lead, let branchID = lead.branchID, let employee = staff.first(where: { $0.branchID == branchID }) {
            shiftAssignments = [
                ShiftAssignment(id: UUID(), branchID: branchID, employeeID: employee.id, weekday: Calendar.current.component(.weekday, from: Date()), shift: .morning)
            ]
        }

        for branch in branches {
            let branchEquipment = (1...6).map { number in
                StationEquipment(id: UUID(), branchID: branch.id, assetCode: "BOM-\(branch.code)-\(number)", name: "Bomba \(number)", category: .pump, serialNumber: "", status: .operational, installedAt: nil)
            } + branch.tanks.enumerated().map { index, tank in
                StationEquipment(id: UUID(), branchID: branch.id, assetCode: "TNQ-\(branch.code)-\(index + 1)", name: "Tanque \(tank.type.rawValue)", category: .tank, serialNumber: "", status: .operational, installedAt: nil)
            } + [
                StationEquipment(id: UUID(), branchID: branch.id, assetCode: "POS-\(branch.code)-01", name: "Terminal de tienda", category: .pointOfSale, serialNumber: "", status: .operational, installedAt: nil),
                StationEquipment(id: UUID(), branchID: branch.id, assetCode: "REF-\(branch.code)-01", name: "Refrigerador principal", category: .refrigeration, serialNumber: "", status: .operational, installedAt: nil)
            ]
            equipment.append(contentsOf: branchEquipment)
        }

        for branch in branches {
            guard let supplier = suppliers.first(where: { $0.supportsStore }) else { continue }
            for product in products {
                let quantity: Int = product.category == .lubricants ? 8 : (product.category == .beverages ? 24 : 15)
                let lot = StoreLot(
                    id: UUID(), branchID: branch.id, productID: product.id, supplierID: supplier.id,
                    lotCode: "INI-\(branch.code)-\(product.sku)", documentReference: "INV-INICIAL",
                    receivedAt: Date(), expiresAt: product.category == .lubricants ? nil : Calendar.current.date(byAdding: .month, value: 8, to: Date()),
                    receivedQuantity: quantity, remainingQuantity: quantity, unitCostCents: product.unitCostCents
                )
                lots.append(lot)
                if let actorID = users.first(where: { $0.role == .generalManager })?.id {
                    stockMovements.append(StockMovement(id: UUID(), branchID: branch.id, productID: product.id, lotID: lot.id, kind: .receipt, quantityDelta: quantity, unitCostCents: product.unitCostCents, reference: "INV-INICIAL", reason: "Existencia inicial de demostración", actorID: actorID, recordedAt: Date()))
                }
            }
        }
        _ = lead
    }
}
