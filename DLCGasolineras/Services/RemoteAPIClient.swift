import Foundation
import Security

struct RemoteSessionTokens: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: Date
    let sessionId: UUID
}

struct RemoteIdentity: Decodable, Sendable {
    struct RoleAssignment: Decodable, Sendable {
        let code: String
        let name: String
        let branchId: UUID?

        var isGeneralManager: Bool {
            "\(code) \(name)".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased().contains("general")
        }
    }

    let id: UUID
    let organizationId: UUID
    let displayName: String
    let email: String
    let roles: [RoleAssignment]
}

struct RemoteCapabilities: Decodable, Sendable {
    let permissions: [String]
}

struct RemoteBranchDashboard: Decodable, Sendable {
    struct Branch: Decodable, Sendable { let id: UUID; let name: String; let timezone: String }
    struct Cut: Decodable, Sendable, Identifiable {
        let id: UUID; let slot: String; let status: String
        let closedAt: Date?; let closedBy: UUID?; let reviewRequired: Bool?
        let closedSalesUsd: String?
        let expectedDispensers: Int; let registeredDispensers: Int
        let expectedNozzles: Int; let registeredNozzles: Int
    }
    struct Tank: Decodable, Sendable, Identifiable {
        let id: UUID; let code: String; let name: String?; let fuelName: String; let family: String
        let capacityLiters: String; let onHandLiters: String?; let percentage: String?
        let usableLiters: String?; let warningPercent: String?; let criticalPercent: String?
        let updatedAt: Date?

        var levelLabel: String {
            guard let percentage, let value = Double(percentage), value.isFinite else { return "Sin medición" }
            if let criticalPercent, let threshold = Double(criticalPercent), value < threshold { return "Crítico" }
            if let warningPercent, let threshold = Double(warningPercent), value < threshold { return "Bajo" }
            return "En rango"
        }

        var levelColor: String {
            switch levelLabel {
            case "Crítico": "critical"
            case "Bajo": "warning"
            case "Sin medición": "unknown"
            default: "normal"
            }
        }
    }
    struct Inventory: Decodable, Sendable {
        let tanks: [Tank]; let totalLiters: String?; let capacityLiters: String; let missingBaselines: Int
    }
    struct Incident: Decodable, Sendable, Identifiable {
        let id: UUID; let severity: String; let status: String; let category: String; let description: String
    }
    struct Alert: Decodable, Sendable, Identifiable {
        struct Action: Decodable, Sendable { let kind: String; let id: UUID }
        let key: String; let severity: String; let title: String; let detail: String
        let status: String; let action: Action
        var id: String { key }
    }
    let branch: Branch; let operationalDate: String; let cuts: [Cut]; let inventory: Inventory
    let openIncidents: [Incident]; let alerts: [Alert]; let openMaintenanceOrders: Int; let lastSourceAt: Date?
}

struct RemoteOperationalCut: Decodable, Sendable, Identifiable {
    let id: UUID
    let slot: Int
    let operationalDate: String
    let startsAt: Date
    let endsAt: Date
    let status: String
    let version: Int
    let closedAt: Date?
    let closedByName: String?

    var title: String { slot == 1 ? "Matutino" : "Vespertino" }
}

struct RemoteGeneratedCut: Decodable, Sendable, Identifiable {
    let id: UUID
    let slot: Int
    let startsAt: Date
    let endsAt: Date
}

struct RemoteCutAssets: Decodable, Sendable {
    struct Cut: Decodable, Sendable {
        let id: UUID
        let status: String
        let version: Int
        let startsAt: Date
        let endsAt: Date
    }
    struct Dispenser: Decodable, Sendable, Identifiable {
        let id: UUID
        let code: String
        let physicalStatus: String
        let configurationVersion: Int
    }
    struct Nozzle: Decodable, Sendable, Identifiable {
        let id: UUID
        let dispenserId: UUID
        let code: String
        let fuelProductId: UUID
        let fuelName: String
        let meterUnit: String
        let participation: String
        let exclusionReason: String?
        let configurationVersion: Int
        let lastMeterValue: String?
        let meterVersion: Int?
        let meterSerial: String?
        let lastReadingId: UUID?
        let lastReadingAt: Date?
        let lastReadingType: String?
        let cutReadingId: UUID?
        let measuredLiters: String?

        var meterUnitLabel: String {
            switch meterUnit {
            case "gallon_us": "gal US"
            case "liter": "L"
            default: meterUnit
            }
        }
    }
    struct Tank: Decodable, Sendable, Identifiable {
        let id: UUID
        let code: String
        let name: String?
        let fuelProductId: UUID
        let fuelName: String
        let capacityLiters: String
        let measuredLiters: String?
        let waterLiters: String?
        let temperatureC: String?
        let observedAt: Date?
        let source: String?
        let evidenceReference: String?
    }

    let cut: Cut
    let dispensers: [Dispenser]
    let nozzles: [Nozzle]
    let tanks: [Tank]
}

struct RemoteCutProgress: Decodable, Sendable {
    struct Cut: Decodable, Sendable {
        let id: UUID
        let status: String
        let version: Int
        let startsAt: Date
        let endsAt: Date
    }
    struct Product: Decodable, Sendable, Identifiable {
        let fuelProductId: UUID
        let productName: String
        let expected: Int
        let captured: Int
        let meterLiters: String
        var id: UUID { fuelProductId }
    }
    let cut: Cut
    let products: [Product]
    let basis: String
    let provisional: Bool
}

struct RemoteCutReconciliation: Decodable, Sendable {
    struct PriceVersion: Decodable, Sendable, Identifiable {
        let priceVersionId: UUID
        let unitPriceUsd: RemoteDecimal?
        let priceUnit: String
        let liters: RemoteDecimal?
        let salesUsd: RemoteDecimal?
        var id: UUID { priceVersionId }
    }

    struct Product: Decodable, Sendable, Identifiable {
        let fuelProductId: UUID
        let productName: String?
        let meterLiters: RemoteDecimal?
        let soldLiters: RemoteDecimal?
        let salesUsd: RemoteDecimal?
        let receiptsLiters: RemoteDecimal?
        let lossLiters: RemoteDecimal?
        let varianceLiters: RemoteDecimal?
        let priceVersions: [PriceVersion]?
        var id: UUID { fuelProductId }
    }
    struct Tank: Decodable, Sendable, Identifiable {
        let tankId: UUID
        let tankCode: String?
        let tankName: String?
        let fuelName: String?
        let measuredLiters: RemoteDecimal?
        let ledgerLiters: RemoteDecimal?
        let varianceLiters: RemoteDecimal?
        var id: UUID { tankId }
    }
    struct Finance: Decodable, Sendable {
        let salesUsd: RemoteDecimal?
        let confirmedCollectionUsd: RemoteDecimal?
        let cashConfirmedUsd: RemoteDecimal?
        let cardConfirmedUsd: RemoteDecimal?
        let refundedUsd: RemoteDecimal?
    }
    struct Review: Decodable, Sendable {
        let id: UUID
        let reviewedBy: UUID
        let reviewedByName: String?
        let reviewedAt: Date
        let reason: String
    }

    let cutId: UUID
    let version: Int
    let products: [Product]
    let tanks: [Tank]
    let finance: Finance
    let reviewRequired: Bool
    let preparedBy: UUID
    let preparedByName: String?
    let preparedAt: Date?
    let status: String?
    let review: Review?
}

struct RemoteDecimal: Decodable, Sendable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self),
           let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) {
            value = decimal
            return
        }
        if let decimal = try? container.decode(Decimal.self) {
            value = decimal
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "El valor numérico del servidor no es válido.")
    }
}

struct RemoteCutOpenResult: Decodable, Sendable {
    let id: UUID
    let version: Int
    let expectedDispensers: Int
    let expectedNozzles: Int
    let excusedNozzles: Int
}

struct RemoteCutCaptureResult: Decodable, Sendable {
    let cutId: UUID
    let nozzleId: UUID
    let version: Int
    let measuredL: String
}

struct RemoteCutTankResult: Decodable, Sendable {
    let cutId: UUID
    let tankId: UUID
    let version: Int
    let measuredL: String
}

struct RemoteCutPrepareResult: Decodable, Sendable {
    let cutId: UUID
    let preparationId: UUID
    let version: Int
    let reviewRequired: Bool
    let automaticClosureId: UUID?
}

struct RemoteCutTransitionResult: Decodable, Sendable {
    let cutId: UUID
    let version: Int
    let reviewId: UUID?
    let closureId: UUID?
    let closedAt: Date?

    enum CodingKeys: String, CodingKey {
        case cutId, version
        case reviewId = "review_id"
        case closureId = "closure_id"
        case closedAt = "closed_at"
    }
}

struct RemoteIncidentDetail: Decodable, Sendable {
    struct Incident: Decodable, Sendable {
        let id: UUID; let code: String; let category: String; let severity: String
        let description: String; let status: String; let version: Int
    }
    struct Event: Decodable, Sendable, Identifiable {
        let fromStatus: String?; let toStatus: String; let note: String; let occurredAt: Date
        var id: String { "\(occurredAt.timeIntervalSince1970):\(toStatus):\(note)" }
    }
    let incident: Incident; let events: [Event]
}

struct RemoteNetworkDashboard: Decodable, Sendable {
    struct Day: Decodable, Sendable, Identifiable {
        let date: String; let closedCuts: Int; let soldLiters: String; let salesUsd: String
        var id: String { date }
    }
    struct Product: Decodable, Sendable {
        let fuelProductId: UUID; let fuelName: String; let family: String
        let soldLiters: String; let salesUsd: String
    }
    struct Tank: Decodable, Sendable {
        let fuelName: String; let family: String; let onHandLiters: String?
        let capacityLiters: String; let missingBaselines: Int
    }
    struct Branch: Decodable, Sendable, Identifiable {
        let id: UUID; let name: String; let code: String; let inventoryRisk: String
        let closedCuts: Int; let expectedCuts: Int
        let lastClosedAt: Date?; let products: [Product]; let tanks: [Tank]
    }
    struct Coverage: Decodable, Sendable { let closed: Int; let expected: Int }
    let periodDays: Int; let activeBranchCount: Int; let cutCoverage: Coverage
    let branches: [Branch]; let dailySeries: [Day]; let lastSourceAt: Date?
}

struct RemoteReportRunCreated: Decodable, Sendable { let id: UUID; let rowCount: Int?; let idempotentReplay: Bool }
struct RemoteReportPage: Decodable, Sendable {
    let id: UUID; let type: String; let rowCount: Int; let asOf: Date; let sourceWatermark: Date?
    let timezone: String; let unit: String; let currency: String; let columns: [String]
    let rows: [[String:String]]; let nextOffset: Int?
}
struct RemoteSavedReportFilter: Decodable, Sendable, Identifiable {
    struct Filters: Decodable, Sendable {
        let from: String; let to: String; let productId: UUID?; let dispenserId: UUID?
        let serviceMode: String?; let groupBy: String?; let status: String?
    }
    let id: UUID; let name: String; let type: String; let filters: Filters; let version: Int
}

struct RemoteNozzleMeterReading: Codable, Sendable, Identifiable {
    let id: UUID
    let readingType: String
    let value: String
    let unit: String
    let priorValue: String?
    let priorMeterSerial: String?
    let meterSerial: String?
    let oldSerial: String?
    let newSerial: String?
    let changeReason: String?
    let note: String?
    let source: String
    let capturedBy: UUID?
    let capturedAt: Date?
}

struct RemoteNozzleMeterState: Codable, Sendable {
    let unit: String
    let lastValue: String
    let meterSerial: String?
    let version: Int
    let lastReadingId: UUID?
    let updatedAt: Date?
}

struct RemoteNozzleMeterHistory: Codable, Sendable {
    let state: RemoteNozzleMeterState?
    let readings: [RemoteNozzleMeterReading]
}

struct RemotePageMetadata: Codable, Sendable {
    let limit: Int
    let nextCursor: String?
}

struct RemotePage<Value: Codable & Sendable>: Codable, Sendable {
    let data: [Value]
    let meta: RemotePageMetadata
}

struct RemoteDispenserProduct: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let family: String
    let productCode: String
    let serviceMode: String
}

struct RemoteDispenserSummary: Codable, Sendable, Identifiable {
    let id: UUID
    let code: String
    let name: String?
    let physicalStatus: String
    let version: Int
    let nozzleCount: Int
    let activeNozzles: Int
    let products: [RemoteDispenserProduct]
}

struct RemoteDispenserNozzle: Codable, Sendable, Identifiable {
    let id: UUID
    let code: String
    let productCode: String
    let fuelProductId: UUID
    let fuelName: String
    let family: String
    let serviceMode: String
    let physicalStatus: String
    let meterUnit: String
    let meterPrecision: Int
    let tankId: UUID?
    let tankCode: String?
    let version: Int
    let meterValue: String?
    let meterSerial: String?
    let meterVersion: Int?
    let lastMeterReadingId: UUID?
    let lastMeterReadingAt: Date?
}

struct RemoteDispenserDetail: Codable, Sendable, Identifiable {
    let id: UUID
    let branchId: UUID
    let code: String
    let name: String?
    let physicalStatus: String
    let version: Int
    let nozzles: [RemoteDispenserNozzle]
}

struct RemoteTankSummary: Codable, Sendable, Identifiable {
    let id: UUID
    let code: String
    let name: String?
    let fuelProductId: UUID
    let fuelName: String
    let family: String
    let nominalCapacityL: String
    let safeFillLimitL: String
    let unusableReserveL: String
    let status: String
    let version: Int
}

struct RemoteTankConnection: Codable, Sendable, Identifiable {
    let connectionId: UUID
    let nozzleId: UUID
    let nozzleCode: String
    let dispenserId: UUID
    let dispenserCode: String
    let validFrom: Date
    let validUntil: Date?
    var id: UUID { connectionId }
}

struct RemoteTankDetail: Codable, Sendable, Identifiable {
    let id: UUID
    let branchId: UUID
    let code: String
    let name: String?
    let fuelProductId: UUID
    let fuelName: String
    let family: String
    let nominalCapacityL: String
    let safeFillLimitL: String
    let unusableReserveL: String
    let status: String
    let version: Int
    let connections: [RemoteTankConnection]
}

struct RemoteTankInventorySnapshot: Codable, Sendable {
    struct Tank: Codable, Sendable {
        let id: UUID
        let branchId: UUID
        let code: String
        let name: String?
        let fuelProductId: UUID
        let nominalCapacityL: String
        let safeFillLimitL: String
        let unusableReserveL: String
        let status: String
    }
    struct Balance: Codable, Sendable {
        let onHandL: String
        let inventoryValueUsd: String?
        let averageCostPerLUsd: String?
        let valuationQuality: String
        let version: Int
        let lastMovementId: UUID?
        let updatedAt: Date?
    }
    let tank: Tank
    let balance: Balance?
    let balanceKnown: Bool
}

struct RemoteInventoryMovement: Codable, Sendable, Identifiable {
    let id: UUID
    let movementType: String
    let sourceType: String?
    let sourceId: UUID?
    let sourceLine: String?
    let quantityEntered: String
    let unitEntered: String
    let conversionFactorToL: String
    let observedL: String
    let compensatedL: String?
    let deltaL: String
    let volumeBasis: String?
    let temperatureC: String?
    let referenceTemperatureC: String?
    let waterL: String?
    let unitCostUsdPerL: String?
    let totalCostUsd: String?
    let costRecognizedUsd: String?
    let valuationQuality: String
    let reasonCode: String?
    let reason: String?
    let documentReference: String?
    let beforeQuantityL: String?
    let afterQuantityL: String?
    let actorUserId: UUID?
    let occurredAt: Date
}

struct RemoteBranchSummary: Codable, Sendable, Identifiable {
    let id: UUID
    let code: String
    let name: String
    let zone: String
    let timezone: String
    let status: String
    let onboardingVersion: Int
    let updatedAt: Date
}

struct RemoteBranchDetail: Codable, Sendable, Identifiable {
    let id: UUID
    let code: String
    let name: String
    let zone: String
    let timezone: String
    let status: String
    let onboardingVersion: Int
    let configuredAt: Date?
    let activatedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

struct RemoteFuelProductSummary: Codable, Sendable, Identifiable {
    let id: UUID
    let sku: String
    let displayName: String
    let family: String
    let brand: String?
    let status: String
}

struct RemoteBranchFuelOffer: Codable, Sendable, Identifiable {
    let id: UUID
    let sku: String
    let displayName: String
    let family: String
    let brand: String?
    let status: String
}

struct RemoteFuelOfferActivationResult: Decodable, Sendable {
    let branchId: UUID
    let fuelProductId: UUID
    let status: String
    let version: Int
    let validFrom: Date
}

struct RemoteBranchConfiguration: Decodable, Sendable {
    let fuelOffers: [RemoteBranchFuelOffer]
}

struct RemoteCreateFuelProduct: Encodable, Sendable {
    let sku: String
    let displayName: String
    let family: String
    let brand: String?
}

struct RemoteEmployeeSummary: Codable, Sendable, Identifiable {
    let id: UUID
    let employeeCode: String
    let legalName: String
    let positionTitle: String
    let status: String
    let version: Int
    let hiredOn: String?
}

struct RemoteCreateEmployee: Encodable, Sendable {
    let employeeCode: String
    let legalName: String
    let positionTitle: String
    let contactEmail: String?
}

struct RemoteBranchFuelPrice: Codable, Sendable, Identifiable {
    let id: UUID
    let fuelProductId: UUID
    let productName: String?
    let serviceMode: String
    let version: Int
    let priceUsdPerUnit: String
    let unit: String
    let effectiveAt: Date
}

struct RemoteBranchFuelPriceBoard: Decodable, Sendable {
    let current: [RemoteBranchFuelPrice]
    let upcoming: [RemoteBranchFuelPrice]
}

struct RemoteFuelPriceProposal: Codable, Sendable, Identifiable {
    let id: UUID
    let fuelProductId: UUID
    let productName: String?
    let serviceMode: String
    let priceUsdPerUnit: String
    let unit: String
    let effectiveAt: Date
    let reason: String
    let status: String
    let version: Int
    let createdBy: UUID?
}

struct RemoteCreateFuelPriceProposal: Encodable, Sendable {
    let fuelProductId: UUID
    let serviceMode: String
    let priceUsdPerUnit: String
    let unit: String
    let effectiveAt: Date
    let reason: String
}

struct RemoteCreateBranchDraft: Encodable, Sendable {
    let code: String
    let name: String
    let zone: String
    let timezone: String
    let profile: String
    let expectedDispenserCount: Int
}

struct RemoteBranchBlocker: Codable, Sendable, Identifiable {
    let code: String
    let step: String
    let message: String
    var id: String { code }
}

struct RemoteBranchReadiness: Codable, Sendable {
    let branchId: UUID
    let status: String
    let canActivate: Bool
    let onboardingVersion: Int
    let activeEmployeeCount: Int
    let blockers: [RemoteBranchBlocker]
}

struct RemoteBranchOnboardingData: Encodable, Sendable {
    var code: String? = nil
    var name: String? = nil
    var zone: String? = nil
    var timezone: String? = nil
    var status: String? = nil
    var employeeCount: Int? = nil
}

struct RemoteNozzleAvailability: Codable, Sendable {
    struct Reason: Codable, Sendable, Identifiable {
        let code: String
        let message: String
        let source: String
        var id: String { code }
    }
    struct Inventory: Codable, Sendable {
        let onHandL: String
        let reserveL: String?
        let valuationQuality: String?
    }
    struct Price: Codable, Sendable {
        let versionId: UUID
        let amount: String
        let unit: String
        let serviceMode: String
    }
    let nozzleId: UUID
    let selectable: Bool
    let reasons: [Reason]
    let inventory: Inventory?
    let price: Price?
    let computedAt: Date
    let source: String
    let inventoryCoverage: String
}

struct RemoteDispenseEvent: Decodable, Sendable, Identifiable {
    let id: UUID
    let eventType: String
    let previousStatus: String?
    let nextStatus: String
    let measuredL: String?
    let actorUserId: UUID?
    let reason: String?
    let occurredAt: Date?
}

struct RemoteDispenseAuthorization: Decodable, Sendable, Identifiable {
    let id: UUID
    let nozzleId: UUID
    let nozzleCode: String?
    let dispenserCode: String?
    let fuelName: String?
    let tankId: UUID
    let fuelProductId: UUID
    let status: String
    let requestType: String
    let requestedAmountUsd: String?
    let requestedVolume: String?
    let requestedVolumeUnit: String?
    let reservedL: String
    let progressL: String
    let actualL: String?
    let priceUsdPerUnit: String
    let priceUnit: String
    let saleAmountUsd: String?
    let version: Int
    let expiresAt: Date?
    let startedAt: Date?
    let completedAt: Date?
    let inventoryMovementId: UUID?
    let events: [RemoteDispenseEvent]
}

struct RemoteFuelTaxRule: Codable, Sendable, Identifiable {
    var id: String { code }
    let code: String
    let label: String
    let kind: String
    let base: String
    let rate: String
}
struct RemoteFuelTaxComponent: Decodable, Sendable, Identifiable {
    var id: String { code }
    let code: String
    let label: String
    let kind: String
    let base: String
    let rate: String
    let taxUsd: String
}
struct RemoteFuelTaxPolicy: Decodable, Sendable, Identifiable {
    let id: UUID
    let fuelProductId: UUID
    let fuelName: String
    let mode: String
    let rules: [RemoteFuelTaxRule]
    let sourceReference: String
    let reason: String
    let effectiveAt: Date
    let proposedBy: UUID
    let policyVersionId: UUID?
    let approvedBy: UUID?
    let version: Int?
    let status: String
}
struct RemoteFuelTaxPolicyPage: Decodable, Sendable {
    struct Product: Decodable, Sendable, Identifiable { let id: UUID; let name: String }
    let data: [RemoteFuelTaxPolicy]
    let products: [Product]
}
struct RemoteFuelTaxProposalBody: Encodable, Sendable {
    let commandId: UUID
    let fuelProductId: UUID
    let mode: String
    let rules: [RemoteFuelTaxRule]
    let sourceReference: String
    let reason: String
    let effectiveAt: Date
}
struct RemoteFuelTaxWriteResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable { let id: UUID; let idempotentReplay: Bool }
    let data: Data
}

struct RemoteFuelSale: Decodable, Sendable, Identifiable {
    struct Line: Decodable, Sendable, Identifiable {
        let id: UUID
        let kind: String
        let description: String
        let quantityL: String?
        let quantityUnits: String?
        let posProductId: UUID?
        let offerVersionId: UUID?
        let unitCostUsd: String?
        let priceUsdPerUnit: String
        let priceUnit: String
        let priceVersionId: UUID?
        let totalUsd: String
        let inventoryMovementId: UUID?
        let costUsd: String?
        let unitCostUsdPerL: String?
        let costQuality: String
    }
    let id: UUID
    let authorizationId: UUID?
    let status: String
    let totalUsd: String
    let collectedUsd: String?
    let outstandingUsd: String?
    let reservedUsd: String?
    let refundedUsd: String?
    let refundStatus: String?
    let taxPolicyVersionId: UUID?
    let taxComponents: [RemoteFuelTaxComponent]
    let taxStatus: String
    let netUsd: String?
    let taxUsd: String?
    let receiptType: String
    let occurredAt: Date?
    let createdAt: Date?
    let createdBy: UUID
    let lines: [Line]
}

struct RemoteFuelSaleSummary: Codable, Sendable, Identifiable {
    let id: UUID
    let authorizationId: UUID?
    let status: String
    let totalUsd: String
    let description: String
    let quantityL: String?
    let lineCount: Int
    let occurredAt: Date?
}

struct RemoteCombinedInternalReceipt: Decodable, Sendable, Identifiable {
    struct Components: Decodable, Sendable {
        let fuel: RemoteFuelSale
        let pos: RemoteFuelSale
    }
    let id: UUID
    let receiptType: String
    let fiscalStatus: String
    let taxStatus: String
    let totalUsd: String
    let collectionStatus: String
    let createdAt: Date
    let createdBy: UUID
    let correlationId: UUID
    let idempotentReplay: Bool
    let components: Components
}

struct RemoteCombinedReceiptBody: Codable, Sendable {
    let commandId: UUID
    let fuelSaleId: UUID
    let posSaleId: UUID
}

struct RemotePOSProduct: Codable, Sendable, Identifiable {
    let id: UUID
    let sku: String
    let kind: String
    let expiryRequired: Bool
    let offerVersionId: UUID
    let version: Int
    let description: String
    let active: Bool
    let priceUsd: String
    let serviceUnitCostUsd: String?
    let availableUnits: String
    let expiredUnits: String
    let updatedAt: Date?
}
struct RemotePOSLot: Codable, Sendable, Identifiable {
    let id: UUID
    let lotCode: String
    let expiresOn: String?
    let receivedUnits: String
    let remainingUnits: String
    let sourceReference: String
    let receivedAt: Date?
    let unitCostUsd: String?
}
struct RemotePOSOfferBody: Codable, Sendable {
    let commandId: UUID
    let productId: UUID?
    let expectedOfferVersionId: UUID?
    let sku: String
    let kind: String
    let expiryRequired: Bool
    let description: String
    let active: Bool
    let priceUsd: String
    let serviceUnitCostUsd: String?
}
struct RemotePOSReceiptBody: Codable, Sendable {
    let commandId: UUID
    let productId: UUID
    let lotCode: String
    let expiresOn: String?
    let quantity: String
    let unitCostUsd: String?
    let sourceReference: String
}
struct RemotePOSSaleBody: Codable, Sendable {
    struct Item: Codable, Sendable { let productId: UUID; let offerVersionId: UUID; let quantity: String }
    let commandId: UUID
    let items: [Item]
}
struct RemotePOSWriteResult: Decodable, Sendable {
    struct Data: Decodable, Sendable { let id: UUID; let productId: UUID?; let idempotentReplay: Bool }
    let data: Data
}

struct RemoteCashRegister: Decodable, Sendable, Identifiable {
    let id: UUID
    let code: String
    let openSessionId: UUID?
    let cashierId: UUID?
}

struct RemoteCashSession: Decodable, Sendable, Identifiable {
    let id: UUID
    let registerId: UUID
    let cashierId: UUID
    let openingUsd: String
    let openedAt: Date
    let expectedCashUsd: String
    let closureId: UUID?
    let reviewStatus: String?
}

struct RemoteCashMovement: Decodable, Sendable, Identifiable {
    let id: UUID
    let kind: String
    let deltaUsd: String
    let reason: String
    let createdAt: Date
    let createdBy: UUID
    let paymentEventId: UUID?
    let advanceId: UUID?
    let refundId: UUID?
}

struct RemoteCashMovementCursor: Codable, Sendable {
    let beforeAt: String
    let beforeId: UUID
}

struct RemoteCashMovementPage: Decodable, Sendable {
    let data: [RemoteCashMovement]
    let nextCursor: RemoteCashMovementCursor?
}

struct RemoteCashClosure: Decodable, Sendable, Identifiable {
    let id: UUID
    let idempotentReplay: Bool
    let expectedCashUsd: String
    let expectedCardUsd: String
    let varianceCashUsd: String
    let varianceCardUsd: String
    let reviewStatus: String
}

struct RemoteCashReview: Decodable, Sendable, Identifiable {
    let closureId: UUID
    let sessionId: UUID
    let cashierId: UUID?
    let closedAt: Date?
    let expectedCashUsd: String?
    let countedCashUsd: String?
    let varianceCashUsd: String?
    let expectedCardUsd: String?
    let settledCardUsd: String?
    let varianceCardUsd: String?
    let cashierReason: String?
    let approvalId: UUID?
    let status: String
    let decidedBy: UUID?
    let decidedAt: Date?
    let decisionReason: String?
    var id: UUID { closureId }
}

struct RemoteCashWriteResult: Decodable, Sendable {
    struct Data: Decodable, Sendable { let id: UUID; let idempotentReplay: Bool }
    let data: Data
}

struct RemoteCashRegisterWriteResult: Decodable, Sendable {
    struct Data: Decodable, Sendable { let id: UUID; let code: String; let idempotentReplay: Bool }
    let data: Data
}

struct RemoteCashRegisterBody: Codable, Sendable {
    let commandId: UUID
    let code: String
}

struct RemoteCashOpenBody: Codable, Sendable {
    let commandId: UUID
    let registerId: UUID
    let openingUsd: String
}

struct RemoteCashMovementBody: Codable, Sendable {
    let commandId: UUID
    let kind: String
    let amountUsd: String
    let reason: String
}

struct RemoteCashCloseBody: Codable, Sendable {
    let commandId: UUID
    let countedCashUsd: String
    let settledCardUsd: String
    let reason: String?
}

enum RemoteCashCommand: Codable, Sendable {
    case createRegister(RemoteCashRegisterBody)
    case open(RemoteCashOpenBody)
    case movement(sessionID: UUID, body: RemoteCashMovementBody)
    case close(sessionID: UUID, body: RemoteCashCloseBody)

    var id: UUID {
        switch self {
        case .createRegister(let body): body.commandId
        case .open(let body): body.commandId
        case .movement(_, let body): body.commandId
        case .close(_, let body): body.commandId
        }
    }
}

struct RemotePaymentAttempt: Decodable, Sendable, Identifiable {
    let id: UUID
    let method: String
    let mode: String
    let amountUsd: String
    let cashSessionId: UUID
    let createdAt: Date
    let status: String
    let paymentEventId: UUID?
    let evidenceReference: String?
    let refundedUsd: String
}

struct RemoteRefundRequest: Decodable, Sendable, Identifiable {
    let id: UUID
    let paymentEventId: UUID
    let method: String
    let paymentAmountUsd: String
    let requestedBy: UUID
    let amountUsd: String
    let reason: String
    let status: String
    let decidedBy: UUID?
    let decidedAt: Date?
    let decisionReason: String?
    let createdAt: Date
    let refundId: UUID?
    let refundedAt: Date?
}

struct RemotePrepayment: Decodable, Sendable, Identifiable {
    let id: UUID
    let authorizationId: UUID
    let method: String
    let mode: String
    let tenderKind: String
    let outcome: String
    let amountUsd: String
    let allocatedUsd: String
    let remainingUsd: String
    let refundableUsd: String
    let evidenceReference: String?
    let createdBy: UUID
    let createdAt: Date
    let disposition: String?
    let releaseStatus: String?
    let approvalId: UUID?
    let requestedBy: UUID?
    let requestAmountUsd: String?
    let reason: String?
    let requestStatus: String?
    let decidedBy: UUID?
    let decidedAt: Date?
    let decisionReason: String?
    let refundId: UUID?
    let refundedAt: Date?
}

struct RemoteCollectPaymentBody: Codable, Sendable {
    let commandId: UUID
    let saleId: UUID
    let cashSessionId: UUID
    let method: String
    let mode: String
    let amountUsd: String
    let outcome: String
    let evidenceReference: String?
}

struct RemoteCollectPrepaymentBody: Codable, Sendable {
    let commandId: UUID
    let cashSessionId: UUID
    let method: String
    let mode: String
    let amountUsd: String
    let currency: String
    let tenderKind: String
    let outcome: String
    let evidenceReference: String?
}

struct RemoteAllocatePrepaymentBody: Codable, Sendable {
    let saleId: UUID
    let amountUsd: String
    let commandId: UUID
}

struct RemoteRequestPrepaymentReleaseBody: Codable, Sendable {
    let commandId: UUID
    let amountUsd: String
}

struct RemoteConfirmPrepaymentReleaseBody: Codable, Sendable {
    let commandId: UUID
    let confirmationReference: String
}

struct RemoteResolvePaymentBody: Codable, Sendable {
    let commandId: UUID
    let outcome: String
    let evidenceReference: String
}

struct RemoteRequestRefundBody: Codable, Sendable {
    let commandId: UUID
    let amountUsd: String
    let reason: String
}

struct RemoteExecuteRefundBody: Codable, Sendable {
    let approvalId: UUID
    let commandId: UUID
    let cashSessionId: UUID
    let amountUsd: String
    let reason: String
    let evidenceReference: String?
}

struct RemoteRefundRequestWriteResult: Decodable, Sendable {
    struct Data: Decodable, Sendable { let id: UUID; let status: String; let idempotentReplay: Bool }
    let data: Data
}

enum RemoteRefundCommand: Codable, Sendable {
    case request(saleID: UUID, paymentEventID: UUID, body: RemoteRequestRefundBody)
    case decide(localID: UUID, saleID: UUID, approvalID: UUID, body: RemoteApprovalDecisionBody)
    case execute(saleID: UUID, paymentEventID: UUID, body: RemoteExecuteRefundBody)

    var id: UUID {
        switch self {
        case .request(_, _, let body): body.commandId
        case .decide(let localID, _, _, _): localID
        case .execute(_, _, let body): body.commandId
        }
    }

    var saleID: UUID {
        switch self {
        case .request(let saleID, _, _), .decide(_, let saleID, _, _), .execute(let saleID, _, _): saleID
        }
    }
}

enum RemotePaymentCommand: Codable, Sendable {
    case collect(RemoteCollectPaymentBody)
    case resolve(saleID: UUID, attemptID: UUID, body: RemoteResolvePaymentBody)

    var id: UUID {
        switch self {
        case .collect(let body): body.commandId
        case .resolve(_, _, let body): body.commandId
        }
    }

    var saleID: UUID {
        switch self {
        case .collect(let body): body.saleId
        case .resolve(let saleID, _, _): saleID
        }
    }
}

struct RemoteFinancialWriteResult: Decodable, Sendable {
    struct Data: Decodable, Sendable { let id: UUID; let idempotentReplay: Bool }
    let data: Data
}

struct RemoteApprovalDecisionBody: Codable, Sendable {
    let branchId: UUID
    let decision: String
    let reason: String
}

struct RemoteApprovalDecisionResult: Decodable, Sendable {
    struct Data: Decodable, Sendable { let id: UUID; let status: String }
    let data: Data
}

struct RemoteCashApprovalCommand: Codable, Sendable, Identifiable {
    let id: UUID
    let approvalId: UUID
    let sessionId: UUID
    let decision: String
    let reason: String
}

struct RemoteDeviceCapabilities: Decodable, Sendable {
    let mode: String
    let physicalHardwareConnected: Bool
    let scenarios: [String]
    let automaticReconciliation: Bool
}

struct RemoteDeviceResponse: Decodable, Sendable {
    struct Device: Decodable, Sendable {
        struct Outcome: Decodable, Sendable {
            let source: String
            let status: String
            let measuredL: String?
            let evidenceReference: String?
        }
        let mode: String
        let scenario: String
        let outcome: Outcome?
        let state: String
        let commandId: UUID
        let idempotentReplay: Bool
        let physicalHardwareConnected: Bool
    }
    let data: RemoteDispenseAuthorization
    let device: Device
}

enum RemoteMeterReadingSource: String, Encodable, Sendable {
    case manual
    case simulated
    case device
}

struct RemoteDataScope: Codable, Hashable, Sendable {
    let organizationId: UUID
    let userId: UUID
    let branchId: UUID?
}

struct CachedRemoteValue<Value: Codable>: Codable {
    let value: Value
    let savedAt: Date
    let isStale: Bool
}

struct RemoteDraft: Codable, Identifiable {
    let id: UUID
    let scope: RemoteDataScope
    let resource: String
    let idempotencyKey: UUID
    let payload: Data
    let savedAt: Date

    init(scope: RemoteDataScope, resource: String, payload: Data, id: UUID = UUID(), savedAt: Date = Date()) {
        self.id = id
        self.scope = scope
        self.resource = resource
        self.idempotencyKey = id
        self.payload = payload
        self.savedAt = savedAt
    }
}

enum RemoteAPIError: Error, LocalizedError {
    case invalidBaseURL
    case malformedResponse
    case transport
    case http(status: Int, code: String, message: String, correlationId: String?)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "La dirección del servidor no es válida o no usa una conexión segura."
        case .malformedResponse: return "El servidor devolvió una respuesta que la app no pudo interpretar."
        case .transport: return "No se pudo conectar con el servidor. Revisa la conexión e intenta de nuevo."
        case let .http(status, code, message, correlationId):
            let reference = correlationId.map { " · Ref. \($0)" } ?? ""
            return "\(message) (\(code), HTTP \(status)\(reference))"
        }
    }
}

@MainActor
protocol RemoteAuthenticationRepository {
    func authenticate(email: String, password: String) async throws -> RemoteIdentity
    func refreshSession() async throws -> RemoteSessionTokens
    func logout() async throws
}

@MainActor
protocol RemotePumpRepository {
    func posCatalog(branchId: UUID, query: String?, kind: String?, cursor: String?, includeInactive: Bool) async throws -> RemotePage<RemotePOSProduct>
    func posProduct(branchId: UUID, productId: UUID) async throws -> RemotePOSProduct
    func posLots(branchId: UUID, productId: UUID, cursor: String?) async throws -> RemotePage<RemotePOSLot>
    func publishPOSOffer(branchId: UUID, body: RemotePOSOfferBody) async throws -> RemotePOSWriteResult
    func receivePOSLot(branchId: UUID, body: RemotePOSReceiptBody) async throws -> RemotePOSWriteResult
    func createPOSSale(branchId: UUID, body: RemotePOSSaleBody) async throws -> RemoteFuelSale


    func fuelTaxPolicies(branchId: UUID) async throws -> RemoteFuelTaxPolicyPage
    func proposeFuelTax(branchId: UUID, body: RemoteFuelTaxProposalBody) async throws -> RemoteFuelTaxWriteResponse
    func approveFuelTax(branchId: UUID, proposalId: UUID, commandId: UUID) async throws -> RemoteFuelTaxWriteResponse

    func fuelSale(branchId: UUID, authorizationId: UUID) async throws -> RemoteFuelSale?
    func createFuelSale(branchId: UUID, authorizationId: UUID, commandId: UUID) async throws -> RemoteFuelSale
    func fuelSales(branchId: UUID, query: String?, cursor: String?) async throws -> RemotePage<RemoteFuelSaleSummary>
    func fuelSaleDetail(branchId: UUID, saleId: UUID) async throws -> RemoteFuelSale
    func createCombinedReceipt(branchId: UUID, body: RemoteCombinedReceiptBody) async throws -> RemoteCombinedInternalReceipt
    func combinedReceipt(branchId: UUID, receiptId: UUID) async throws -> RemoteCombinedInternalReceipt
    func combinedReceipt(branchId: UUID, saleId: UUID) async throws -> RemoteCombinedInternalReceipt?

    func deviceCapabilities() async throws -> RemoteDeviceCapabilities
    func deviceOperation(branchId: UUID, authorizationId: UUID, commandId: UUID, operation: String, expectedVersion: Int, scenario: String?) async throws -> RemoteDeviceResponse

    func dispensers(branchId: UUID, query: String?, cursor: String?, limit: Int) async throws -> RemotePage<RemoteDispenserSummary>
    func dispenser(branchId: UUID, dispenserId: UUID) async throws -> RemoteDispenserDetail
    func nozzleAvailability(branchId: UUID, nozzleId: UUID) async throws -> RemoteNozzleAvailability
    func nozzleMeterReadings(branchId: UUID, nozzleId: UUID) async throws -> RemoteNozzleMeterHistory
    func captureMeterBaseline(branchId: UUID, nozzleId: UUID, commandId: UUID, value: String, meterSerial: String?, source: RemoteMeterReadingSource, note: String?) async throws -> RemoteNozzleMeterReading
    func captureMeterReading(branchId: UUID, nozzleId: UUID, commandId: UUID, value: String, meterSerial: String?, expectedVersion: Int, source: RemoteMeterReadingSource) async throws -> RemoteNozzleMeterReading
    func createDispenseAuthorization(branchId: UUID, nozzleId: UUID, commandId: UUID, amountUsd: String?, volume: String?, volumeUnit: String?) async throws -> RemoteDispenseAuthorization
    func dispenseAuthorization(branchId: UUID, authorizationId: UUID) async throws -> RemoteDispenseAuthorization
    func dispenseAuthorizations(branchId: UUID, status: String?, cursor: String?, limit: Int) async throws -> RemotePage<RemoteDispenseAuthorization>
    func startDispense(branchId: UUID, authorizationId: UUID, commandId: UUID, expectedVersion: Int) async throws -> RemoteDispenseAuthorization
    func reportDispenseProgress(branchId: UUID, authorizationId: UUID, commandId: UUID, quantity: String, unit: String, expectedVersion: Int) async throws -> RemoteDispenseAuthorization
    func completeDispense(branchId: UUID, authorizationId: UUID, commandId: UUID, quantity: String, unit: String, expectedVersion: Int, documentReference: String?) async throws -> RemoteDispenseAuthorization
    func cancelDispense(branchId: UUID, authorizationId: UUID, commandId: UUID, expectedVersion: Int, reason: String) async throws -> RemoteDispenseAuthorization
    func markDispenseUnknown(branchId: UUID, authorizationId: UUID, commandId: UUID, expectedVersion: Int, reason: String) async throws -> RemoteDispenseAuthorization
    func reconcileDispenseNoFlow(branchId: UUID, authorizationId: UUID, commandId: UUID, expectedVersion: Int, evidenceReference: String, reason: String) async throws -> RemoteDispenseAuthorization
}

@MainActor
protocol RemoteTankRepository {
    func tanks(branchId: UUID, query: String?, status: String?, cursor: String?, limit: Int) async throws -> RemotePage<RemoteTankSummary>
    func tank(branchId: UUID, tankId: UUID) async throws -> RemoteTankDetail
    func inventoryBalance(branchId: UUID, tankId: UUID) async throws -> RemoteTankInventorySnapshot
    func inventoryMovements(branchId: UUID, tankId: UUID, cursor: String?, limit: Int) async throws -> RemotePage<RemoteInventoryMovement>
}

@MainActor
protocol RemoteBranchRepository {
    func branches(query: String?, status: String?, cursor: String?, limit: Int) async throws -> RemotePage<RemoteBranchSummary>
    func branchDetail(branchID: UUID) async throws -> RemoteBranchDetail
    func createBranchDraft(_ input: RemoteCreateBranchDraft) async throws -> RemoteBranchSummary
    func branchReadiness(branchID: UUID) async throws -> RemoteBranchReadiness
    func saveOnboardingStep(branchID: UUID, expectedVersion: Int, step: String, data: RemoteBranchOnboardingData) async throws
    func activateBranch(branchID: UUID, expectedVersion: Int) async throws
    func fuelProducts(cursor: String?) async throws -> RemotePage<RemoteFuelProductSummary>
    func branchConfiguration(branchID: UUID) async throws -> RemoteBranchConfiguration
    func createFuelProduct(_ input: RemoteCreateFuelProduct) async throws
    func enableFuelOffer(branchID: UUID, fuelProductID: UUID) async throws
    func employees(branchID: UUID, cursor: String?) async throws -> RemotePage<RemoteEmployeeSummary>
    func createEmployee(branchID: UUID, input: RemoteCreateEmployee) async throws
    func fuelPriceBoard(branchID: UUID) async throws -> RemoteBranchFuelPriceBoard
    func fuelPriceProposals(branchID: UUID) async throws -> [RemoteFuelPriceProposal]
    func createFuelPriceProposal(branchID: UUID, input: RemoteCreateFuelPriceProposal) async throws
}

@MainActor
protocol RemoteCutRepository {
    func dailyCuts(branchID: UUID, date: String) async throws -> [RemoteOperationalCut]
    func generateDailyCuts(branchID: UUID, date: String) async throws -> [RemoteGeneratedCut]
    func cutAssets(branchID: UUID, cutID: UUID) async throws -> RemoteCutAssets
    func openCut(branchID: UUID, cutID: UUID, expectedVersion: Int) async throws -> RemoteCutOpenResult
    func captureCutMeter(branchID: UUID, cutID: UUID, nozzleID: UUID, readingID: UUID, expectedVersion: Int) async throws -> RemoteCutCaptureResult
    func cutProgress(branchID: UUID, cutID: UUID) async throws -> RemoteCutProgress
    func measureCutTank(branchID: UUID, cutID: UUID, tankID: UUID, expectedVersion: Int, measuredLiters: String, waterLiters: String?, temperatureC: String?, observedAt: Date) async throws -> RemoteCutTankResult
    func prepareCut(branchID: UUID, cutID: UUID, expectedVersion: Int) async throws -> RemoteCutPrepareResult
    func cutReconciliation(branchID: UUID, cutID: UUID) async throws -> RemoteCutReconciliation
    func reviewCut(branchID: UUID, cutID: UUID, expectedVersion: Int, reason: String) async throws -> RemoteCutTransitionResult
    func closeCut(branchID: UUID, cutID: UUID, expectedVersion: Int) async throws -> RemoteCutTransitionResult
}

/// Stores the rotating API tokens in Keychain. This store is separate from the
/// legacy demo's local password vault and repository JSON.
@MainActor
final class RemoteSessionStore {
    private let service = "sv.com.dlc.gasolineras.api-session"
    private let account = "current"

    func load() -> RemoteSessionTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        let decoder = JSONDecoder()
        configureDLCDateDecoding(decoder)
        return try? decoder.decode(RemoteSessionTokens.self, from: data)
    }

    func save(_ tokens: RemoteSessionTokens) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(tokens)
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(key as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = key
            update.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "No se pudo guardar la sesión segura (Keychain \(status))." }
    }
}

/// Offline support stores server reads as a cache and unsent commands as drafts.
/// Neither store changes the legacy repository or claims that a draft was sent.
@MainActor
final class RemoteOfflineStore {
    private let fileManager = FileManager.default

    func saveRead<Value: Codable>(_ value: Value, resource: String, scope: RemoteDataScope) throws {
        let url = try cacheURL(resource: resource, scope: scope)
        let record = CachedRemoteValue(value: value, savedAt: Date(), isStale: false)
        let data = try encoder().encode(record)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func loadRead<Value: Codable>(resource: String, scope: RemoteDataScope, as type: Value.Type, maxAge: TimeInterval) -> CachedRemoteValue<Value>? {
        guard let url = try? cacheURL(resource: resource, scope: scope),
              let data = try? Data(contentsOf: url),
              let record = try? decoder().decode(CachedRemoteValue<Value>.self, from: data) else { return nil }
        return CachedRemoteValue(value: record.value, savedAt: record.savedAt, isStale: Date().timeIntervalSince(record.savedAt) > maxAge)
    }

    func saveDraft(_ draft: RemoteDraft) throws {
        let directory = try draftsDirectory(scope: draft.scope)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder().encode(draft).write(
            to: directory.appendingPathComponent("\(draft.id.uuidString.lowercased()).json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    func drafts(scope: RemoteDataScope) -> [RemoteDraft] {
        guard let directory = try? draftsDirectory(scope: scope),
              let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let draft = try? decoder().decode(RemoteDraft.self, from: data),
                  draft.scope == scope else { return nil }
            return draft
        }.sorted { $0.savedAt < $1.savedAt }
    }

    func checkedDrafts(scope: RemoteDataScope) throws -> [RemoteDraft] {
        let directory = try draftsDirectory(scope: scope)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try urls.filter { $0.pathExtension == "json" }.map { url in
            let draft = try decoder().decode(RemoteDraft.self, from: Data(contentsOf: url))
            guard draft.scope == scope else { throw RemoteAPIError.malformedResponse }
            return draft
        }.sorted { $0.savedAt < $1.savedAt }
    }

    func removeDraft(id: UUID, scope: RemoteDataScope) throws {
        try fileManager.removeItem(at: draftsDirectory(scope: scope).appendingPathComponent("\(id.uuidString.lowercased()).json"))
    }

    private func cacheURL(resource: String, scope: RemoteDataScope) throws -> URL {
        guard !resource.isEmpty, resource.count <= 96,
              resource.allSatisfy({ $0.isLetter || $0.isNumber || "-_ .".contains($0) }),
              !resource.contains("..") else { throw RemoteAPIError.malformedResponse }
        return try cacheRoot(scope: scope).appendingPathComponent("\(resource).json")
    }

    private func cacheRoot(scope: RemoteDataScope) throws -> URL {
        let root = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return root.appendingPathComponent("DLCRemoteReads", isDirectory: true)
            .appendingPathComponent(scope.organizationId.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(scope.userId.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(scope.branchId?.uuidString.lowercased() ?? "network", isDirectory: true)
    }

    private func draftsDirectory(scope: RemoteDataScope) throws -> URL {
        let root = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return root.appendingPathComponent("DLCRemoteDrafts", isDirectory: true)
            .appendingPathComponent(scope.organizationId.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(scope.userId.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(scope.branchId?.uuidString.lowercased() ?? "network", isDirectory: true)
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        configureDLCDateDecoding(decoder)
        return decoder
    }
}

@MainActor
final class RemoteAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokenStore: RemoteSessionStore
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()
    private var refreshTask: Task<RemoteSessionTokens, Error>?

    init(baseURL: URL, tokenStore: RemoteSessionStore = RemoteSessionStore(), session: URLSession = .shared) throws {
        let host = baseURL.host?.lowercased()
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard baseURL.scheme?.lowercased() == "https" || (isLoopback && baseURL.scheme?.lowercased() == "http") else {
            throw RemoteAPIError.invalidBaseURL
        }
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.session = session
        decoder = JSONDecoder()
        configureDLCDateDecoding(decoder)
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .useDefaultKeys
    }

    func login(email: String, password: String, deviceLabel: String = "iOS") async throws -> RemoteSessionTokens {
        struct Body: Encodable { let email: String; let password: String; let deviceLabel: String }
        let body = try encoder.encode(Body(email: email, password: password, deviceLabel: deviceLabel))
        let tokens: RemoteSessionTokens = try await send(path: "auth/login", method: "POST", body: body, requiresSession: false)
        try tokenStore.save(tokens)
        return tokens
    }

    func refreshSession() async throws -> RemoteSessionTokens {
        if let refreshTask { return try await refreshTask.value }
        guard let current = tokenStore.load() else { throw RemoteAPIError.http(status: 401, code: "UNAUTHENTICATED", message: "Inicia sesión nuevamente.", correlationId: nil) }
        let task = Task { @MainActor [weak self] () throws -> RemoteSessionTokens in
            guard let self else { throw RemoteAPIError.transport }
            struct Body: Encodable { let refreshToken: String }
            let body = try self.encoder.encode(Body(refreshToken: current.refreshToken))
            let tokens: RemoteSessionTokens = try await self.send(path: "auth/refresh", method: "POST", body: body, requiresSession: false)
            try self.tokenStore.save(tokens)
            return tokens
        }
        refreshTask = task
        do {
            let tokens = try await task.value
            refreshTask = nil
            return tokens
        } catch {
            refreshTask = nil
            throw error
        }
    }

    func currentIdentity() async throws -> RemoteIdentity {
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        let response: Envelope<RemoteIdentity> = try await send(path: "auth/me", method: "GET")
        return response.data
    }

    func capabilities(branchId: UUID? = nil) async throws -> RemoteCapabilities {
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        let query = branchId.map { [URLQueryItem(name: "branchId", value: $0.uuidString.lowercased())] } ?? []
        let response: Envelope<RemoteCapabilities> = try await send(path: "auth/me/capabilities", method: "GET", queryItems: query)
        return response.data
    }

    func logout() async throws {
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        struct Result: Decodable { let revoked: Bool }
        let _: Envelope<Result> = try await send(path: "auth/logout", method: "POST")
        tokenStore.clear()
    }

    func nozzleMeterReadings(branchId: UUID, nozzleId: UUID) async throws -> RemoteNozzleMeterHistory {
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        let path = meterPath(branchId, nozzleId, suffix: "meter-readings")
        let response: Envelope<RemoteNozzleMeterHistory> = try await send(path: path, method: "GET")
        return response.data
    }

    func dispensers(branchId: UUID, query: String?, cursor: String?, limit: Int) async throws -> RemotePage<RemoteDispenserSummary> {
        let boundedLimit = min(max(limit, 1), 200)
        var items = [URLQueryItem(name: "limit", value: String(boundedLimit))]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { items.append(URLQueryItem(name: "query", value: query)) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(path: "branches/\(branchId.uuidString.lowercased())/dispensers", method: "GET", queryItems: items)
    }

    func dispenser(branchId: UUID, dispenserId: UUID) async throws -> RemoteDispenserDetail {
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        let path = "branches/\(branchId.uuidString.lowercased())/dispensers/\(dispenserId.uuidString.lowercased())"
        let response: Envelope<RemoteDispenserDetail> = try await send(path: path, method: "GET")
        return response.data
    }

    func nozzleAvailability(branchId: UUID, nozzleId: UUID) async throws -> RemoteNozzleAvailability {
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        let path = "branches/\(branchId.uuidString.lowercased())/nozzles/\(nozzleId.uuidString.lowercased())/availability"
        let response: Envelope<RemoteNozzleAvailability> = try await send(path: path, method: "GET")
        return response.data
    }

    func tanks(branchId: UUID, query: String?, status: String?, cursor: String?, limit: Int) async throws -> RemotePage<RemoteTankSummary> {
        let boundedLimit = min(max(limit, 1), 200)
        var items = [URLQueryItem(name: "limit", value: String(boundedLimit))]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { items.append(URLQueryItem(name: "query", value: query)) }
        if let status { items.append(URLQueryItem(name: "status", value: status)) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(path: "branches/\(branchId.uuidString.lowercased())/tanks", method: "GET", queryItems: items)
    }

    func tank(branchId: UUID, tankId: UUID) async throws -> RemoteTankDetail {
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        let response: Envelope<RemoteTankDetail> = try await send(path: "branches/\(branchId.uuidString.lowercased())/tanks/\(tankId.uuidString.lowercased())", method: "GET")
        return response.data
    }

    func inventoryBalance(branchId: UUID, tankId: UUID) async throws -> RemoteTankInventorySnapshot {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/tanks/\(tankId.uuidString.lowercased())/inventory", method: "GET")
    }

    func inventoryMovements(branchId: UUID, tankId: UUID, cursor: String?, limit: Int) async throws -> RemotePage<RemoteInventoryMovement> {
        let boundedLimit = min(max(limit, 1), 100)
        var items = [URLQueryItem(name: "limit", value: String(boundedLimit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(path: "branches/\(branchId.uuidString.lowercased())/tanks/\(tankId.uuidString.lowercased())/inventory/movements", method: "GET", queryItems: items)
    }

    func branches(query: String?, status: String?, cursor: String?, limit: Int) async throws -> RemotePage<RemoteBranchSummary> {
        let boundedLimit = min(max(limit, 1), 100)
        var items = [URLQueryItem(name: "limit", value: String(boundedLimit))]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { items.append(URLQueryItem(name: "query", value: query)) }
        if let status { items.append(URLQueryItem(name: "status", value: status)) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(path: "branches", method: "GET", queryItems: items)
    }

    func branchDetail(branchID: UUID) async throws -> RemoteBranchDetail {
        try await send(path: "branches/\(branchID.uuidString.lowercased())", method: "GET")
    }

    func createBranchDraft(_ input: RemoteCreateBranchDraft) async throws -> RemoteBranchSummary {
        try await send(path: "branches", method: "POST", body: try encoder.encode(input))
    }

    func branchReadiness(branchID: UUID) async throws -> RemoteBranchReadiness {
        try await send(path: "branches/\(branchID.uuidString.lowercased())/readiness", method: "GET")
    }

    func saveOnboardingStep(branchID: UUID, expectedVersion: Int, step: String, data: RemoteBranchOnboardingData) async throws {
        struct Body: Encodable { let expectedVersion: Int; let step: String; let data: RemoteBranchOnboardingData }
        struct Result: Decodable { let id: UUID; let status: String; let onboardingVersion: Int; let updatedAt: Date }
        let body = try encoder.encode(Body(expectedVersion: expectedVersion, step: step, data: data))
        let _: Result = try await send(path: "branches/\(branchID.uuidString.lowercased())/onboarding", method: "PATCH", body: body)
    }

    func activateBranch(branchID: UUID, expectedVersion: Int) async throws {
        struct Body: Encodable { let expectedVersion: Int }
        struct Result: Decodable { let id: UUID; let status: String; let activatedAt: Date }
        let _: Result = try await send(path: "branches/\(branchID.uuidString.lowercased())/activate", method: "POST", body: try encoder.encode(Body(expectedVersion: expectedVersion)))
    }

    func fuelProducts(cursor: String?) async throws -> RemotePage<RemoteFuelProductSummary> {
        var items = [URLQueryItem(name: "status", value: "active"), URLQueryItem(name: "limit", value: "100")]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(path: "fuel-products", method: "GET", queryItems: items)
    }

    func branchConfiguration(branchID: UUID) async throws -> RemoteBranchConfiguration {
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        let result: Envelope<RemoteBranchConfiguration> = try await send(path: "branches/\(branchID.uuidString.lowercased())/configuration", method: "GET")
        return result.data
    }

    func createFuelProduct(_ input: RemoteCreateFuelProduct) async throws {
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        let body = try encoder.encode(input)
        let _: Envelope<RemoteFuelProductSummary> = try await send(path: "fuel-products", method: "POST", body: body)
    }

    func enableFuelOffer(branchID: UUID, fuelProductID: UUID) async throws {
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        let _: Envelope<RemoteFuelOfferActivationResult> = try await send(path: "branches/\(branchID.uuidString.lowercased())/fuel-offers/\(fuelProductID.uuidString.lowercased())", method: "PUT", body: Data("{}".utf8))
    }

    func employees(branchID: UUID, cursor: String?) async throws -> RemotePage<RemoteEmployeeSummary> {
        var items = [URLQueryItem(name: "status", value: "active"), URLQueryItem(name: "limit", value: "100")]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(path: "branches/\(branchID.uuidString.lowercased())/staff/employees", method: "GET", queryItems: items)
    }

    func createEmployee(branchID: UUID, input: RemoteCreateEmployee) async throws {
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        struct Result: Decodable { let id: UUID; let status: String }
        let _: Envelope<Result> = try await send(path: "branches/\(branchID.uuidString.lowercased())/staff/employees", method: "POST", body: try encoder.encode(input))
    }

    func fuelPriceBoard(branchID: UUID) async throws -> RemoteBranchFuelPriceBoard {
        try await send(path: "branches/\(branchID.uuidString.lowercased())/fuel-prices", method: "GET")
    }

    func fuelPriceProposals(branchID: UUID) async throws -> [RemoteFuelPriceProposal] {
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        let result: Envelope<[RemoteFuelPriceProposal]> = try await send(path: "branches/\(branchID.uuidString.lowercased())/fuel-price-proposals", method: "GET")
        return result.data
    }

    func createFuelPriceProposal(branchID: UUID, input: RemoteCreateFuelPriceProposal) async throws {
        let _: RemoteFuelPriceProposal = try await send(path: "branches/\(branchID.uuidString.lowercased())/fuel-price-proposals", method: "POST", body: try encoder.encode(input))
    }

    func branchDashboard(branchID: UUID) async throws -> RemoteBranchDashboard {
        struct Envelope: Decodable { let data: RemoteBranchDashboard }
        let response: Envelope = try await send(path: "metrics/branches/\(branchID.uuidString.lowercased())/dashboard", method: "GET")
        return response.data
    }

    func dailyCuts(branchID: UUID, date: String) async throws -> [RemoteOperationalCut] {
        struct Envelope: Decodable { let data: [RemoteOperationalCut] }
        let response: Envelope = try await send(
            path: "branches/\(branchID.uuidString.lowercased())/cuts",
            method: "GET",
            queryItems: [URLQueryItem(name: "date", value: date)]
        )
        return response.data
    }

    func generateDailyCuts(branchID: UUID, date: String) async throws -> [RemoteGeneratedCut] {
        struct Body: Encodable { let operationalDate: String }
        struct Envelope: Decodable { let data: [RemoteGeneratedCut] }
        let response: Envelope = try await send(
            path: "branches/\(branchID.uuidString.lowercased())/cuts/generate",
            method: "POST",
            body: try encoder.encode(Body(operationalDate: date))
        )
        return response.data
    }

    func cutAssets(branchID: UUID, cutID: UUID) async throws -> RemoteCutAssets {
        struct Envelope: Decodable { let data: RemoteCutAssets }
        let response: Envelope = try await send(
            path: "branches/\(branchID.uuidString.lowercased())/cuts/\(cutID.uuidString.lowercased())/assets",
            method: "GET"
        )
        return response.data
    }

    func openCut(branchID: UUID, cutID: UUID, expectedVersion: Int) async throws -> RemoteCutOpenResult {
        struct Body: Encodable { let expectedVersion: Int }
        struct Envelope: Decodable { let data: RemoteCutOpenResult }
        let response: Envelope = try await send(
            path: "branches/\(branchID.uuidString.lowercased())/cuts/\(cutID.uuidString.lowercased())/open",
            method: "POST",
            body: try encoder.encode(Body(expectedVersion: expectedVersion))
        )
        return response.data
    }

    func captureCutMeter(branchID: UUID, cutID: UUID, nozzleID: UUID, readingID: UUID, expectedVersion: Int) async throws -> RemoteCutCaptureResult {
        struct Body: Encodable { let nozzleId: UUID; let readingId: UUID; let expectedVersion: Int }
        struct Envelope: Decodable { let data: RemoteCutCaptureResult }
        let response: Envelope = try await send(
            path: "branches/\(branchID.uuidString.lowercased())/cuts/\(cutID.uuidString.lowercased())/meters",
            method: "POST",
            body: try encoder.encode(Body(nozzleId: nozzleID, readingId: readingID, expectedVersion: expectedVersion))
        )
        return response.data
    }

    func cutProgress(branchID: UUID, cutID: UUID) async throws -> RemoteCutProgress {
        struct Envelope: Decodable { let data: RemoteCutProgress }
        let response: Envelope = try await send(
            path: "branches/\(branchID.uuidString.lowercased())/cuts/\(cutID.uuidString.lowercased())/progress",
            method: "GET"
        )
        return response.data
    }

    func measureCutTank(branchID: UUID, cutID: UUID, tankID: UUID, expectedVersion: Int, measuredLiters: String, waterLiters: String?, temperatureC: String?, observedAt: Date) async throws -> RemoteCutTankResult {
        struct Body: Encodable {
            let tankId: UUID
            let expectedVersion: Int
            let measuredL: String
            let waterL: String?
            let temperatureC: String?
            let observedAt: String
            let source: String
        }
        struct Envelope: Decodable { let data: RemoteCutTankResult }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body = Body(
            tankId: tankID,
            expectedVersion: expectedVersion,
            measuredL: measuredLiters,
            waterL: waterLiters,
            temperatureC: temperatureC,
            observedAt: formatter.string(from: observedAt),
            source: "manual"
        )
        let response: Envelope = try await send(
            path: "branches/\(branchID.uuidString.lowercased())/cuts/\(cutID.uuidString.lowercased())/tanks",
            method: "POST",
            body: try encoder.encode(body)
        )
        return response.data
    }

    func prepareCut(branchID: UUID, cutID: UUID, expectedVersion: Int) async throws -> RemoteCutPrepareResult {
        struct Body: Encodable { let expectedVersion: Int }
        struct Envelope: Decodable { let data: RemoteCutPrepareResult }
        let response: Envelope = try await send(
            path: "branches/\(branchID.uuidString.lowercased())/cuts/\(cutID.uuidString.lowercased())/prepare",
            method: "POST",
            body: try encoder.encode(Body(expectedVersion: expectedVersion))
        )
        return response.data
    }

    func cutReconciliation(branchID: UUID, cutID: UUID) async throws -> RemoteCutReconciliation {
        struct Envelope: Decodable { let data: RemoteCutReconciliation }
        let response: Envelope = try await send(
            path: "branches/\(branchID.uuidString.lowercased())/cuts/\(cutID.uuidString.lowercased())/reconciliation",
            method: "GET"
        )
        return response.data
    }

    func reviewCut(branchID: UUID, cutID: UUID, expectedVersion: Int, reason: String) async throws -> RemoteCutTransitionResult {
        struct Body: Encodable { let expectedVersion: Int; let reason: String }
        struct Envelope: Decodable { let data: RemoteCutTransitionResult }
        let response: Envelope = try await send(
            path: "branches/\(branchID.uuidString.lowercased())/cuts/\(cutID.uuidString.lowercased())/review",
            method: "POST",
            body: try encoder.encode(Body(expectedVersion: expectedVersion, reason: reason))
        )
        return response.data
    }

    func closeCut(branchID: UUID, cutID: UUID, expectedVersion: Int) async throws -> RemoteCutTransitionResult {
        struct Body: Encodable { let expectedVersion: Int }
        struct Envelope: Decodable { let data: RemoteCutTransitionResult }
        let response: Envelope = try await send(
            path: "branches/\(branchID.uuidString.lowercased())/cuts/\(cutID.uuidString.lowercased())/close",
            method: "POST",
            body: try encoder.encode(Body(expectedVersion: expectedVersion))
        )
        return response.data
    }

    func networkDashboard(days: Int, branchID: UUID? = nil) async throws -> RemoteNetworkDashboard {
        struct Envelope: Decodable { let data: RemoteNetworkDashboard }
        var items = [URLQueryItem(name: "days", value: String(days))]
        if let branchID { items.append(URLQueryItem(name: "branchId", value: branchID.uuidString.lowercased())) }
        let response: Envelope = try await send(path: "metrics/network/dashboard", method: "GET", queryItems: items)
        return response.data
    }

    func incidentDetail(branchID: UUID, incidentID: UUID) async throws -> RemoteIncidentDetail {
        struct Envelope: Decodable { let data: RemoteIncidentDetail }
        let response: Envelope = try await send(path: "branches/\(branchID.uuidString.lowercased())/incidents/\(incidentID.uuidString.lowercased())", method: "GET")
        return response.data
    }

    func reviewAnomaly(branchID: UUID, alertID: UUID, expectedStatus: String, nextStatus: String, note: String) async throws {
        struct Body: Encodable { let expectedStatus: String; let nextStatus: String; let note: String }
        struct Envelope: Decodable { struct Data: Decodable { let id: UUID; let status: String }; let data: Data }
        let _: Envelope = try await send(path: "branches/\(branchID.uuidString.lowercased())/anomalies/\(alertID.uuidString.lowercased())/review",
                                         method: "POST", body: encoder.encode(Body(expectedStatus: expectedStatus, nextStatus: nextStatus, note: note)))
    }

    func createReport(branchID: UUID, type: String, from: String, to: String,
                      productId: UUID? = nil, dispenserId: UUID? = nil, serviceMode: String? = nil,
                      groupBy: String? = nil, status: String? = nil) async throws -> RemoteReportRunCreated {
        struct Body: Encodable {
            let type: String; let from: String; let to: String; let productId: UUID?
            let dispenserId: UUID?; let serviceMode: String?; let groupBy: String?; let status: String?; let commandId: UUID
        }
        struct Envelope: Decodable { let data: RemoteReportRunCreated }
        let response: Envelope = try await send(path: "branches/\(branchID.uuidString.lowercased())/reports/runs",method: "POST",
            body: encoder.encode(Body(type: type, from: from, to: to, productId: productId,
                dispenserId: dispenserId, serviceMode: serviceMode, groupBy: groupBy, status: status, commandId: UUID())))
        return response.data
    }

    func reportPage(branchID: UUID, runID: UUID, offset: Int = 0) async throws -> RemoteReportPage {
        struct Envelope: Decodable { let data: RemoteReportPage }
        let response: Envelope = try await send(path: "branches/\(branchID.uuidString.lowercased())/reports/runs/\(runID.uuidString.lowercased())",
            method: "GET",queryItems:[URLQueryItem(name:"offset",value:String(offset))])
        return response.data
    }

    func reportCSV(branchID: UUID, runID: UUID) async throws -> URL {
        try await reportExport(branchID: branchID, runID: runID, format: "csv")
    }

    func reportExport(branchID: UUID, runID: UUID, format: String,
                      onProgress: ((UUID?, String) -> Void)? = nil) async throws -> URL {
        guard ["csv", "xlsx", "pdf"].contains(format) else { throw RemoteAPIError.invalidBaseURL }
        struct CreateBody: Encodable { let format: String; let commandId: UUID }
        struct CreateEnvelope: Decodable { struct Data: Decodable { let id: UUID }; let data: Data }
        struct StatusEnvelope: Decodable {
            struct Data: Decodable {
                struct Progress: Decodable { let completed: Int; let total: Int; let percent: Int }
                let state: String; let error: String?; let progress: Progress
            }
            let data: Data
        }
        let created: CreateEnvelope = try await send(
            path: "branches/\(branchID.uuidString.lowercased())/reports/runs/\(runID.uuidString.lowercased())/exports",
            method: "POST", body: encoder.encode(CreateBody(format: format, commandId: UUID())))
        onProgress?(created.data.id, "En cola")
        var ready = false
        for _ in 0..<90 {
            let status: StatusEnvelope = try await send(
                path: "branches/\(branchID.uuidString.lowercased())/reports/exports/\(created.data.id.uuidString.lowercased())",
                method: "GET")
            let progress = status.data.progress
            let message = status.data.state == "queued" ? "En cola" :
                "Generando archivo · \(progress.completed.formatted()) de \(progress.total.formatted()) (\(progress.percent)%)"
            onProgress?(created.data.id, message)
            if status.data.state == "succeeded" { ready = true; break }
            if status.data.state == "cancelled" { onProgress?(nil, "Cancelada"); throw CancellationError() }
            if status.data.state == "failed" {
                throw RemoteAPIError.http(status: 422, code: "REPORT_EXPORT_FAILED",
                    message: status.data.error ?? "No se pudo generar el reporte.", correlationId: nil)
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard ready else {
            throw RemoteAPIError.http(status: 408, code: "REPORT_EXPORT_TIMEOUT",
                message: "La exportación sigue en proceso. Vuelve a intentarlo en unos momentos.", correlationId: nil)
        }
        guard let token = tokenStore.load() else {
            throw RemoteAPIError.http(status: 401, code: "UNAUTHENTICATED", message: "Inicia sesión nuevamente.", correlationId: nil)
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw RemoteAPIError.invalidBaseURL
        }
        let prefix = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = "\(prefix)/api/v1/branches/\(branchID.uuidString.lowercased())/reports/exports/\(created.data.id.uuidString.lowercased())/download"
        guard let url = components.url else { throw RemoteAPIError.invalidBaseURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let mimeType: String
        switch format {
        case "xlsx": mimeType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "pdf": mimeType = "application/pdf"
        default: mimeType = "text/csv"
        }
        request.setValue(mimeType, forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RemoteAPIError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 500,
                code: "REPORT_EXPORT", message: "No se pudo exportar el reporte. Comprueba tus permisos.", correlationId: nil)
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("dlc-report-\(runID.uuidString.lowercased()).\(format)")
        try data.write(to: destination, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? destination.setResourceValues(values)
        return destination
    }

    func cancelReportExport(branchID: UUID, exportID: UUID) async throws {
        struct Envelope: Decodable { struct Data: Decodable { let id: UUID; let state: String; let cancelled: Bool }; let data: Data }
        let _: Envelope = try await send(path: "branches/\(branchID.uuidString.lowercased())/reports/exports/\(exportID.uuidString.lowercased())/cancel",
            method: "POST")
    }

    func savedReportFilters(branchID: UUID) async throws -> [RemoteSavedReportFilter] {
        struct Envelope: Decodable { let data: [RemoteSavedReportFilter] }
        let response: Envelope = try await send(path: "branches/\(branchID.uuidString.lowercased())/reports/saved-filters", method: "GET")
        return response.data
    }

    func saveReportFilter(branchID: UUID, name: String, type: String, from: String, to: String,
                          productId: UUID? = nil, dispenserId: UUID? = nil, serviceMode: String? = nil,
                          groupBy: String? = nil, status: String? = nil) async throws {
        struct Body: Encodable {
            let name: String; let type: String; let from: String; let to: String
            let productId: UUID?; let dispenserId: UUID?; let serviceMode: String?; let groupBy: String?; let status: String?
        }
        struct Envelope: Decodable { struct Data: Decodable { let id: UUID }; let data: Data }
        let _: Envelope = try await send(path: "branches/\(branchID.uuidString.lowercased())/reports/saved-filters", method: "POST",
            body: encoder.encode(Body(name: name, type: type, from: from, to: to,
                productId: productId, dispenserId: dispenserId, serviceMode: serviceMode, groupBy: groupBy, status: status)))
    }

    func deleteReportFilter(branchID: UUID, filterID: UUID) async throws {
        struct Envelope: Decodable { struct Data: Decodable { let id: UUID; let deleted: Bool }; let data: Data }
        let _: Envelope = try await send(path: "branches/\(branchID.uuidString.lowercased())/reports/saved-filters/\(filterID.uuidString.lowercased())",
            method: "DELETE")
    }

    func captureMeterBaseline(branchId: UUID, nozzleId: UUID, commandId: UUID, value: String, meterSerial: String?, source: RemoteMeterReadingSource = .manual, note: String? = nil) async throws -> RemoteNozzleMeterReading {
        struct Body: Encodable { let commandId: UUID; let value: String; let meterSerial: String?; let source: RemoteMeterReadingSource; let expectedVersion: Int; let note: String? }
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        let body = try encoder.encode(Body(commandId: commandId, value: value, meterSerial: meterSerial, source: source, expectedVersion: 0, note: note))
        let response: Envelope<RemoteNozzleMeterReading> = try await send(path: meterPath(branchId, nozzleId, suffix: "meter-readings/baseline"), method: "POST", body: body)
        return response.data
    }

    func captureMeterReading(branchId: UUID, nozzleId: UUID, commandId: UUID, value: String, meterSerial: String?, expectedVersion: Int, source: RemoteMeterReadingSource = .manual) async throws -> RemoteNozzleMeterReading {
        struct Body: Encodable { let commandId: UUID; let value: String; let meterSerial: String?; let source: RemoteMeterReadingSource; let expectedVersion: Int }
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        let body = try encoder.encode(Body(commandId: commandId, value: value, meterSerial: meterSerial, source: source, expectedVersion: expectedVersion))
        let response: Envelope<RemoteNozzleMeterReading> = try await send(path: meterPath(branchId, nozzleId, suffix: "meter-readings"), method: "POST", body: body)
        return response.data
    }

    func recordMeterChange(branchId: UUID, nozzleId: UUID, commandId: UUID, value: String, oldSerial: String?, newSerial: String, reason: String, expectedVersion: Int, source: RemoteMeterReadingSource = .manual) async throws -> RemoteNozzleMeterReading {
        struct Body: Encodable { let commandId: UUID; let value: String; let reason: String; let newSerial: String; let oldSerial: String?; let source: RemoteMeterReadingSource; let expectedVersion: Int }
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        let body = try encoder.encode(Body(commandId: commandId, value: value, reason: reason, newSerial: newSerial, oldSerial: oldSerial, source: source, expectedVersion: expectedVersion))
        let response: Envelope<RemoteNozzleMeterReading> = try await send(path: meterPath(branchId, nozzleId, suffix: "meter-changes"), method: "POST", body: body)
        return response.data
    }

    func deviceCapabilities() async throws -> RemoteDeviceCapabilities {
        struct Envelope: Decodable { let data: RemoteDeviceCapabilities }
        let response: Envelope = try await send(path: "dispense-device/capabilities", method: "GET")
        return response.data
    }

    func deviceOperation(branchId: UUID, authorizationId: UUID, commandId: UUID, operation: String, expectedVersion: Int, scenario: String?) async throws -> RemoteDeviceResponse {
        guard ["start", "query"].contains(operation) else { throw RemoteAPIError.invalidBaseURL }
        struct Body: Encodable { let commandId: UUID; let expectedVersion: Int; let scenario: String? }
        let body = try encoder.encode(Body(commandId: commandId, expectedVersion: expectedVersion, scenario: scenario))
        return try await send(path: dispensePath(branchId, authorizationId: authorizationId, nozzleId: nil, suffix: "device-\(operation)"), method: "POST", body: body)
    }

    func fuelTaxPolicies(branchId: UUID) async throws -> RemoteFuelTaxPolicyPage {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/fuel-tax-policies", method: "GET")
    }
    func proposeFuelTax(branchId: UUID, body: RemoteFuelTaxProposalBody) async throws -> RemoteFuelTaxWriteResponse {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/fuel-tax-policies/proposals", method: "POST", body: try encoder.encode(body))
    }
    func approveFuelTax(branchId: UUID, proposalId: UUID, commandId: UUID) async throws -> RemoteFuelTaxWriteResponse {
        struct Body: Encodable { let commandId: UUID }
        return try await send(path: "branches/\(branchId.uuidString.lowercased())/fuel-tax-policies/proposals/\(proposalId.uuidString.lowercased())/approve", method: "POST", body: try encoder.encode(Body(commandId: commandId)))
    }

    func posCatalog(branchId: UUID, query: String?, kind: String?, cursor: String?, includeInactive: Bool) async throws -> RemotePage<RemotePOSProduct> {
        var items = [URLQueryItem(name: "limit", value: "25"), URLQueryItem(name: "includeInactive", value: includeInactive ? "true" : "false")]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        if let kind { items.append(URLQueryItem(name: "kind", value: kind)) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(path: "branches/\(branchId.uuidString.lowercased())/pos/catalog", method: "GET", queryItems: items)
    }
    func posProduct(branchId: UUID, productId: UUID) async throws -> RemotePOSProduct {
        struct Envelope: Decodable { let data: RemotePOSProduct }
        let result: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/pos/catalog/\(productId.uuidString.lowercased())", method: "GET")
        return result.data
    }
    func posLots(branchId: UUID, productId: UUID, cursor: String?) async throws -> RemotePage<RemotePOSLot> {
        var items = [URLQueryItem(name: "limit", value: "25")]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(path: "branches/\(branchId.uuidString.lowercased())/pos/catalog/\(productId.uuidString.lowercased())/lots", method: "GET", queryItems: items)
    }
    func publishPOSOffer(branchId: UUID, body: RemotePOSOfferBody) async throws -> RemotePOSWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/pos/catalog/offers", method: "POST", body: try encoder.encode(body))
    }
    func receivePOSLot(branchId: UUID, body: RemotePOSReceiptBody) async throws -> RemotePOSWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/pos/stock/receipts", method: "POST", body: try encoder.encode(body))
    }
    func createPOSSale(branchId: UUID, body: RemotePOSSaleBody) async throws -> RemoteFuelSale {
        struct Envelope: Decodable { let data: RemoteFuelSale }
        let result: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/sales/pos", method: "POST", body: try encoder.encode(body))
        return result.data
    }

    func cashRegisters(branchId: UUID) async throws -> [RemoteCashRegister] {
        struct Envelope: Decodable { let data: [RemoteCashRegister] }
        let response: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/cash/registers", method: "GET")
        return response.data
    }

    func createCashRegister(branchId: UUID, body: RemoteCashRegisterBody) async throws -> RemoteCashRegisterWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/cash/registers", method: "POST", body: try encoder.encode(body))
    }

    func openCashSession(branchId: UUID, body: RemoteCashOpenBody) async throws -> RemoteCashWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/cash/sessions", method: "POST", body: try encoder.encode(body))
    }

    func cashSession(branchId: UUID, sessionID: UUID) async throws -> RemoteCashSession {
        struct Envelope: Decodable { let data: RemoteCashSession }
        let response: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/cash/sessions/\(sessionID.uuidString.lowercased())", method: "GET")
        return response.data
    }

    func cashMovements(branchId: UUID, sessionID: UUID, kind: String?, cursor: RemoteCashMovementCursor?, limit: Int = 30) async throws -> RemoteCashMovementPage {
        var items = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100)))]
        if let kind { items.append(URLQueryItem(name: "kind", value: kind)) }
        if let cursor {
            items.append(URLQueryItem(name: "beforeAt", value: cursor.beforeAt))
            items.append(URLQueryItem(name: "beforeId", value: cursor.beforeId.uuidString.lowercased()))
        }
        return try await send(path: "branches/\(branchId.uuidString.lowercased())/cash/sessions/\(sessionID.uuidString.lowercased())/movements", method: "GET", queryItems: items)
    }

    func createCashMovement(branchId: UUID, sessionID: UUID, body: RemoteCashMovementBody) async throws -> RemoteCashWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/cash/sessions/\(sessionID.uuidString.lowercased())/movements", method: "POST", body: try encoder.encode(body))
    }

    func closeCashSession(branchId: UUID, sessionID: UUID, body: RemoteCashCloseBody) async throws -> RemoteCashClosure {
        struct Envelope: Decodable { let data: RemoteCashClosure }
        let response: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/cash/sessions/\(sessionID.uuidString.lowercased())/close", method: "POST", body: try encoder.encode(body))
        return response.data
    }

    func cashReview(branchId: UUID, sessionID: UUID) async throws -> RemoteCashReview {
        struct Envelope: Decodable { let data: RemoteCashReview }
        let response: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/cash/sessions/\(sessionID.uuidString.lowercased())/review", method: "GET")
        return response.data
    }

    func cashReviews(branchId: UUID, status: String? = nil) async throws -> [RemoteCashReview] {
        struct Envelope: Decodable { let data: [RemoteCashReview] }
        let query = status.map { [URLQueryItem(name: "status", value: $0)] } ?? []
        let response: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/cash/reviews", method: "GET", queryItems: query)
        return response.data
    }

    func paymentsForSale(branchId: UUID, saleID: UUID) async throws -> [RemotePaymentAttempt] {
        struct Envelope: Decodable { let data: [RemotePaymentAttempt] }
        let response: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/sales/\(saleID.uuidString.lowercased())/payments", method: "GET")
        return response.data
    }

    func refundRequestsForSale(branchId: UUID, saleID: UUID) async throws -> [RemoteRefundRequest] {
        struct Envelope: Decodable { let data: [RemoteRefundRequest] }
        let response: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/sales/\(saleID.uuidString.lowercased())/refund-requests", method: "GET")
        return response.data
    }

    func prepayments(branchId: UUID) async throws -> [RemotePrepayment] {
        struct Envelope: Decodable { let data: [RemotePrepayment] }
        let response: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/prepayments", method: "GET")
        return response.data
    }

    func requestRefund(branchId: UUID, paymentEventID: UUID, body: RemoteRequestRefundBody) async throws -> RemoteRefundRequestWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/payment-events/\(paymentEventID.uuidString.lowercased())/refund-requests", method: "POST", body: try encoder.encode(body))
    }

    func requestPrepaymentRefund(branchId: UUID, advanceID: UUID, body: RemotePrepaymentRefundRequestBody) async throws -> RemoteRefundRequestWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/prepayments/\(advanceID.uuidString.lowercased())/refund-requests", method: "POST", body: try encoder.encode(body))
    }

    func collectPrepayment(branchId: UUID, authorizationID: UUID, body: RemoteCollectPrepaymentBody) async throws -> RemoteFinancialWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/dispense-authorizations/\(authorizationID.uuidString.lowercased())/prepayments", method: "POST", body: try encoder.encode(body))
    }

    func allocatePrepayment(branchId: UUID, advanceID: UUID, body: RemoteAllocatePrepaymentBody) async throws -> RemoteFinancialWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/prepayments/\(advanceID.uuidString.lowercased())/allocate", method: "POST", body: try encoder.encode(body))
    }

    func requestPrepaymentRelease(branchId: UUID, advanceID: UUID, body: RemoteRequestPrepaymentReleaseBody) async throws -> RemoteFinancialWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/prepayments/\(advanceID.uuidString.lowercased())/release-requests", method: "POST", body: try encoder.encode(body))
    }

    func confirmPrepaymentRelease(branchId: UUID, advanceID: UUID, body: RemoteConfirmPrepaymentReleaseBody) async throws -> RemoteFinancialWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/prepayments/\(advanceID.uuidString.lowercased())/release-confirmations", method: "POST", body: try encoder.encode(body))
    }

    func resolvePrepayment(branchId: UUID, advanceID: UUID, body: RemoteResolvePaymentBody) async throws -> RemoteFinancialWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/prepayments/\(advanceID.uuidString.lowercased())/resolve", method: "POST", body: try encoder.encode(body))
    }

    func executeRefund(branchId: UUID, paymentEventID: UUID, body: RemoteExecuteRefundBody) async throws -> RemoteFinancialWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/payment-events/\(paymentEventID.uuidString.lowercased())/refunds", method: "POST", body: try encoder.encode(body))
    }

    func executePrepaymentRefund(branchId: UUID, advanceID: UUID, body: RemoteExecuteRefundBody) async throws -> RemoteFinancialWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/prepayments/\(advanceID.uuidString.lowercased())/refunds", method: "POST", body: try encoder.encode(body))
    }

    func collectPayment(branchId: UUID, body: RemoteCollectPaymentBody) async throws -> RemoteFinancialWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/payments", method: "POST", body: try encoder.encode(body))
    }

    func resolvePayment(branchId: UUID, attemptID: UUID, body: RemoteResolvePaymentBody) async throws -> RemoteFinancialWriteResult {
        try await send(path: "branches/\(branchId.uuidString.lowercased())/payments/\(attemptID.uuidString.lowercased())/resolve", method: "POST", body: try encoder.encode(body))
    }

    func decideApproval(approvalID: UUID, body: RemoteApprovalDecisionBody) async throws -> RemoteApprovalDecisionResult {
        try await send(path: "approvals/\(approvalID.uuidString.lowercased())/decision", method: "POST", body: try encoder.encode(body))
    }

    func fuelSale(branchId: UUID, authorizationId: UUID) async throws -> RemoteFuelSale? {
        struct Envelope: Decodable { let data: RemoteFuelSale? }
        let response: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/dispense-authorizations/\(authorizationId.uuidString.lowercased())/sale", method: "GET")
        return response.data
    }
    func createFuelSale(branchId: UUID, authorizationId: UUID, commandId: UUID) async throws -> RemoteFuelSale {
        struct Body: Encodable { let authorizationId: UUID; let commandId: UUID }
        struct Envelope: Decodable { let data: RemoteFuelSale }
        let response: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/sales/from-dispatch", method: "POST",
            body: try encoder.encode(Body(authorizationId: authorizationId, commandId: commandId)))
        return response.data
    }
    func fuelSales(branchId: UUID, query: String?, cursor: String?) async throws -> RemotePage<RemoteFuelSaleSummary> {
        var items = [URLQueryItem(name: "limit", value: "25")]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(path: "branches/\(branchId.uuidString.lowercased())/sales", method: "GET", queryItems: items)
    }
    func fuelSaleDetail(branchId: UUID, saleId: UUID) async throws -> RemoteFuelSale {
        struct Envelope: Decodable { let data: RemoteFuelSale }
        let response: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/sales/\(saleId.uuidString.lowercased())", method: "GET")
        return response.data
    }
    func createCombinedReceipt(branchId: UUID, body: RemoteCombinedReceiptBody) async throws -> RemoteCombinedInternalReceipt {
        struct Envelope: Decodable { let data: RemoteCombinedInternalReceipt }
        let response: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/sales/combined-receipts", method: "POST", body: try encoder.encode(body))
        return response.data
    }
    func combinedReceipt(branchId: UUID, receiptId: UUID) async throws -> RemoteCombinedInternalReceipt {
        struct Envelope: Decodable { let data: RemoteCombinedInternalReceipt }
        let response: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/sales/combined-receipts/\(receiptId.uuidString.lowercased())", method: "GET")
        return response.data
    }
    func combinedReceipt(branchId: UUID, saleId: UUID) async throws -> RemoteCombinedInternalReceipt? {
        struct Envelope: Decodable { let data: RemoteCombinedInternalReceipt? }
        let response: Envelope = try await send(path: "branches/\(branchId.uuidString.lowercased())/sales/\(saleId.uuidString.lowercased())/combined-receipt", method: "GET")
        return response.data
    }

    func createDispenseAuthorization(branchId: UUID, nozzleId: UUID, commandId: UUID, amountUsd: String? = nil, volume: String? = nil, volumeUnit: String? = nil) async throws -> RemoteDispenseAuthorization {
        struct Body: Encodable { let commandId: UUID; let requestedAmountUsd: String?; let requestedVolume: String?; let volumeUnit: String? }
        struct Envelope<Value: Decodable>: Decodable { let data: Value }
        let body=try encoder.encode(Body(commandId:commandId,requestedAmountUsd:amountUsd,requestedVolume:volume,volumeUnit:volumeUnit))
        let response:Envelope<RemoteDispenseAuthorization>=try await send(path:dispensePath(branchId,authorizationId:nil,nozzleId:nozzleId,suffix:nil),method:"POST",body:body)
        return response.data
    }

    func dispenseAuthorizations(branchId: UUID, status: String?, cursor: String?, limit: Int) async throws -> RemotePage<RemoteDispenseAuthorization> {
        let boundedLimit = min(max(limit, 1), 100)
        var items = [URLQueryItem(name: "limit", value: String(boundedLimit))]
        if let status { items.append(URLQueryItem(name: "status", value: status)) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(path: "branches/\(branchId.uuidString.lowercased())/dispense-authorizations", method: "GET", queryItems: items)
    }

    func dispenseAuthorization(branchId:UUID,authorizationId:UUID) async throws -> RemoteDispenseAuthorization {
        struct Envelope<Value:Decodable>:Decodable{let data:Value}
        let response:Envelope<RemoteDispenseAuthorization>=try await send(path:dispensePath(branchId,authorizationId:authorizationId,nozzleId:nil,suffix:nil),method:"GET")
        return response.data
    }

    func startDispense(branchId:UUID,authorizationId:UUID,commandId:UUID,expectedVersion:Int) async throws -> RemoteDispenseAuthorization {
        struct Body:Encodable{let commandId:UUID;let expectedVersion:Int}
        return try await dispenseAction(branchId:branchId,authorizationId:authorizationId,suffix:"start",body:Body(commandId:commandId,expectedVersion:expectedVersion))
    }

    func reportDispenseProgress(branchId:UUID,authorizationId:UUID,commandId:UUID,quantity:String,unit:String,expectedVersion:Int) async throws -> RemoteDispenseAuthorization {
        struct Body:Encodable{let commandId:UUID;let quantity:String;let unit:String;let expectedVersion:Int}
        return try await dispenseAction(branchId:branchId,authorizationId:authorizationId,suffix:"progress",body:Body(commandId:commandId,quantity:quantity,unit:unit,expectedVersion:expectedVersion))
    }

    func completeDispense(branchId:UUID,authorizationId:UUID,commandId:UUID,quantity:String,unit:String,expectedVersion:Int,documentReference:String?=nil) async throws -> RemoteDispenseAuthorization {
        struct Body:Encodable{let commandId:UUID;let quantity:String;let unit:String;let expectedVersion:Int;let documentReference:String?}
        return try await dispenseAction(branchId:branchId,authorizationId:authorizationId,suffix:"complete",body:Body(commandId:commandId,quantity:quantity,unit:unit,expectedVersion:expectedVersion,documentReference:documentReference))
    }

    func cancelDispense(branchId:UUID,authorizationId:UUID,commandId:UUID,expectedVersion:Int,reason:String) async throws -> RemoteDispenseAuthorization {
        struct Body:Encodable{let commandId:UUID;let expectedVersion:Int;let reason:String}
        return try await dispenseAction(branchId:branchId,authorizationId:authorizationId,suffix:"cancel",body:Body(commandId:commandId,expectedVersion:expectedVersion,reason:reason))
    }

    func markDispenseUnknown(branchId:UUID,authorizationId:UUID,commandId:UUID,expectedVersion:Int,reason:String) async throws -> RemoteDispenseAuthorization {
        struct Body:Encodable{let commandId:UUID;let expectedVersion:Int;let reason:String}
        return try await dispenseAction(branchId:branchId,authorizationId:authorizationId,suffix:"unknown",body:Body(commandId:commandId,expectedVersion:expectedVersion,reason:reason))
    }

    func reconcileDispenseNoFlow(branchId:UUID,authorizationId:UUID,commandId:UUID,expectedVersion:Int,evidenceReference:String,reason:String) async throws -> RemoteDispenseAuthorization {
        struct Body:Encodable{let commandId:UUID;let expectedVersion:Int;let evidenceReference:String;let reason:String}
        return try await dispenseAction(branchId:branchId,authorizationId:authorizationId,suffix:"reconcile-no-flow",body:Body(commandId:commandId,expectedVersion:expectedVersion,evidenceReference:evidenceReference,reason:reason))
    }

    private func dispenseAction<Body:Encodable>(branchId:UUID,authorizationId:UUID,suffix:String,body:Body) async throws -> RemoteDispenseAuthorization {
        struct Envelope<Value:Decodable>:Decodable{let data:Value}
        let encoded=try encoder.encode(body)
        let response:Envelope<RemoteDispenseAuthorization>=try await send(path:dispensePath(branchId,authorizationId:authorizationId,nozzleId:nil,suffix:suffix),method:"POST",body:encoded)
        return response.data
    }

    private func dispensePath(_ branchId:UUID,authorizationId:UUID?,nozzleId:UUID?,suffix:String?) -> String {
        let root="branches/\(branchId.uuidString.lowercased())"
        if let nozzleId{return "\(root)/nozzles/\(nozzleId.uuidString.lowercased())/dispense-authorizations"}
        let path="\(root)/dispense-authorizations/\(authorizationId?.uuidString.lowercased() ?? "")"
        return suffix.map{"\(path)/\($0)"} ?? path
    }

    private func meterPath(_ branchId: UUID, _ nozzleId: UUID, suffix: String) -> String {
        "branches/\(branchId.uuidString.lowercased())/nozzles/\(nozzleId.uuidString.lowercased())/\(suffix)"
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        body: Data? = nil,
        requiresSession: Bool = true,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw RemoteAPIError.invalidBaseURL }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = "\(basePath)/api/v1/\(path)"
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw RemoteAPIError.invalidBaseURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Request-ID")
        if requiresSession {
            guard let tokens = tokenStore.load() else {
                throw RemoteAPIError.http(status: 401, code: "UNAUTHENTICATED", message: "Inicia sesión para continuar.", correlationId: nil)
            }
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RemoteAPIError.transport
        }
        guard let http = response as? HTTPURLResponse else { throw RemoteAPIError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else {
            struct ErrorBody: Decodable { let code: String?; let message: String?; let correlationId: String? }
            let failure = try? decoder.decode(ErrorBody.self, from: data)
            throw RemoteAPIError.http(
                status: http.statusCode,
                code: failure?.code ?? "HTTP_\(http.statusCode)",
                message: failure?.message ?? "La solicitud no pudo completarse.",
                correlationId: failure?.correlationId ?? http.value(forHTTPHeaderField: "x-request-id")
            )
        }
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw RemoteAPIError.malformedResponse }
    }
}

extension RemoteAPIClient: RemoteAuthenticationRepository {
    func authenticate(email: String, password: String) async throws -> RemoteIdentity {
        _ = try await login(email: email, password: password)
        return try await currentIdentity()
    }
}

@MainActor
final class APIRemotePumpRepository: RemotePumpRepository {
    func posCatalog(branchId: UUID, query: String?, kind: String?, cursor: String?, includeInactive: Bool) async throws -> RemotePage<RemotePOSProduct> { try await client.posCatalog(branchId: branchId, query: query, kind: kind, cursor: cursor, includeInactive: includeInactive) }
    func posProduct(branchId: UUID, productId: UUID) async throws -> RemotePOSProduct { try await client.posProduct(branchId: branchId, productId: productId) }
    func posLots(branchId: UUID, productId: UUID, cursor: String?) async throws -> RemotePage<RemotePOSLot> { try await client.posLots(branchId: branchId, productId: productId, cursor: cursor) }
    func publishPOSOffer(branchId: UUID, body: RemotePOSOfferBody) async throws -> RemotePOSWriteResult { try await client.publishPOSOffer(branchId: branchId, body: body) }
    func receivePOSLot(branchId: UUID, body: RemotePOSReceiptBody) async throws -> RemotePOSWriteResult { try await client.receivePOSLot(branchId: branchId, body: body) }
    func createPOSSale(branchId: UUID, body: RemotePOSSaleBody) async throws -> RemoteFuelSale { try await client.createPOSSale(branchId: branchId, body: body) }

    func deviceCapabilities() async throws -> RemoteDeviceCapabilities { try await client.deviceCapabilities() }
    func deviceOperation(branchId: UUID, authorizationId: UUID, commandId: UUID, operation: String, expectedVersion: Int, scenario: String?) async throws -> RemoteDeviceResponse {
        try await client.deviceOperation(branchId: branchId, authorizationId: authorizationId, commandId: commandId, operation: operation, expectedVersion: expectedVersion, scenario: scenario)
    }

    private let client: RemoteAPIClient
    init(client: RemoteAPIClient) { self.client = client }
    func fuelTaxPolicies(branchId: UUID) async throws -> RemoteFuelTaxPolicyPage { try await client.fuelTaxPolicies(branchId: branchId) }
    func proposeFuelTax(branchId: UUID, body: RemoteFuelTaxProposalBody) async throws -> RemoteFuelTaxWriteResponse { try await client.proposeFuelTax(branchId: branchId, body: body) }
    func approveFuelTax(branchId: UUID, proposalId: UUID, commandId: UUID) async throws -> RemoteFuelTaxWriteResponse { try await client.approveFuelTax(branchId: branchId, proposalId: proposalId, commandId: commandId) }
    func fuelSale(branchId: UUID, authorizationId: UUID) async throws -> RemoteFuelSale? {
        try await client.fuelSale(branchId: branchId, authorizationId: authorizationId)
    }
    func createFuelSale(branchId: UUID, authorizationId: UUID, commandId: UUID) async throws -> RemoteFuelSale {
        try await client.createFuelSale(branchId: branchId, authorizationId: authorizationId, commandId: commandId)
    }
    func fuelSales(branchId: UUID, query: String?, cursor: String?) async throws -> RemotePage<RemoteFuelSaleSummary> {
        try await client.fuelSales(branchId: branchId, query: query, cursor: cursor)
    }
    func fuelSaleDetail(branchId: UUID, saleId: UUID) async throws -> RemoteFuelSale {
        try await client.fuelSaleDetail(branchId: branchId, saleId: saleId)
    }
    func createCombinedReceipt(branchId: UUID, body: RemoteCombinedReceiptBody) async throws -> RemoteCombinedInternalReceipt {
        try await client.createCombinedReceipt(branchId: branchId, body: body)
    }
    func combinedReceipt(branchId: UUID, receiptId: UUID) async throws -> RemoteCombinedInternalReceipt {
        try await client.combinedReceipt(branchId: branchId, receiptId: receiptId)
    }
    func combinedReceipt(branchId: UUID, saleId: UUID) async throws -> RemoteCombinedInternalReceipt? {
        try await client.combinedReceipt(branchId: branchId, saleId: saleId)
    }
    func dispensers(branchId: UUID, query: String?, cursor: String?, limit: Int) async throws -> RemotePage<RemoteDispenserSummary> {
        try await client.dispensers(branchId: branchId, query: query, cursor: cursor, limit: limit)
    }
    func dispenser(branchId: UUID, dispenserId: UUID) async throws -> RemoteDispenserDetail {
        try await client.dispenser(branchId: branchId, dispenserId: dispenserId)
    }
    func nozzleAvailability(branchId: UUID, nozzleId: UUID) async throws -> RemoteNozzleAvailability {
        try await client.nozzleAvailability(branchId: branchId, nozzleId: nozzleId)
    }
    func nozzleMeterReadings(branchId: UUID, nozzleId: UUID) async throws -> RemoteNozzleMeterHistory {
        try await client.nozzleMeterReadings(branchId: branchId, nozzleId: nozzleId)
    }
    func captureMeterBaseline(branchId: UUID, nozzleId: UUID, commandId: UUID, value: String, meterSerial: String?, source: RemoteMeterReadingSource, note: String?) async throws -> RemoteNozzleMeterReading {
        try await client.captureMeterBaseline(branchId: branchId, nozzleId: nozzleId, commandId: commandId, value: value, meterSerial: meterSerial, source: source, note: note)
    }
    func captureMeterReading(branchId: UUID, nozzleId: UUID, commandId: UUID, value: String, meterSerial: String?, expectedVersion: Int, source: RemoteMeterReadingSource) async throws -> RemoteNozzleMeterReading {
        try await client.captureMeterReading(branchId: branchId, nozzleId: nozzleId, commandId: commandId, value: value, meterSerial: meterSerial, expectedVersion: expectedVersion, source: source)
    }
    func createDispenseAuthorization(branchId: UUID, nozzleId: UUID, commandId: UUID, amountUsd: String?, volume: String?, volumeUnit: String?) async throws -> RemoteDispenseAuthorization {
        try await client.createDispenseAuthorization(branchId: branchId, nozzleId: nozzleId, commandId: commandId, amountUsd: amountUsd, volume: volume, volumeUnit: volumeUnit)
    }
    func dispenseAuthorization(branchId: UUID, authorizationId: UUID) async throws -> RemoteDispenseAuthorization {
        try await client.dispenseAuthorization(branchId: branchId, authorizationId: authorizationId)
    }
    func dispenseAuthorizations(branchId: UUID, status: String?, cursor: String?, limit: Int) async throws -> RemotePage<RemoteDispenseAuthorization> {
        try await client.dispenseAuthorizations(branchId: branchId, status: status, cursor: cursor, limit: limit)
    }
    func startDispense(branchId: UUID, authorizationId: UUID, commandId: UUID, expectedVersion: Int) async throws -> RemoteDispenseAuthorization {
        try await client.startDispense(branchId: branchId, authorizationId: authorizationId, commandId: commandId, expectedVersion: expectedVersion)
    }
    func reportDispenseProgress(branchId: UUID, authorizationId: UUID, commandId: UUID, quantity: String, unit: String, expectedVersion: Int) async throws -> RemoteDispenseAuthorization {
        try await client.reportDispenseProgress(branchId: branchId, authorizationId: authorizationId, commandId: commandId, quantity: quantity, unit: unit, expectedVersion: expectedVersion)
    }
    func completeDispense(branchId: UUID, authorizationId: UUID, commandId: UUID, quantity: String, unit: String, expectedVersion: Int, documentReference: String?) async throws -> RemoteDispenseAuthorization {
        try await client.completeDispense(branchId: branchId, authorizationId: authorizationId, commandId: commandId, quantity: quantity, unit: unit, expectedVersion: expectedVersion, documentReference: documentReference)
    }
    func cancelDispense(branchId: UUID, authorizationId: UUID, commandId: UUID, expectedVersion: Int, reason: String) async throws -> RemoteDispenseAuthorization {
        try await client.cancelDispense(branchId: branchId, authorizationId: authorizationId, commandId: commandId, expectedVersion: expectedVersion, reason: reason)
    }
    func markDispenseUnknown(branchId: UUID, authorizationId: UUID, commandId: UUID, expectedVersion: Int, reason: String) async throws -> RemoteDispenseAuthorization {
        try await client.markDispenseUnknown(branchId: branchId, authorizationId: authorizationId, commandId: commandId, expectedVersion: expectedVersion, reason: reason)
    }
    func reconcileDispenseNoFlow(branchId: UUID, authorizationId: UUID, commandId: UUID, expectedVersion: Int, evidenceReference: String, reason: String) async throws -> RemoteDispenseAuthorization {
        try await client.reconcileDispenseNoFlow(branchId: branchId, authorizationId: authorizationId, commandId: commandId, expectedVersion: expectedVersion, evidenceReference: evidenceReference, reason: reason)
    }
}

@MainActor
final class APIRemoteTankRepository: RemoteTankRepository {
    private let client: RemoteAPIClient
    init(client: RemoteAPIClient) { self.client = client }
    func tanks(branchId: UUID, query: String?, status: String?, cursor: String?, limit: Int) async throws -> RemotePage<RemoteTankSummary> {
        try await client.tanks(branchId: branchId, query: query, status: status, cursor: cursor, limit: limit)
    }
    func tank(branchId: UUID, tankId: UUID) async throws -> RemoteTankDetail {
        try await client.tank(branchId: branchId, tankId: tankId)
    }
    func inventoryBalance(branchId: UUID, tankId: UUID) async throws -> RemoteTankInventorySnapshot {
        try await client.inventoryBalance(branchId: branchId, tankId: tankId)
    }
    func inventoryMovements(branchId: UUID, tankId: UUID, cursor: String?, limit: Int) async throws -> RemotePage<RemoteInventoryMovement> {
        try await client.inventoryMovements(branchId: branchId, tankId: tankId, cursor: cursor, limit: limit)
    }
}

@MainActor
final class APIRemoteBranchRepository: RemoteBranchRepository {
    private let client: RemoteAPIClient
    init(client: RemoteAPIClient) { self.client = client }
    func branches(query: String?, status: String?, cursor: String?, limit: Int) async throws -> RemotePage<RemoteBranchSummary> {
        try await client.branches(query: query, status: status, cursor: cursor, limit: limit)
    }
    func branchDetail(branchID: UUID) async throws -> RemoteBranchDetail {
        try await client.branchDetail(branchID: branchID)
    }
    func createBranchDraft(_ input: RemoteCreateBranchDraft) async throws -> RemoteBranchSummary {
        try await client.createBranchDraft(input)
    }
    func branchReadiness(branchID: UUID) async throws -> RemoteBranchReadiness {
        try await client.branchReadiness(branchID: branchID)
    }
    func saveOnboardingStep(branchID: UUID, expectedVersion: Int, step: String, data: RemoteBranchOnboardingData) async throws {
        try await client.saveOnboardingStep(branchID: branchID, expectedVersion: expectedVersion, step: step, data: data)
    }
    func activateBranch(branchID: UUID, expectedVersion: Int) async throws {
        try await client.activateBranch(branchID: branchID, expectedVersion: expectedVersion)
    }
    func fuelProducts(cursor: String?) async throws -> RemotePage<RemoteFuelProductSummary> {
        try await client.fuelProducts(cursor: cursor)
    }
    func branchConfiguration(branchID: UUID) async throws -> RemoteBranchConfiguration {
        try await client.branchConfiguration(branchID: branchID)
    }
    func createFuelProduct(_ input: RemoteCreateFuelProduct) async throws {
        try await client.createFuelProduct(input)
    }
    func enableFuelOffer(branchID: UUID, fuelProductID: UUID) async throws {
        try await client.enableFuelOffer(branchID: branchID, fuelProductID: fuelProductID)
    }
    func employees(branchID: UUID, cursor: String?) async throws -> RemotePage<RemoteEmployeeSummary> {
        try await client.employees(branchID: branchID, cursor: cursor)
    }
    func createEmployee(branchID: UUID, input: RemoteCreateEmployee) async throws {
        try await client.createEmployee(branchID: branchID, input: input)
    }
    func fuelPriceBoard(branchID: UUID) async throws -> RemoteBranchFuelPriceBoard {
        try await client.fuelPriceBoard(branchID: branchID)
    }
    func fuelPriceProposals(branchID: UUID) async throws -> [RemoteFuelPriceProposal] {
        try await client.fuelPriceProposals(branchID: branchID)
    }
    func createFuelPriceProposal(branchID: UUID, input: RemoteCreateFuelPriceProposal) async throws {
        try await client.createFuelPriceProposal(branchID: branchID, input: input)
    }
}

@MainActor
final class APIRemoteCutRepository: RemoteCutRepository {
    private let client: RemoteAPIClient
    init(client: RemoteAPIClient) { self.client = client }

    func dailyCuts(branchID: UUID, date: String) async throws -> [RemoteOperationalCut] {
        try await client.dailyCuts(branchID: branchID, date: date)
    }
    func generateDailyCuts(branchID: UUID, date: String) async throws -> [RemoteGeneratedCut] {
        try await client.generateDailyCuts(branchID: branchID, date: date)
    }
    func cutAssets(branchID: UUID, cutID: UUID) async throws -> RemoteCutAssets {
        try await client.cutAssets(branchID: branchID, cutID: cutID)
    }
    func openCut(branchID: UUID, cutID: UUID, expectedVersion: Int) async throws -> RemoteCutOpenResult {
        try await client.openCut(branchID: branchID, cutID: cutID, expectedVersion: expectedVersion)
    }
    func captureCutMeter(branchID: UUID, cutID: UUID, nozzleID: UUID, readingID: UUID, expectedVersion: Int) async throws -> RemoteCutCaptureResult {
        try await client.captureCutMeter(branchID: branchID, cutID: cutID, nozzleID: nozzleID, readingID: readingID, expectedVersion: expectedVersion)
    }
    func cutProgress(branchID: UUID, cutID: UUID) async throws -> RemoteCutProgress {
        try await client.cutProgress(branchID: branchID, cutID: cutID)
    }
    func measureCutTank(branchID: UUID, cutID: UUID, tankID: UUID, expectedVersion: Int, measuredLiters: String, waterLiters: String?, temperatureC: String?, observedAt: Date) async throws -> RemoteCutTankResult {
        try await client.measureCutTank(branchID: branchID, cutID: cutID, tankID: tankID, expectedVersion: expectedVersion, measuredLiters: measuredLiters, waterLiters: waterLiters, temperatureC: temperatureC, observedAt: observedAt)
    }
    func prepareCut(branchID: UUID, cutID: UUID, expectedVersion: Int) async throws -> RemoteCutPrepareResult {
        try await client.prepareCut(branchID: branchID, cutID: cutID, expectedVersion: expectedVersion)
    }
    func cutReconciliation(branchID: UUID, cutID: UUID) async throws -> RemoteCutReconciliation {
        try await client.cutReconciliation(branchID: branchID, cutID: cutID)
    }
    func reviewCut(branchID: UUID, cutID: UUID, expectedVersion: Int, reason: String) async throws -> RemoteCutTransitionResult {
        try await client.reviewCut(branchID: branchID, cutID: cutID, expectedVersion: expectedVersion, reason: reason)
    }
    func closeCut(branchID: UUID, cutID: UUID, expectedVersion: Int) async throws -> RemoteCutTransitionResult {
        try await client.closeCut(branchID: branchID, cutID: cutID, expectedVersion: expectedVersion)
    }
}

private func configureDLCDateDecoding(_ decoder: JSONDecoder) {
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "La fecha ISO 8601 del servidor no es válida.")
    }
}
