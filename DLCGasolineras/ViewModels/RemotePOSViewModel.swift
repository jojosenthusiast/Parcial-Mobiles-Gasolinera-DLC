import Combine
import Foundation

struct RemotePOSCartLine: Identifiable {
    var id: UUID { product.id }
    let product: RemotePOSProduct
    var quantity: String
}
enum RemotePOSCommand: Codable {
    case offer(RemotePOSOfferBody)
    case receipt(RemotePOSReceiptBody)
    case sale(RemotePOSSaleBody)
    var id: UUID {
        switch self { case .offer(let b): return b.commandId; case .receipt(let b): return b.commandId; case .sale(let b): return b.commandId }
    }
    var title: String {
        switch self { case .offer: return "Publicación de catálogo"; case .receipt: return "Recepción de lote"; case .sale: return "Venta de tienda o servicios" }
    }
}

@MainActor
final class RemotePOSViewModel: ObservableObject {
    @Published var query = ""
    @Published var kind = "all"
    @Published var includeInactive = false
    @Published var basket: [RemotePOSCartLine] = []
    @Published private(set) var products: [RemotePOSProduct] = []
    @Published private(set) var nextCursor: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isPosting = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var pending: [RemoteDraft] = []
    @Published private(set) var recoveryError = ""
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastSale: RemoteFuelSale?
    @Published private(set) var notice = ""
    let repository: RemotePumpRepository
    let branchID: UUID
    private let store: RemoteOfflineStore
    private let scope: RemoteDataScope
    private var generation = 0
    var canStartCommand: Bool { !isPosting && pending.isEmpty && recoveryError.isEmpty }

    init(repository: RemotePumpRepository, store: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID) {
        self.repository = repository; self.store = store; self.scope = scope; self.branchID = branchID
        refreshPending()
    }
    func refreshPending() {
        do {
            let drafts = try store.checkedDrafts(scope: scope).filter { $0.resource == "pos-command" }
            for draft in drafts {
                let command = try JSONDecoder().decode(RemotePOSCommand.self, from: draft.payload)
                guard command.id == draft.id else { throw RemoteAPIError.malformedResponse }
            }
            pending = drafts; recoveryError = ""
        } catch {
            recoveryError = "No se pudieron leer las operaciones guardadas. Se bloquean nuevas operaciones para evitar duplicados."
        }
    }
    func load(more: Bool = false) async {
        if more && (isLoading || nextCursor == nil) { return }
        generation += 1; let current = generation
        let requestedQuery = query, requestedKind = kind, inactive = includeInactive
        let cursor = more ? nextCursor : nil
        isLoading = true; errorMessage = ""
        if !more { products = []; nextCursor = nil; lastUpdated = nil }
        defer { if current == generation { isLoading = false } }
        do {
            let page = try await repository.posCatalog(branchId: branchID, query: requestedQuery, kind: requestedKind == "all" ? nil : requestedKind, cursor: cursor, includeInactive: inactive)
            guard generation == current else { return }
            products = more ? products + page.data.filter { p in !products.contains { $0.id == p.id } } : page.data
            nextCursor = page.meta.nextCursor; lastUpdated = Date()
        } catch { if generation == current { errorMessage = error.localizedDescription } }
    }
    func add(_ product: RemotePOSProduct) {
        guard canStartCommand, product.active else { return }
        if let index = basket.firstIndex(where: { $0.id == product.id }) {
            guard basket[index].product.offerVersionId == product.offerVersionId else {
                errorMessage = "El precio cambió. Quita la línea anterior y agrega el producto con su precio actualizado."; return
            }
            let previous = Decimal(string: basket[index].quantity) ?? 0
            basket[index].quantity = NSDecimalNumber(decimal: previous + 1).stringValue
        } else if basket.count < 50 { basket.append(RemotePOSCartLine(product: product, quantity: "1")) }
        else { errorMessage = "El comprobante admite hasta 50 productos distintos." }
    }
    func submitBasket() async -> Bool {
        guard canStartCommand, !basket.isEmpty else { return false }
        var items: [RemotePOSSaleBody.Item] = []
        for line in basket {
            guard let quantity = posDecimal(line.quantity, precision: 3, positive: true),
                  line.product.kind != "store" || !quantity.contains(".") else {
                errorMessage = "Usa cantidades positivas; los productos de tienda se venden en unidades completas."; return false
            }
            items.append(.init(productId: line.id, offerVersionId: line.product.offerVersionId, quantity: quantity))
        }
        return await perform(.sale(RemotePOSSaleBody(commandId: UUID(), items: items)))
    }
    func perform(_ command: RemotePOSCommand) async -> Bool {
        guard canStartCommand else { return false }
        do {
            let draft = RemoteDraft(scope: scope, resource: "pos-command", payload: try JSONEncoder().encode(command), id: command.id)
            try store.saveDraft(draft) // Persist before sending, including when the response may be lost.
            refreshPending()
            guard recoveryError.isEmpty else { return false }
            return await execute(command)
        } catch { errorMessage = "No se pudo guardar la operación; no se envió al servidor."; return false }
    }
    func retry(_ draft: RemoteDraft) async {
        guard !isPosting, recoveryError.isEmpty else { return }
        do { _ = await execute(try JSONDecoder().decode(RemotePOSCommand.self, from: draft.payload)) }
        catch { recoveryError = "La operación guardada no se puede interpretar. No se enviaron cambios." }
    }
    private func execute(_ command: RemotePOSCommand) async -> Bool {
        guard !isPosting else { return false }
        isPosting = true; errorMessage = ""; notice = ""
        defer { isPosting = false }
        do {
            switch command {
            case .offer(let body): _ = try await repository.publishPOSOffer(branchId: branchID, body: body); notice = "Catálogo actualizado."
            case .receipt(let body): _ = try await repository.receivePOSLot(branchId: branchID, body: body); notice = "Recepción registrada."
            case .sale(let body): lastSale = try await repository.createPOSSale(branchId: branchID, body: body); basket = []; notice = "Venta registrada; pendiente de cobro."
            }
            try store.removeDraft(id: command.id, scope: scope)
            refreshPending(); await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            // Transport/5xx/403 may follow a committed sale whose detail could not be returned.
            // Keep its exact body and command until an explicit retry obtains the result.
            if case RemoteAPIError.http(let status, _, _, _) = error, [400, 404, 409, 422].contains(status) {
                do { try store.removeDraft(id: command.id, scope: scope); refreshPending() }
                catch { recoveryError = "No se pudo actualizar el registro de operaciones guardadas." }
            }
            return false
        }
    }
    var estimatedTotal: String {
        let total = basket.reduce(Decimal.zero) { result, line in
            guard let quantity = Decimal(string: posDecimal(line.quantity, precision: 3, positive: true) ?? ""), let price = Decimal(string: line.product.priceUsd) else { return result }
            var value = quantity * price, rounded = Decimal()
            NSDecimalRound(&rounded, &value, 2, .plain)
            return result + rounded
        }
        return NSDecimalNumber(decimal: total).stringValue
    }
}

@MainActor
final class RemotePOSLotsViewModel: ObservableObject {
    @Published private(set) var product: RemotePOSProduct?
    @Published private(set) var lots: [RemotePOSLot] = []
    @Published private(set) var nextCursor: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage = ""
    private let repository: RemotePumpRepository
    private let branchID: UUID
    private let productID: UUID
    init(repository: RemotePumpRepository, branchID: UUID, productID: UUID) { self.repository = repository; self.branchID = branchID; self.productID = productID }
    func load(more: Bool = false) async {
        guard !isLoading, !more || nextCursor != nil else { return }
        isLoading = true; errorMessage = ""; defer { isLoading = false }
        do {
            product = try await repository.posProduct(branchId: branchID, productId: productID)
            guard product?.kind == "store" else { lots = []; nextCursor = nil; return }
            let page = try await repository.posLots(branchId: branchID, productId: productID, cursor: more ? nextCursor : nil)
            lots = more ? lots + page.data.filter { l in !lots.contains { $0.id == l.id } } : page.data
            nextCursor = page.meta.nextCursor
        } catch { errorMessage = error.localizedDescription }
    }
}

func posDecimal(_ raw: String, precision: Int, positive: Bool) -> String? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    guard value.range(of: "^(0|[1-9][0-9]{0,8})(\\.[0-9]{1,\(precision)})?$", options: .regularExpression) != nil,
          let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), !positive || decimal > 0 else { return nil }
    return NSDecimalNumber(decimal: decimal).stringValue
}

@MainActor
final class RemoteCombinedReceiptViewModel: ObservableObject {
    @Published private(set) var candidates: [RemoteFuelSaleSummary] = []
    @Published private(set) var nextCursor: String?
    @Published private(set) var receipt: RemoteCombinedInternalReceipt?
    @Published private(set) var isLoading = false
    @Published private(set) var isPosting = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var recoveryError = ""
    @Published private(set) var notice = ""
    @Published private(set) var pending: [RemoteDraft] = []

    private let repository: RemotePumpRepository
    private let store: RemoteOfflineStore?
    private let scope: RemoteDataScope?
    private let branchID: UUID
    private let fuelSaleID: UUID
    private var generation = 0
    var canStartCommand: Bool { store != nil && scope != nil && !isPosting && pending.isEmpty && recoveryError.isEmpty && receipt == nil }

    init(repository: RemotePumpRepository, store: RemoteOfflineStore?, scope: RemoteDataScope?, branchID: UUID, fuelSaleID: UUID) {
        self.repository = repository; self.store = store; self.scope = scope; self.branchID = branchID; self.fuelSaleID = fuelSaleID
        refreshPending()
    }

    func refreshPending() {
        guard let store, let scope else { pending = []; recoveryError = ""; return }
        do {
            let drafts = try store.checkedDrafts(scope: scope).filter { $0.resource == "combined-receipt-command" }
            var matching: [RemoteDraft] = []
            for draft in drafts {
                let body = try JSONDecoder().decode(RemoteCombinedReceiptBody.self, from: draft.payload)
                guard body.commandId == draft.id else { throw RemoteAPIError.malformedResponse }
                if body.fuelSaleId == fuelSaleID { matching.append(draft) }
            }
            pending = matching; recoveryError = ""
        } catch {
            recoveryError = "No se pudieron validar los comprobantes pendientes. Se bloquean nuevos intentos para evitar duplicados."
        }
    }

    func load(more: Bool = false) async {
        guard !isLoading, !more || nextCursor != nil else { return }
        generation += 1; let current = generation
        isLoading = true; errorMessage = ""
        if !more { candidates = []; nextCursor = nil; receipt = nil }
        defer { if current == generation { isLoading = false } }
        do {
            if !more { receipt = try await repository.combinedReceipt(branchId: branchID, saleId: fuelSaleID) }
            if receipt == nil {
                let page = try await repository.fuelSales(branchId: branchID, query: nil, cursor: more ? nextCursor : nil)
                guard current == generation else { return }
                let selectable = page.data.filter { $0.id != fuelSaleID && $0.authorizationId == nil && $0.status == "pending_collection" }
                candidates = more ? candidates + selectable.filter { item in !candidates.contains { $0.id == item.id } } : selectable
                nextCursor = page.meta.nextCursor
            }
        } catch {
            if current == generation { errorMessage = error.localizedDescription }
        }
    }

    func create(posSaleID: UUID) async -> Bool {
        guard let store, let scope, canStartCommand, posSaleID != fuelSaleID, candidates.contains(where: { $0.id == posSaleID }) else { return false }
        let body = RemoteCombinedReceiptBody(commandId: UUID(), fuelSaleId: fuelSaleID, posSaleId: posSaleID)
        do {
            try store.saveDraft(RemoteDraft(scope: scope, resource: "combined-receipt-command", payload: try JSONEncoder().encode(body), id: body.commandId))
            refreshPending()
            guard recoveryError.isEmpty else { return false }
            return await execute(body)
        } catch {
            errorMessage = "No se pudo guardar la operación; no se envió al servidor."
            return false
        }
    }

    func retry(_ draft: RemoteDraft) async {
        guard store != nil, scope != nil, !isPosting, recoveryError.isEmpty else { return }
        do {
            let body = try JSONDecoder().decode(RemoteCombinedReceiptBody.self, from: draft.payload)
            guard body.commandId == draft.id, body.fuelSaleId == fuelSaleID else { throw RemoteAPIError.malformedResponse }
            _ = await execute(body)
        } catch {
            recoveryError = "El comprobante pendiente no coincide con esta venta. No se enviaron cambios."
        }
    }

    private func execute(_ body: RemoteCombinedReceiptBody) async -> Bool {
        guard let store, let scope, !isPosting else { return false }
        isPosting = true; errorMessage = ""; notice = ""
        defer { isPosting = false }
        do {
            receipt = try await repository.createCombinedReceipt(branchId: branchID, body: body)
            try store.removeDraft(id: body.commandId, scope: scope)
            refreshPending(); notice = "Comprobante interno consolidado. Los cobros y datos fiscales siguen separados por venta."
            return true
        } catch {
            errorMessage = error.localizedDescription
            if case RemoteAPIError.http(let status, _, _, _) = error, [400, 404, 409, 422].contains(status) {
                do { try store.removeDraft(id: body.commandId, scope: scope); refreshPending() }
                catch { recoveryError = "No se pudo actualizar el registro de comprobantes pendientes." }
            }
            return false
        }
    }
}

@MainActor
final class RemoteCashViewModel: ObservableObject {
    @Published private(set) var registers: [RemoteCashRegister] = []
    @Published private(set) var session: RemoteCashSession?
    @Published private(set) var movements: [RemoteCashMovement] = []
    @Published private(set) var nextCursor: RemoteCashMovementCursor?
    @Published private(set) var review: RemoteCashReview?
    @Published var movementFilter = "all"
    @Published var reviewFilter = "all"
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMovements = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isPosting = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var reviewError = ""
    @Published private(set) var reviewListError = ""
    @Published private(set) var reviews: [RemoteCashReview] = []
    @Published private(set) var notice = ""
    @Published private(set) var pending: [RemoteDraft] = []
    @Published private(set) var pendingReviewCommands: [RemoteCashApprovalCommand] = []
    @Published private(set) var recoveryError = ""

    let client: RemoteAPIClient
    let store: RemoteOfflineStore
    let scope: RemoteDataScope
    let branchID: UUID
    let sessionID: UUID?
    private var generation = 0
    private var movementGeneration = 0
    private var reviewListGeneration = 0

    var canStartCommand: Bool { !isPosting && pending.isEmpty && recoveryError.isEmpty }

    init(client: RemoteAPIClient, store: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID, sessionID: UUID? = nil) {
        self.client = client
        self.store = store
        self.scope = scope
        self.branchID = branchID
        self.sessionID = sessionID
        refreshPending()
    }

    func refreshPending() {
        do {
            let drafts = try store.checkedDrafts(scope: scope)
            let cashDrafts = drafts.filter { $0.resource == "cash-command" }
            for draft in cashDrafts {
                let command = try JSONDecoder().decode(RemoteCashCommand.self, from: draft.payload)
                guard command.id == draft.id else { throw RemoteAPIError.malformedResponse }
            }
            let reviewDrafts = drafts.filter { $0.resource == "cash-review-command" }
            let commands = try reviewDrafts.map { draft -> RemoteCashApprovalCommand in
                let command = try JSONDecoder().decode(RemoteCashApprovalCommand.self, from: draft.payload)
                guard command.id == draft.id,
                      ["approved", "rejected"].contains(command.decision),
                      (3...1000).contains(command.reason.count) else { throw RemoteAPIError.malformedResponse }
                return command
            }
            pending = cashDrafts
            pendingReviewCommands = commands
            recoveryError = ""
        } catch {
            recoveryError = "No se pudieron leer comandos pendientes de caja o aprobación. Se bloquean cambios para evitar duplicados."
        }
    }

    func load() async {
        guard !isLoading else { return }
        generation += 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = ""
        defer { if requestGeneration == generation { isLoading = false } }
        do {
            if let sessionID {
                let loadedSession = try await client.cashSession(branchId: branchID, sessionID: sessionID)
                guard generation == requestGeneration else { return }
                session = loadedSession
                await loadMovements(more: false)
                if loadedSession.closureId != nil {
                    do {
                        review = try await client.cashReview(branchId: branchID, sessionID: sessionID)
                        reviewError = ""
                    } catch {
                        reviewError = error.localizedDescription
                    }
                } else {
                    review = nil
                    reviewError = ""
                }
            } else {
                registers = try await client.cashRegisters(branchId: branchID)
                await loadReviews()
            }
        } catch {
            if generation == requestGeneration { errorMessage = error.localizedDescription }
        }
    }

    func loadReviews() async {
        guard sessionID == nil else { return }
        reviewListGeneration += 1
        let requestGeneration = reviewListGeneration
        let status = reviewFilter == "all" ? nil : reviewFilter
        reviewListError = ""
        do {
            let loaded = try await client.cashReviews(branchId: branchID, status: status)
            guard requestGeneration == reviewListGeneration else { return }
            reviews = loaded
        } catch {
            if requestGeneration == reviewListGeneration { reviewListError = error.localizedDescription }
        }
    }

    func loadMovements(more: Bool) async {
        guard let sessionID else { return }
        if more && (isLoadingMore || nextCursor == nil) { return }
        if more {
            isLoadingMore = true
        } else {
            movementGeneration += 1
            isLoadingMovements = true
            movements = []
            nextCursor = nil
            errorMessage = ""
        }
        let requestGeneration = movementGeneration
        let requestedKind = movementFilter == "all" ? nil : movementFilter
        defer {
            if more { isLoadingMore = false }
            else if requestGeneration == movementGeneration { isLoadingMovements = false }
        }
        do {
            let page = try await client.cashMovements(
                branchId: branchID,
                sessionID: sessionID,
                kind: requestedKind,
                cursor: more ? nextCursor : nil,
                limit: 30
            )
            guard requestGeneration == movementGeneration else { return }
            movements = more ? movements + page.data.filter { item in !movements.contains(where: { $0.id == item.id }) } : page.data
            nextCursor = page.nextCursor
        } catch {
            if requestGeneration == movementGeneration { errorMessage = error.localizedDescription }
        }
    }

    func createRegister(code rawCode: String) async -> Bool {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.range(of: "^[A-Z0-9_-]{1,30}$", options: .regularExpression) != nil else {
            errorMessage = "Usa de 1 a 30 letras, números, guiones o guiones bajos para el código."
            return false
        }
        return await perform(.createRegister(RemoteCashRegisterBody(commandId: UUID(), code: code)))
    }

    func openRegister(_ registerID: UUID, opening rawOpening: String) async -> Bool {
        guard let amount = cashMoney(rawOpening, positive: false) else {
            errorMessage = "El fondo inicial debe ser un importe válido de hasta dos decimales."
            return false
        }
        return await perform(.open(RemoteCashOpenBody(commandId: UUID(), registerId: registerID, openingUsd: amount)))
    }

    func recordMovement(sessionID: UUID, kind: String, amount rawAmount: String, reason rawReason: String) async -> Bool {
        guard ["cash_in", "withdrawal", "deposit"].contains(kind),
              let amount = cashMoney(rawAmount, positive: true) else {
            errorMessage = "El movimiento debe tener un importe positivo válido."
            return false
        }
        let reason = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...300).contains(reason.count) else {
            errorMessage = "Describe el motivo en 3 a 300 caracteres."
            return false
        }
        let body = RemoteCashMovementBody(commandId: UUID(), kind: kind, amountUsd: amount, reason: reason)
        return await perform(.movement(sessionID: sessionID, body: body))
    }

    func closeSession(sessionID: UUID, countedCash rawCash: String, settledCard rawCard: String, reason rawReason: String) async -> Bool {
        guard let cash = cashMoney(rawCash, positive: false), let card = cashMoney(rawCard, positive: false, signed: true) else {
            errorMessage = "Revisa el efectivo contado y el neto liquidado de tarjeta; usa hasta dos decimales."
            return false
        }
        let reason = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count <= 300 else { errorMessage = "La observación admite hasta 300 caracteres."; return false }
        let body = RemoteCashCloseBody(commandId: UUID(), countedCashUsd: cash, settledCardUsd: card, reason: reason.isEmpty ? nil : reason)
        return await perform(.close(sessionID: sessionID, body: body))
    }

    func retry(_ draft: RemoteDraft) async {
        guard !isPosting, recoveryError.isEmpty else { return }
        do {
            let command = try JSONDecoder().decode(RemoteCashCommand.self, from: draft.payload)
            guard command.id == draft.id else { throw RemoteAPIError.malformedResponse }
            if await execute(command) { await load() }
        } catch {
            recoveryError = "El comando de caja guardado no se puede recuperar. No se envió ningún cambio."
        }
    }

    func decideVariance(review: RemoteCashReview, decision: String, reason rawReason: String) async -> Bool {
        let reason = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard review.status == "pending", let approvalId = review.approvalId else {
            errorMessage = "Esta diferencia ya no tiene una aprobación pendiente. Actualiza el arqueo."
            return false
        }
        guard review.cashierId != scope.userId else {
            errorMessage = "Quien cerró el turno no puede aprobar su propia diferencia."
            return false
        }
        guard ["approved", "rejected"].contains(decision), (3...1000).contains(reason.count) else {
            errorMessage = "Selecciona aprobar o rechazar y escribe un motivo de 3 a 1,000 caracteres."
            return false
        }
        guard !isPosting, recoveryError.isEmpty,
              !pendingReviewCommands.contains(where: { $0.sessionId == review.sessionId }) else { return false }
        let command = RemoteCashApprovalCommand(
            id: UUID(), approvalId: approvalId, sessionId: review.sessionId,
            decision: decision, reason: reason
        )
        do {
            let draft = RemoteDraft(scope: scope, resource: "cash-review-command", payload: try JSONEncoder().encode(command), id: command.id)
            try store.saveDraft(draft)
            refreshPending()
            guard recoveryError.isEmpty, pendingReviewCommands.contains(where: { $0.id == command.id }) else { return false }
            return await executeVarianceDecision(command)
        } catch {
            errorMessage = "No se pudo guardar la decisión en este dispositivo; no se envió al servidor."
            return false
        }
    }

    func retryVarianceDecision(_ command: RemoteCashApprovalCommand) async {
        guard !isPosting, recoveryError.isEmpty,
              pendingReviewCommands.contains(where: { $0.id == command.id }) else { return }
        await executeVarianceDecision(command)
    }

    private func executeVarianceDecision(_ command: RemoteCashApprovalCommand) async -> Bool {
        guard !isPosting, recoveryError.isEmpty else { return false }
        isPosting = true
        errorMessage = ""
        notice = ""
        defer { isPosting = false }
        var didSendDecision = false
        do {
            let current = try await client.cashReview(branchId: branchID, sessionID: command.sessionId)
            guard current.approvalId == command.approvalId else {
                if current.status != "pending" {
                    try removeReviewCommand(command)
                    notice = "La diferencia ya fue resuelta por otro usuario. Se actualizó el arqueo."
                    await load()
                    return true
                }
                try removeReviewCommand(command)
                errorMessage = "La solicitud cambió. Se descartó la decisión guardada; revisa el arqueo actualizado."
                await load()
                return false
            }
            guard current.status == "pending" else {
                try removeReviewCommand(command)
                notice = "La diferencia ya fue resuelta. Se actualizó el arqueo."
                await load()
                return true
            }
            guard current.cashierId != scope.userId else {
                try removeReviewCommand(command)
                errorMessage = "Quien cerró el turno no puede aprobar su propia diferencia."
                await load()
                return false
            }

            didSendDecision = true
            _ = try await client.decideApproval(
                approvalID: command.approvalId,
                body: RemoteApprovalDecisionBody(branchId: branchID, decision: command.decision, reason: command.reason)
            )
            try removeReviewCommand(command)
            notice = command.decision == "approved" ? "Diferencia aprobada y auditada." : "Diferencia rechazada y auditada."
            await load()
            return true
        } catch {
            let originalMessage = error.localizedDescription
            if let apiError = error as? RemoteAPIError,
               case .http(let status, _, _, _) = apiError,
               [400, 403, 422].contains(status) {
                do {
                    try removeReviewCommand(command)
                    errorMessage = "El servidor rechazó la decisión (HTTP \(status)): \(originalMessage)"
                } catch {
                    recoveryError = "El servidor rechazó la decisión, pero no se pudo limpiar el borrador local. Revisa la solicitud antes de continuar."
                }
                return false
            }

            guard didSendDecision else {
                errorMessage = "No se pudo consultar el estado actual. No se envió la decisión; el borrador conserva el motivo para reintentar."
                return false
            }

            do {
                let current = try await client.cashReview(branchId: branchID, sessionID: command.sessionId)
                if current.status != "pending" || current.approvalId != command.approvalId {
                    try removeReviewCommand(command)
                    notice = "El servidor ya registró una decisión. Se consultó el resultado actualizado."
                    await load()
                    return true
                }
                errorMessage = "No se confirmó la decisión (\(originalMessage)). La solicitud sigue pendiente; puedes consultar y reintentar con el mismo borrador."
            } catch {
                errorMessage = "No se pudo confirmar el resultado de la decisión. El borrador permanece guardado para consultar y reintentar sin perder el motivo."
            }
            return false
        }
    }

    private func removeReviewCommand(_ command: RemoteCashApprovalCommand) throws {
        try store.removeDraft(id: command.id, scope: scope)
        refreshPending()
        guard recoveryError.isEmpty else { throw RemoteAPIError.malformedResponse }
    }

    private func perform(_ command: RemoteCashCommand) async -> Bool {
        guard canStartCommand else { return false }
        do {
            let draft = RemoteDraft(scope: scope, resource: "cash-command", payload: try JSONEncoder().encode(command), id: command.id)
            try store.saveDraft(draft)
            refreshPending()
            guard recoveryError.isEmpty else { return false }
            return await execute(command)
        } catch {
            errorMessage = "No se pudo guardar el comando en este dispositivo; no se envió al servidor."
            return false
        }
    }

    private func execute(_ command: RemoteCashCommand) async -> Bool {
        guard !isPosting else { return false }
        isPosting = true
        errorMessage = ""
        notice = ""
        defer { isPosting = false }
        do {
            switch command {
            case .createRegister(let body):
                _ = try await client.createCashRegister(branchId: branchID, body: body)
                notice = "Caja registrada."
            case .open(let body):
                _ = try await client.openCashSession(branchId: branchID, body: body)
                notice = "Turno de caja abierto."
            case .movement(let sessionID, let body):
                _ = try await client.createCashMovement(branchId: branchID, sessionID: sessionID, body: body)
                notice = "Movimiento agregado al historial de caja."
            case .close(let sessionID, let body):
                let result = try await client.closeCashSession(branchId: branchID, sessionID: sessionID, body: body)
                notice = result.reviewStatus == "balanced"
                    ? "Cierre registrado y conciliado."
                    : "Cierre registrado. La diferencia quedó pendiente de revisión independiente."
            }
            try store.removeDraft(id: command.id, scope: scope)
            refreshPending()
            if case .movement = command { await load() }
            if case .close = command { await load() }
            if case .createRegister = command { await load() }
            if case .open = command { await load() }
            return true
        } catch {
            errorMessage = error.localizedDescription
            if case RemoteAPIError.http(let status, _, _, _) = error, [400, 403, 404, 409, 422].contains(status) {
                do { try store.removeDraft(id: command.id, scope: scope); refreshPending() }
                catch { recoveryError = "No se pudo limpiar el comando rechazado; confirma la operación antes de continuar." }
            }
            return false
        }
    }
}

func cashMoney(_ raw: String, positive: Bool, signed: Bool = false) -> String? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    let pattern = signed
        ? "^-?(0|[1-9][0-9]{0,8})(\\.[0-9]{1,2})?$"
        : "^(0|[1-9][0-9]{0,8})(\\.[0-9]{1,2})?$"
    guard value.range(of: pattern, options: .regularExpression) != nil,
          let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
          !positive || decimal > 0 else { return nil }
    return NSDecimalNumber(decimal: decimal).stringValue
}

@MainActor
final class RemotePaymentViewModel: ObservableObject {
    @Published private(set) var attempts: [RemotePaymentAttempt] = []
    @Published private(set) var registers: [RemoteCashRegister] = []
    @Published var selectedCashSessionID: UUID?
    @Published private(set) var outstandingUsd: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isPosting = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var sessionError = ""
    @Published private(set) var pending: [RemoteDraft] = []
    @Published private(set) var recoveryError = ""
    @Published private(set) var notice = ""

    let client: RemoteAPIClient
    let store: RemoteOfflineStore
    let scope: RemoteDataScope
    let branchID: UUID
    let saleID: UUID
    private(set) var saleStatus: String
    let canReadPayments: Bool
    let canReadCash: Bool
    private var generation = 0
    var openSessions: [RemoteCashRegister] { registers.filter { $0.openSessionId != nil } }
    var canStartCommand: Bool { !isPosting && pending.isEmpty && recoveryError.isEmpty }

    init(client: RemoteAPIClient, store: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID, saleID: UUID,
         saleStatus: String, outstandingUsd: String?, canReadPayments: Bool, canReadCash: Bool) {
        self.client = client
        self.store = store
        self.scope = scope
        self.branchID = branchID
        self.saleID = saleID
        self.saleStatus = saleStatus
        self.outstandingUsd = outstandingUsd
        self.canReadPayments = canReadPayments
        self.canReadCash = canReadCash
        refreshPending()
    }

    func updateSaleState(status: String, outstanding: String?) {
        saleStatus = status
        outstandingUsd = outstanding
    }

    func refreshPending() {
        do {
            let drafts = try store.checkedDrafts(scope: scope).filter { $0.resource == "payment-command" }
            var matching: [RemoteDraft] = []
            for draft in drafts {
                let command = try JSONDecoder().decode(RemotePaymentCommand.self, from: draft.payload)
                guard command.id == draft.id else { throw RemoteAPIError.malformedResponse }
                if command.saleID == saleID { matching.append(draft) }
            }
            pending = matching
            recoveryError = ""
        } catch {
            recoveryError = "No se pudieron leer los pagos guardados. Se bloquean nuevos cobros para evitar duplicados."
        }
    }

    func load() async {
        guard !isLoading else { return }
        generation += 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = ""
        defer { if requestGeneration == generation { isLoading = false } }
        if canReadPayments {
            do {
                let loaded = try await client.paymentsForSale(branchId: branchID, saleID: saleID)
                guard generation == requestGeneration else { return }
                attempts = loaded
            } catch {
                if generation == requestGeneration { errorMessage = error.localizedDescription }
            }
        }
        if canReadCash {
            do {
                let loaded = try await client.cashRegisters(branchId: branchID)
                guard generation == requestGeneration else { return }
                registers = loaded
                let sessions = loaded.compactMap(\.openSessionId)
                if let selectedCashSessionID, sessions.contains(selectedCashSessionID) { return }
                selectedCashSessionID = sessions.first
                sessionError = ""
            } catch {
                if generation == requestGeneration { sessionError = error.localizedDescription }
            }
        }
    }

    func collect(method: String, amount rawAmount: String, outcome: String, evidence rawEvidence: String) async -> Bool {
        guard saleStatus != "on_credit" else {
            errorMessage = "Esta venta está a crédito; el saldo se cobra desde el estado de cuenta comercial."
            return false
        }
        guard method == "cash" || method == "card",
              method == "cash" ? outcome == "confirmed" : ["confirmed", "declined", "unknown"].contains(outcome),
              let cashSessionID = selectedCashSessionID,
              openSessions.contains(where: { $0.openSessionId == cashSessionID }),
              let amount = cashMoney(rawAmount, positive: true) else {
            errorMessage = "Selecciona un turno abierto y un importe positivo válido."
            return false
        }
        guard let outstandingUsd, let due = Decimal(string: outstandingUsd, locale: Locale(identifier: "en_US_POSIX")),
              let requested = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")), requested <= due else {
            errorMessage = "El importe supera el saldo pendiente de la venta. Actualiza el comprobante si ya hubo otro cobro."
            return false
        }
        let evidence = rawEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
        if method == "card" && outcome != "unknown" && !(1...200).contains(evidence.count) {
            errorMessage = "Registra la referencia de aprobación o rechazo del terminal; nunca ingreses datos completos de tarjeta."
            return false
        }
        let body = RemoteCollectPaymentBody(
            commandId: UUID(), saleId: saleID, cashSessionId: cashSessionID,
            method: method, mode: "manual", amountUsd: amount, outcome: outcome,
            evidenceReference: method != "card" || evidence.isEmpty ? nil : evidence
        )
        return await perform(.collect(body))
    }

    func resolve(attemptID: UUID, outcome: String, evidence rawEvidence: String) async -> Bool {
        guard ["confirmed", "declined"].contains(outcome) else { errorMessage = "El resultado no es válido."; return false }
        let evidence = rawEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...200).contains(evidence.count) else { errorMessage = "La referencia de conciliación debe tener de 1 a 200 caracteres."; return false }
        guard attempts.contains(where: { $0.id == attemptID && $0.status == "unknown" }) else {
            errorMessage = "Este intento ya no está pendiente de resolución. Actualiza la venta."
            return false
        }
        return await perform(.resolve(saleID: saleID, attemptID: attemptID, body: RemoteResolvePaymentBody(commandId: UUID(), outcome: outcome, evidenceReference: evidence)))
    }

    func retry(_ draft: RemoteDraft) async -> Bool {
        guard !isPosting, recoveryError.isEmpty else { return false }
        do {
            let command = try JSONDecoder().decode(RemotePaymentCommand.self, from: draft.payload)
            guard command.id == draft.id, command.saleID == saleID else { throw RemoteAPIError.malformedResponse }
            return await execute(command)
        } catch {
            recoveryError = "El pago guardado no se puede recuperar; no se enviaron cambios."
            return false
        }
    }

    private func perform(_ command: RemotePaymentCommand) async -> Bool {
        guard canStartCommand else { return false }
        do {
            let draft = RemoteDraft(scope: scope, resource: "payment-command", payload: try JSONEncoder().encode(command), id: command.id)
            try store.saveDraft(draft)
            refreshPending()
            guard recoveryError.isEmpty else { return false }
            return await execute(command)
        } catch {
            errorMessage = "No se pudo guardar el pago en este dispositivo; no se envió al servidor."
            return false
        }
    }

    private func execute(_ command: RemotePaymentCommand) async -> Bool {
        guard !isPosting else { return false }
        isPosting = true
        errorMessage = ""
        notice = ""
        defer { isPosting = false }
        do {
            switch command {
            case .collect(let body):
                guard body.saleId == saleID else { throw RemoteAPIError.malformedResponse }
                _ = try await client.collectPayment(branchId: branchID, body: body)
                notice = body.outcome == "unknown"
                    ? "El terminal no confirmó el resultado. El importe queda reservado hasta conciliarlo."
                    : body.outcome == "declined" ? "El intento fue rechazado; no se registró como cobro." : "Cobro registrado."
            case .resolve(let commandSaleID, let attemptID, let body):
                guard commandSaleID == saleID else { throw RemoteAPIError.malformedResponse }
                _ = try await client.resolvePayment(branchId: branchID, attemptID: attemptID, body: body)
                notice = body.outcome == "confirmed" ? "Pago confirmado con referencia." : "Pago marcado como rechazado con referencia."
            }
            try store.removeDraft(id: command.id, scope: scope)
            refreshPending()
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            if case RemoteAPIError.http(let status, _, _, _) = error, [400, 403, 404, 409, 422].contains(status) {
                do { try store.removeDraft(id: command.id, scope: scope); refreshPending() }
                catch { recoveryError = "No se pudo limpiar el comando rechazado. Actualiza el estado antes de intentar otro pago." }
            }
            return false
        }
    }
}

@MainActor
final class RemoteRefundViewModel: ObservableObject {
    @Published private(set) var requests: [RemoteRefundRequest] = []
    @Published private(set) var attempts: [RemotePaymentAttempt] = []
    @Published private(set) var registers: [RemoteCashRegister] = []
    @Published var selectedCashSessionID: UUID?
    @Published private(set) var pending: [RemoteDraft] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPosting = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var notice = ""
    @Published private(set) var recoveryError = ""

    let client: RemoteAPIClient
    let store: RemoteOfflineStore
    let scope: RemoteDataScope
    let branchID: UUID
    let saleID: UUID
    let canReadCash: Bool
    private var generation = 0

    var openSessions: [RemoteCashRegister] { registers.filter { $0.openSessionId != nil } }
    var canStartCommand: Bool { !isPosting && pending.isEmpty && recoveryError.isEmpty }

    init(client: RemoteAPIClient, store: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID, saleID: UUID, canReadCash: Bool) {
        self.client = client
        self.store = store
        self.scope = scope
        self.branchID = branchID
        self.saleID = saleID
        self.canReadCash = canReadCash
        refreshPending()
    }

    func refreshPending() {
        do {
            let drafts = try store.checkedDrafts(scope: scope).filter { $0.resource == "refund-command" }
            var matching: [RemoteDraft] = []
            for draft in drafts {
                let command = try JSONDecoder().decode(RemoteRefundCommand.self, from: draft.payload)
                guard command.id == draft.id else { throw RemoteAPIError.malformedResponse }
                if command.saleID == saleID { matching.append(draft) }
            }
            pending = matching
            recoveryError = ""
        } catch {
            recoveryError = "No se pudieron leer las devoluciones guardadas. Se bloquean nuevas acciones para evitar duplicados."
        }
    }

    func load() async {
        guard !isLoading else { return }
        generation += 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = ""
        defer { if requestGeneration == generation { isLoading = false } }
        do {
            async let loadedRequests = client.refundRequestsForSale(branchId: branchID, saleID: saleID)
            async let loadedAttempts = client.paymentsForSale(branchId: branchID, saleID: saleID)
            let (newRequests, newAttempts) = try await (loadedRequests, loadedAttempts)
            guard requestGeneration == generation else { return }
            requests = newRequests
            attempts = newAttempts
            if canReadCash {
                registers = try await client.cashRegisters(branchId: branchID)
                guard requestGeneration == generation else { return }
                let sessions = registers.compactMap(\.openSessionId)
                if selectedCashSessionID.map({ !sessions.contains($0) }) ?? true {
                    selectedCashSessionID = sessions.first
                }
            }
        } catch {
            if requestGeneration == generation { errorMessage = error.localizedDescription }
        }
    }

    func requestRefund(attempt: RemotePaymentAttempt, amount rawAmount: String, reason rawReason: String) async -> Bool {
        guard attempt.status == "confirmed", let paymentEventID = attempt.paymentEventId else {
            errorMessage = "Solo un pago confirmado puede iniciar una devolución."
            return false
        }
        let reason = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = cashMoney(rawAmount, positive: true), (3...300).contains(reason.count),
              let paid = Decimal(string: attempt.amountUsd, locale: Locale(identifier: "en_US_POSIX")),
              let refunded = Decimal(string: attempt.refundedUsd, locale: Locale(identifier: "en_US_POSIX")),
              let requested = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")), requested <= paid - refunded else {
            errorMessage = "El importe debe ser positivo, no superar el saldo reembolsable y llevar un motivo de 3 a 300 caracteres."
            return false
        }
        guard !requests.contains(where: { $0.paymentEventId == paymentEventID && ["pending", "approved"].contains($0.status) && $0.refundId == nil }) else {
            errorMessage = "Ese pago ya tiene una solicitud pendiente o aprobada."
            return false
        }
        return await persistAndExecute(.request(
            saleID: saleID, paymentEventID: paymentEventID,
            body: RemoteRequestRefundBody(commandId: UUID(), amountUsd: amount, reason: reason)
        ))
    }

    func decide(_ request: RemoteRefundRequest, decision: String, reason rawReason: String) async -> Bool {
        let reason = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard request.status == "pending", request.requestedBy != scope.userId,
              ["approved", "rejected"].contains(decision), (3...1000).contains(reason.count) else {
            errorMessage = "La solicitud debe estar pendiente, pertenecer a otra persona y llevar un motivo válido."
            return false
        }
        return await persistAndExecute(.decide(
            localID: UUID(), saleID: saleID, approvalID: request.id,
            body: RemoteApprovalDecisionBody(branchId: branchID, decision: decision, reason: reason)
        ))
    }

    func executeRefund(_ request: RemoteRefundRequest, evidence rawEvidence: String) async -> Bool {
        let evidence = rawEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard request.status == "approved", request.requestedBy == scope.userId, request.refundId == nil else {
            errorMessage = "Solo quien solicitó la devolución puede ejecutar una aprobación vigente y no utilizada."
            return false
        }
        guard let cashSessionID = selectedCashSessionID,
              openSessions.contains(where: { $0.openSessionId == cashSessionID }) else {
            errorMessage = "Selecciona un turno de caja abierto."
            return false
        }
        guard evidence.count <= 200, request.method != "card" || !evidence.isEmpty else {
            errorMessage = "La devolución de tarjeta requiere una referencia del terminal de hasta 200 caracteres."
            return false
        }
        return await persistAndExecute(.execute(
            saleID: saleID, paymentEventID: request.paymentEventId,
            body: RemoteExecuteRefundBody(
                approvalId: request.id, commandId: UUID(), cashSessionId: cashSessionID,
                amountUsd: request.amountUsd, reason: request.reason,
                evidenceReference: evidence.isEmpty ? nil : evidence
            )
        ))
    }

    func retry(_ draft: RemoteDraft) async -> Bool {
        guard !isPosting, recoveryError.isEmpty else { return false }
        do {
            let command = try JSONDecoder().decode(RemoteRefundCommand.self, from: draft.payload)
            guard command.id == draft.id, command.saleID == saleID else { throw RemoteAPIError.malformedResponse }
            return await execute(command)
        } catch {
            recoveryError = "La devolución guardada no se puede recuperar; no se enviaron cambios."
            return false
        }
    }

    private func persistAndExecute(_ command: RemoteRefundCommand) async -> Bool {
        guard canStartCommand else { return false }
        do {
            let draft = RemoteDraft(scope: scope, resource: "refund-command", payload: try JSONEncoder().encode(command), id: command.id)
            try store.saveDraft(draft)
            refreshPending()
            guard recoveryError.isEmpty else { return false }
            return await execute(command)
        } catch {
            errorMessage = "No se pudo guardar la acción de devolución; no se envió al servidor."
            return false
        }
    }

    private func execute(_ command: RemoteRefundCommand) async -> Bool {
        guard !isPosting else { return false }
        isPosting = true
        errorMessage = ""
        notice = ""
        defer { isPosting = false }
        do {
            switch command {
            case .request(let commandSaleID, let paymentEventID, let body):
                guard commandSaleID == saleID else { throw RemoteAPIError.malformedResponse }
                _ = try await client.requestRefund(branchId: branchID, paymentEventID: paymentEventID, body: body)
                notice = "Solicitud enviada para revisión independiente."
            case .decide(_, let commandSaleID, let approvalID, let body):
                guard commandSaleID == saleID else { throw RemoteAPIError.malformedResponse }
                let current = try await client.refundRequestsForSale(branchId: branchID, saleID: saleID)
                guard let request = current.first(where: { $0.id == approvalID }) else { throw RemoteAPIError.malformedResponse }
                if request.status != "pending" {
                    try clear(command)
                    notice = "La solicitud ya fue resuelta. Se actualizó el estado."
                    await load()
                    return true
                }
                guard request.requestedBy != scope.userId else { throw RemoteAPIError.http(status: 409, code: "SELF_APPROVAL", message: "No puedes aprobar tu propia solicitud.", correlationId: nil) }
                _ = try await client.decideApproval(approvalID: approvalID, body: body)
                notice = body.decision == "approved" ? "Devolución aprobada." : "Devolución rechazada."
            case .execute(let commandSaleID, let paymentEventID, let body):
                guard commandSaleID == saleID else { throw RemoteAPIError.malformedResponse }
                _ = try await client.executeRefund(branchId: branchID, paymentEventID: paymentEventID, body: body)
                notice = "Devolución ejecutada y registrada en caja."
            }
            try clear(command)
            await load()
            return true
        } catch {
            let original = error.localizedDescription
            if case .decide(_, _, let approvalID, _) = command {
                do {
                    let current = try await client.refundRequestsForSale(branchId: branchID, saleID: saleID)
                    if let request = current.first(where: { $0.id == approvalID }), request.status != "pending" {
                        try clear(command)
                        notice = "La decisión ya consta en el servidor. Se actualizó la solicitud."
                        await load()
                        return true
                    }
                } catch { /* conserva el borrador si no se puede confirmar */ }
            }
            errorMessage = original
            if case RemoteAPIError.http(let status, _, _, _) = error, [400, 403, 404, 409, 422].contains(status) {
                do { try clear(command) }
                catch { recoveryError = "El servidor rechazó la acción, pero no se pudo limpiar el borrador local." }
            }
            return false
        }
    }

    private func clear(_ command: RemoteRefundCommand) throws {
        try store.removeDraft(id: command.id, scope: scope)
        refreshPending()
        guard recoveryError.isEmpty else { throw RemoteAPIError.malformedResponse }
    }
}

struct RemotePrepaymentRefundRequestBody: Codable, Sendable {
    let commandId: UUID
    let amountUsd: String
    let reason: String
}

enum RemotePrepaymentRefundCommand: Codable, Sendable {
    case collect(authorizationID: UUID, body: RemoteCollectPrepaymentBody)
    case allocate(advanceID: UUID, body: RemoteAllocatePrepaymentBody)
    case request(advanceID: UUID, body: RemotePrepaymentRefundRequestBody)
    case decide(localID: UUID, advanceID: UUID, approvalID: UUID, body: RemoteApprovalDecisionBody)
    case execute(advanceID: UUID, body: RemoteExecuteRefundBody)
    case resolve(advanceID: UUID, body: RemoteResolvePaymentBody)
    case requestRelease(advanceID: UUID, body: RemoteRequestPrepaymentReleaseBody)
    case confirmRelease(advanceID: UUID, body: RemoteConfirmPrepaymentReleaseBody)

    var id: UUID {
        switch self {
        case .collect(_, let body): body.commandId
        case .allocate(_, let body): body.commandId
        case .request(_, let body): body.commandId
        case .execute(_, let body): body.commandId
        case .resolve(_, let body): body.commandId
        case .requestRelease(_, let body): body.commandId
        case .confirmRelease(_, let body): body.commandId
        case .decide(let localID, _, _, _): localID
        }
    }

    var advanceID: UUID? {
        switch self {
        case .collect: nil
        case .allocate(let advanceID, _), .request(let advanceID, _), .decide(_, let advanceID, _, _),
             .execute(let advanceID, _), .resolve(let advanceID, _), .requestRelease(let advanceID, _),
             .confirmRelease(let advanceID, _): advanceID
        }
    }
}

@MainActor
final class RemotePrepaymentRefundViewModel: ObservableObject {
    @Published private(set) var advances: [RemotePrepayment] = []
    @Published private(set) var registers: [RemoteCashRegister] = []
    @Published var selectedCashSessionID: UUID?
    @Published private(set) var pending: [RemoteDraft] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isPosting = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var notice = ""
    @Published private(set) var recoveryError = ""

    let client: RemoteAPIClient
    let store: RemoteOfflineStore
    let scope: RemoteDataScope
    let branchID: UUID
    let canReadCash: Bool
    let canReadPrepayments: Bool
    let canCollectPrepayments: Bool
    let canResolvePrepayments: Bool
    private var generation = 0

    var openSessions: [RemoteCashRegister] { registers.filter { $0.openSessionId != nil } }
    var canStartCommand: Bool { !isPosting && pending.isEmpty && recoveryError.isEmpty }

    init(client: RemoteAPIClient, store: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID,
         canReadCash: Bool, canReadPrepayments: Bool = true,
         canCollectPrepayments: Bool = false, canResolvePrepayments: Bool = false) {
        self.client = client
        self.store = store
        self.scope = scope
        self.branchID = branchID
        self.canReadCash = canReadCash
        self.canReadPrepayments = canReadPrepayments
        self.canCollectPrepayments = canCollectPrepayments
        self.canResolvePrepayments = canResolvePrepayments
        refreshPending()
    }

    func refreshPending() {
        do {
            let drafts = try store.checkedDrafts(scope: scope).filter { $0.resource == "prepayment-refund-command" }
            var matching: [RemoteDraft] = []
            for draft in drafts {
                let command = try JSONDecoder().decode(RemotePrepaymentRefundCommand.self, from: draft.payload)
                guard command.id == draft.id else { throw RemoteAPIError.malformedResponse }
                matching.append(draft)
            }
            pending = matching
            recoveryError = ""
        } catch {
            recoveryError = "No se pudieron leer las acciones de anticipos guardadas. Se bloquean nuevas acciones para evitar duplicados."
        }
    }

    func load() async {
        guard !isLoading else { return }
        generation += 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = ""
        defer { if requestGeneration == generation { isLoading = false } }
        do {
            if canReadPrepayments && canReadCash {
                async let loadedAdvances = client.prepayments(branchId: branchID)
                async let loadedRegisters = client.cashRegisters(branchId: branchID)
                (advances, registers) = try await (loadedAdvances, loadedRegisters)
            } else if canReadPrepayments {
                advances = try await client.prepayments(branchId: branchID)
            } else {
                advances = []
            }
            guard requestGeneration == generation else { return }
            if canReadCash {
                if !canReadPrepayments { registers = try await client.cashRegisters(branchId: branchID) }
                guard requestGeneration == generation else { return }
                let sessions = registers.compactMap(\.openSessionId)
                if selectedCashSessionID.map({ !sessions.contains($0) }) ?? true { selectedCashSessionID = sessions.first }
            } else {
                registers = []
            }
        } catch {
            if requestGeneration == generation { errorMessage = error.localizedDescription }
        }
    }

    func requestRefund(_ advance: RemotePrepayment, reason rawReason: String) async -> Bool {
        let reason = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard advance.tenderKind == "captured", advance.outcome == "confirmed",
              advance.requestStatus == nil, let amount = cashMoney(advance.refundableUsd, positive: true),
              (3...300).contains(reason.count) else {
            errorMessage = "Solo se puede solicitar el remanente de un anticipo capturado y confirmado, sin otra disposición, con motivo de 3 a 300 caracteres."
            return false
        }
        return await persistAndExecute(.request(
            advanceID: advance.id,
            body: RemotePrepaymentRefundRequestBody(commandId: UUID(), amountUsd: amount, reason: reason)
        ))
    }

    func collectPrepayment(authorizationID: UUID, amount rawAmount: String, method: String, tenderKind: String,
                           outcome: String, evidence rawEvidence: String) async -> Bool {
        guard canCollectPrepayments else {
            errorMessage = "Tu usuario no tiene permiso para registrar anticipos."
            return false
        }
        guard canReadCash, let cashSessionID = selectedCashSessionID,
              openSessions.contains(where: { $0.openSessionId == cashSessionID }) else {
            errorMessage = "Selecciona una caja abierta de tu usuario para registrar el anticipo."
            return false
        }
        guard let amount = cashMoney(rawAmount, positive: true), ["cash", "card"].contains(method),
              ["captured", "authorization_hold"].contains(tenderKind),
              ["confirmed", "declined", "unknown"].contains(outcome) else {
            errorMessage = "Revisa importe, medio, tipo de tender y resultado del pago."
            return false
        }
        if method == "cash" && (tenderKind != "captured" || outcome != "confirmed") {
            errorMessage = "El efectivo se registra como capturado y confirmado; solo una tarjeta puede quedar en conciliación o retención."
            return false
        }
        if tenderKind == "authorization_hold" && method != "card" {
            errorMessage = "Una retención solo puede ser una autorización manual de tarjeta."
            return false
        }
        if tenderKind == "authorization_hold" && outcome == "declined" {
            errorMessage = "Una retención no puede registrarse como rechazada; conserva unknown si el terminal no confirmó el resultado."
            return false
        }
        let evidence = rawEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
        if method == "card" && outcome != "unknown" && evidence.isEmpty {
            errorMessage = "La tarjeta requiere referencia del terminal cuando el resultado es conocido."
            return false
        }
        if evidence.count > 200 {
            errorMessage = "La referencia documental no puede exceder 200 caracteres."
            return false
        }
        return await persistAndExecute(.collect(
            authorizationID: authorizationID,
            body: RemoteCollectPrepaymentBody(commandId: UUID(), cashSessionId: cashSessionID,
                method: method, mode: "manual", amountUsd: amount, currency: "USD", tenderKind: tenderKind,
                outcome: outcome, evidenceReference: evidence.isEmpty ? nil : evidence)
        ))
    }

    func allocatePrepayment(_ advance: RemotePrepayment, to sale: RemoteFuelSale, amount rawAmount: String) async -> Bool {
        guard canCollectPrepayments, advance.tenderKind == "captured", advance.outcome == "confirmed",
              advance.disposition == nil, advance.requestStatus == nil, advance.refundId == nil,
              sale.status == "completed", sale.authorizationId == advance.authorizationId else {
            errorMessage = "Solo se puede asignar un anticipo capturado confirmado a la venta completada de su despacho, sin otra disposición."
            return false
        }
        guard let amount = cashMoney(rawAmount, positive: true),
              let remaining = Decimal(string: advance.remainingUsd, locale: Locale(identifier: "en_US_POSIX")),
              let outstandingRaw = sale.outstandingUsd,
              let outstanding = Decimal(string: outstandingRaw, locale: Locale(identifier: "en_US_POSIX")),
              let requested = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")),
              requested <= remaining, requested <= outstanding else {
            errorMessage = "El importe debe ser positivo y no superar el saldo del anticipo ni el saldo pendiente de la venta."
            return false
        }
        return await persistAndExecute(.allocate(
            advanceID: advance.id,
            body: RemoteAllocatePrepaymentBody(saleId: sale.id, amountUsd: amount, commandId: UUID())
        ))
    }

    func requestRelease(_ advance: RemotePrepayment) async -> Bool {
        guard canResolvePrepayments, advance.tenderKind == "authorization_hold", advance.method == "card",
              advance.mode == "manual", advance.outcome == "confirmed", advance.disposition == nil,
              advance.releaseStatus == nil, let amount = cashMoney(advance.remainingUsd, positive: true) else {
            errorMessage = "Solo se puede solicitar la liberación del saldo de una retención manual confirmada sin disposición previa."
            return false
        }
        return await persistAndExecute(.requestRelease(
            advanceID: advance.id,
            body: RemoteRequestPrepaymentReleaseBody(commandId: UUID(), amountUsd: amount)
        ))
    }

    func confirmRelease(_ advance: RemotePrepayment, evidence rawEvidence: String) async -> Bool {
        let evidence = rawEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canResolvePrepayments, advance.tenderKind == "authorization_hold", advance.method == "card",
              advance.outcome == "confirmed", advance.disposition == "release", advance.releaseStatus == "pending",
              (1...200).contains(evidence.count) else {
            errorMessage = "Confirma únicamente una liberación pendiente y registra la referencia del terminal (1 a 200 caracteres)."
            return false
        }
        return await persistAndExecute(.confirmRelease(
            advanceID: advance.id,
            body: RemoteConfirmPrepaymentReleaseBody(commandId: UUID(), confirmationReference: evidence)
        ))
    }

    func resolvePrepayment(_ advance: RemotePrepayment, outcome: String, evidence rawEvidence: String) async -> Bool {
        let evidence = rawEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canResolvePrepayments, advance.outcome == "unknown", ["confirmed", "declined"].contains(outcome),
              (1...200).contains(evidence.count) else {
            errorMessage = "El anticipo debe estar por conciliar; confirma el resultado real del terminal y registra su referencia."
            return false
        }
        return await persistAndExecute(.resolve(
            advanceID: advance.id,
            body: RemoteResolvePaymentBody(commandId: UUID(), outcome: outcome, evidenceReference: evidence)
        ))
    }

    func decide(_ advance: RemotePrepayment, decision: String, reason rawReason: String) async -> Bool {
        let reason = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard advance.requestStatus == "pending", let approvalID = advance.approvalId,
              advance.requestedBy != scope.userId, ["approved", "rejected"].contains(decision),
              (3...1000).contains(reason.count) else {
            errorMessage = "La solicitud debe estar pendiente, pertenecer a otra persona y llevar un motivo válido."
            return false
        }
        return await persistAndExecute(.decide(
            localID: UUID(), advanceID: advance.id, approvalID: approvalID,
            body: RemoteApprovalDecisionBody(branchId: branchID, decision: decision, reason: reason)
        ))
    }

    func executeRefund(_ advance: RemotePrepayment, evidence rawEvidence: String) async -> Bool {
        let evidence = rawEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard advance.requestStatus == "approved", let approvalID = advance.approvalId,
              advance.refundId == nil, advance.requestedBy == scope.userId,
              let amount = advance.requestAmountUsd, let reason = advance.reason else {
            errorMessage = "Solo quien solicitó puede ejecutar una aprobación vigente y no utilizada."
            return false
        }
        guard canReadCash, let cashSessionID = selectedCashSessionID,
              openSessions.contains(where: { $0.openSessionId == cashSessionID }) else {
            errorMessage = "Selecciona una caja abierta de tu usuario antes de ejecutar la devolución."
            return false
        }
        guard (1...200).contains(evidence.count) else {
            errorMessage = "Registra la referencia documental de la devolución (1 a 200 caracteres)."
            return false
        }
        return await persistAndExecute(.execute(
            advanceID: advance.id,
            body: RemoteExecuteRefundBody(approvalId: approvalID, commandId: UUID(), cashSessionId: cashSessionID,
                amountUsd: amount, reason: reason, evidenceReference: evidence)
        ))
    }

    func retry(_ draft: RemoteDraft) async -> Bool {
        guard !isPosting, recoveryError.isEmpty else { return false }
        do {
            let command = try JSONDecoder().decode(RemotePrepaymentRefundCommand.self, from: draft.payload)
            guard command.id == draft.id else { throw RemoteAPIError.malformedResponse }
            return await execute(command)
        } catch {
            recoveryError = "La acción de anticipo guardada no se puede recuperar; no se enviaron cambios."
            return false
        }
    }

    private func persistAndExecute(_ command: RemotePrepaymentRefundCommand) async -> Bool {
        guard canStartCommand else { return false }
        do {
            try store.saveDraft(RemoteDraft(scope: scope, resource: "prepayment-refund-command", payload: try JSONEncoder().encode(command), id: command.id))
            refreshPending()
            guard recoveryError.isEmpty else { return false }
            return await execute(command)
        } catch {
            errorMessage = "No se pudo guardar la acción financiera; no se envió al servidor."
            return false
        }
    }

    private func execute(_ command: RemotePrepaymentRefundCommand) async -> Bool {
        guard !isPosting else { return false }
        isPosting = true
        errorMessage = ""
        notice = ""
        defer { isPosting = false }
        do {
            switch command {
            case .collect(let authorizationID, let body):
                _ = try await client.collectPrepayment(branchId: branchID, authorizationID: authorizationID, body: body)
                notice = "Anticipo registrado y ligado a la autorización de despacho."
            case .allocate(let advanceID, let body):
                _ = try await client.allocatePrepayment(branchId: branchID, advanceID: advanceID, body: body)
                notice = "Anticipo aplicado al saldo de la venta del despacho."
            case .request(let advanceID, let body):
                _ = try await client.requestPrepaymentRefund(branchId: branchID, advanceID: advanceID, body: body)
                notice = "Solicitud enviada para revisión independiente."
            case .decide(_, let advanceID, let approvalID, let body):
                let current = try await client.prepayments(branchId: branchID)
                guard let advance = current.first(where: { $0.id == advanceID }) else { throw RemoteAPIError.malformedResponse }
                if advance.requestStatus != "pending" {
                    try clear(command)
                    notice = "La solicitud ya fue resuelta. Se actualizó su estado."
                    await load()
                    return true
                }
                guard advance.approvalId == approvalID, advance.requestedBy != scope.userId else {
                    throw RemoteAPIError.http(status: 409, code: "SELF_APPROVAL", message: "No puedes aprobar tu propia solicitud.", correlationId: nil)
                }
                _ = try await client.decideApproval(approvalID: approvalID, body: body)
                notice = body.decision == "approved" ? "Devolución aprobada." : "Devolución rechazada."
            case .execute(let advanceID, let body):
                _ = try await client.executePrepaymentRefund(branchId: branchID, advanceID: advanceID, body: body)
                notice = "Devolución ejecutada y registrada en caja."
            case .resolve(let advanceID, let body):
                _ = try await client.resolvePrepayment(branchId: branchID, advanceID: advanceID, body: body)
                notice = body.outcome == "confirmed" ? "Pago confirmado con evidencia." : "Pago marcado como rechazado con evidencia."
            case .requestRelease(let advanceID, let body):
                _ = try await client.requestPrepaymentRelease(branchId: branchID, advanceID: advanceID, body: body)
                notice = "Liberación solicitada; confirma el resultado del terminal cuando se complete."
            case .confirmRelease(let advanceID, let body):
                _ = try await client.confirmPrepaymentRelease(branchId: branchID, advanceID: advanceID, body: body)
                notice = "Liberación confirmada con referencia del terminal."
            }
            try clear(command)
            await load()
            return true
        } catch {
            let original = error.localizedDescription
            if canReadPrepayments {
                do {
                    let current = try await client.prepayments(branchId: branchID)
                    if let advanceID = command.advanceID, let advance = current.first(where: { $0.id == advanceID }) {
                        let completed: Bool
                        switch command {
                        case .collect: completed = false
                        case .allocate: completed = false
                        case .request: completed = advance.requestStatus != nil
                        case .decide: completed = advance.requestStatus != "pending"
                        case .execute: completed = advance.refundId != nil
                        case .resolve: completed = advance.outcome != "unknown"
                        case .requestRelease: completed = advance.releaseStatus != nil
                        case .confirmRelease: completed = advance.releaseStatus == "released"
                        }
                        if completed {
                            try clear(command)
                            notice = "La acción ya consta en el servidor. Se actualizó el anticipo."
                            await load()
                            return true
                        }
                    }
                } catch { /* conserva el borrador si no puede confirmar el estado remoto */ }
            }
            errorMessage = original
            if case RemoteAPIError.http(let status, _, _, _) = error, [400, 403, 404, 409, 422].contains(status) {
                do { try clear(command) }
                catch { recoveryError = "El servidor rechazó la acción, pero no se pudo limpiar el borrador local." }
            }
            return false
        }
    }

    private func clear(_ command: RemotePrepaymentRefundCommand) throws {
        try store.removeDraft(id: command.id, scope: scope)
        refreshPending()
        guard recoveryError.isEmpty else { throw RemoteAPIError.malformedResponse }
    }
}
