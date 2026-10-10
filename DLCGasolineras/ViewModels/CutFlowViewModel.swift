import Combine
import Foundation

@MainActor
final class CutFlowViewModel: ObservableObject {
    @Published private(set) var cut: DailyCut
    @Published var selectedPumpNumber = 1
    @Published var validationMessage = ""

    private let repository: MockRepository

    init(cut: DailyCut) {
        self.cut = cut
        self.repository = .shared
    }

    var completedPumpCount: Int { cut.completedPumpCount }
    var canClose: Bool { cut.canClose }

    func pumpReading(number: Int) -> PumpReading? {
        cut.pumpReadings.first(where: { $0.pumpNumber == number })
    }

    func registerPump(number: Int, readings: [FuelType: (initial: Double, final: Double)]) -> String? {
        guard !cut.isClosed else { return "El corte ya está cerrado." }
        guard (1...6).contains(number), readings.count == FuelType.allCases.count else {
            return "Registra las lecturas de los tres combustibles para una bomba válida."
        }
        var fuelReadings: [FuelReading] = []
        for fuel in FuelType.allCases {
            guard let value = readings[fuel], value.initial.isFinite, value.final.isFinite,
                  value.initial >= 0, value.final >= value.initial else {
                return "La lectura final de \(fuel.rawValue) debe ser igual o mayor que la inicial."
            }
            fuelReadings.append(FuelReading(
                id: UUID(), type: fuel,
                initialGallons: value.initial, finalGallons: value.final
            ))
        }
        let proposedReadings = Dictionary(uniqueKeysWithValues: fuelReadings.map {
            ($0.type, (initial: $0.initialGallons, final: $0.finalGallons))
        })
        if let continuityError = repository.readingContinuityError(
            cutID: cut.id,
            pumpNumber: number,
            proposedReadings: proposedReadings
        ) {
            return continuityError
        }

        let previousCut = cut
        let pump = PumpReading(id: pumpReading(number: number)?.id ?? UUID(), pumpNumber: number, readings: fuelReadings)
        if let index = cut.pumpReadings.firstIndex(where: { $0.pumpNumber == number }) {
            cut.pumpReadings[index] = pump
        } else {
            cut.pumpReadings.append(pump)
        }
        cut.pumpReadings.sort { $0.pumpNumber < $1.pumpNumber }
        validationMessage = ""
        if let error = repository.saveOpenCut(cut) {
            cut = previousCut
            return error
        }
        return nil
    }

    func addReceipt(fuel: FuelType, liters: Double, supplier: String, reference: String) -> String? {
        let cleanSupplier = supplier.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard liters.isFinite, liters > 0, !cleanSupplier.isEmpty, !cleanReference.isEmpty else {
            return "Ingresa litros, proveedor y documento o folio de recepción."
        }
        return appendMovement(FuelMovement(
            id: UUID(), kind: .receipt, fuel: fuel, quantityLiters: liters,
            cause: nil, explanation: "", supplier: cleanSupplier,
            documentReference: cleanReference, recordedAt: Date()
        ))
    }

    func addLoss(fuel: FuelType, liters: Double, cause: LossCause, explanation: String) -> String? {
        let cleanExplanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard liters.isFinite, liters > 0, !cleanExplanation.isEmpty else {
            return "Ingresa una cantidad en litros y explica la pérdida o daño."
        }
        return appendMovement(FuelMovement(
            id: UUID(), kind: .loss, fuel: fuel, quantityLiters: liters,
            cause: cause, explanation: cleanExplanation, supplier: "",
            documentReference: "", recordedAt: Date()
        ))
    }

    func removeMovement(id: UUID) -> String? {
        guard !cut.isClosed else { return "No puedes cambiar movimientos de un corte cerrado." }
        let previousCut = cut
        cut.movements.removeAll { $0.id == id }
        if let error = repository.saveOpenCut(cut) {
            cut = previousCut
            return error
        }
        return nil
    }

    func close(branchID: UUID) -> String? {
        guard branchID == cut.branchID else { return "El corte no pertenece a la sucursal activa." }
        if let error = repository.closeCut(id: cut.id, branchID: branchID) {
            validationMessage = error
            return error
        }
        if let updated = repository.todayCuts(for: branchID).first(where: { $0.id == cut.id }) {
            cut = updated
        }
        validationMessage = ""
        return nil
    }

    func salesGallons(for fuel: FuelType) -> Double { cut.soldGallons(for: fuel) }
    func salesUSD(for fuel: FuelType) -> Double {
        let price = repository.branch(withID: cut.branchID)?.pricePerGallonUSD[fuel] ?? 0
        return cut.soldGallons(for: fuel) * price
    }
    func receiptLiters(for fuel: FuelType) -> Double { cut.movementLiters(kind: .receipt, fuel: fuel) }
    func lossLiters(for fuel: FuelType) -> Double { cut.movementLiters(kind: .loss, fuel: fuel) }

    private func appendMovement(_ movement: FuelMovement) -> String? {
        guard !cut.isClosed else { return "El corte ya está cerrado." }
        cut.movements.append(movement)
        if let error = repository.saveOpenCut(cut) {
            cut.movements.removeAll { $0.id == movement.id }
            return error
        }
        return nil
    }
}
