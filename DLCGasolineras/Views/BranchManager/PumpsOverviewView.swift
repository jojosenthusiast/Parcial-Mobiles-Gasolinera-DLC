import SwiftUI

struct PumpsOverviewView: View {
    @ObservedObject var vm: BranchManagerViewModel
    @State private var range: HistoryRange = .last7Days
    @State private var selectedType: CutType?
    @State private var query = ""

    private var filteredCuts: [DailyCut] {
        vm.history(range: range, type: selectedType).filter { cut in
            guard !query.isEmpty else { return true }
            let date = cut.date.formatted(date: .long, time: .omitted)
            return date.localizedCaseInsensitiveContains(query)
                || cut.type.rawValue.localizedCaseInsensitiveContains(query)
                || cut.type.schedule.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Historial de cortes").font(.largeTitle.weight(.bold))
                    Text("Consulta ventas, lecturas y movimientos de cada corte.")
                        .font(.subheadline).foregroundStyle(DLCTheme.muted)
                }

                VStack(alignment: .leading, spacing: 11) {
                    Text("Periodo").font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.muted)
                    Picker("Periodo", selection: $range) {
                        ForEach(HistoryRange.allCases) { value in Text(value.rawValue).tag(value) }
                    }
                    .pickerStyle(.segmented)
                    Text("Tipo de corte").font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.muted)
                    HStack(spacing: 8) {
                        filterChip("Todos", isSelected: selectedType == nil) { selectedType = nil }
                        ForEach(CutType.allCases) { type in
                            filterChip(type.rawValue, isSelected: selectedType == type) { selectedType = type }
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(DLCTheme.muted)
                        TextField("Filtrar por fecha o turno", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DLCTheme.muted) }
                                .accessibilityLabel("Limpiar filtro")
                        }
                    }
                    .padding(12)
                    .background(DLCTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .dlcCard()

                HStack {
                    Text("Resultados").font(.headline)
                    Spacer()
                    Text("\(filteredCuts.count) cortes").font(.caption).foregroundStyle(DLCTheme.muted)
                }

                if filteredCuts.isEmpty {
                    ContentUnavailableView("Sin resultados", systemImage: "line.3.horizontal.decrease.circle", description: Text("Ajusta el periodo o los filtros para encontrar un corte."))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredCuts) { cut in
                            NavigationLink(destination: CutHistoryDetailView(cut: cut, branch: vm.branch)) {
                                HistoryCutRow(cut: cut)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Historial")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .onAppear { vm.reload() }
    }

    private func filterChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : DLCTheme.ink)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(isSelected ? DLCTheme.forest : DLCTheme.background)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct HistoryCutRow: View {
    let cut: DailyCut

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(cut.date.formatted(.dateTime.day())).font(.title3.weight(.bold))
                Text(cut.date.formatted(.dateTime.month(.abbreviated)).uppercased()).font(.caption2.weight(.bold))
            }
            .foregroundStyle(DLCTheme.ink)
            .frame(width: 46, height: 49)
            .background(DLCTheme.orangeBG)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(cut.type.rawValue).font(.headline).foregroundStyle(DLCTheme.ink)
                Text(cut.type.schedule).font(.caption).foregroundStyle(DLCTheme.muted)
                Text("\(cut.completedPumpCount)/6 bombas · \(Int(cut.totalSoldGallons.rounded()).formatted()) gal")
                    .font(.caption.weight(.medium)).foregroundStyle(DLCTheme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: cut.isClosed ? "checkmark.circle.fill" : "clock.fill")
                .foregroundStyle(cut.isClosed ? DLCTheme.green : DLCTheme.orange)
        }
        .dlcCard()
        .accessibilityElement(children: .combine)
    }
}

private struct CutHistoryDetailView: View {
    let cut: DailyCut
    let branch: Branch

    private var estimatedSalesUSD: Double {
        FuelType.allCases.reduce(0) { total, fuel in
            total + cut.soldGallons(for: fuel) * (branch.pricePerGallonUSD[fuel] ?? 0)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(cut.type.rawValue).font(.largeTitle.weight(.bold))
                    Text("\(branch.name) · \(cut.date.formatted(date: .long, time: .omitted)) · \(cut.type.schedule)")
                        .font(.subheadline).foregroundStyle(DLCTheme.muted)
                }
                HStack {
                    summaryValue("Bombas", value: "\(cut.completedPumpCount) / 6")
                    Divider().frame(height: 44)
                    summaryValue("Venta estimada", value: estimatedSalesUSD.formatted(.currency(code: "USD")))
                }
                .dlcCard(color: DLCTheme.orangeBG)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Detalle por combustible").font(.headline)
                    ForEach(FuelType.allCases) { fuel in
                        HStack(spacing: 8) {
                            Circle().fill(DLCTheme.fuelColor(fuel)).frame(width: 9, height: 9)
                            Text(fuel.rawValue).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(cut.soldGallons(for: fuel), specifier: "%.1f") gal")
                                .font(.subheadline.weight(.bold))
                        }
                        if fuel != FuelType.allCases.last { Divider() }
                    }
                }
                .dlcCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Lecturas de las bombas").font(.headline)
                    ForEach(1...6, id: \.self) { number in
                        if let pump = cut.pumpReadings.first(where: { $0.pumpNumber == number }) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Bomba \(number)").font(.subheadline.weight(.semibold))
                                ForEach(FuelType.allCases) { fuel in
                                    if let reading = pump.readings.first(where: { $0.type == fuel }) {
                                        HStack(spacing: 7) {
                                            Circle().fill(DLCTheme.fuelColor(fuel)).frame(width: 7, height: 7)
                                            Text(fuel.rawValue).font(.caption)
                                            Spacer()
                                        }
                                        .foregroundStyle(DLCTheme.muted)
                                        HStack(spacing: 8) {
                                            readingValue("Inicial", gallons: reading.initialGallons)
                                            readingValue("Final", gallons: reading.finalGallons)
                                            readingValue("Venta", gallons: reading.soldGallons, emphasized: true)
                                        }
                                    }
                                }
                            }
                            if number < 6 { Divider() }
                        }
                    }
                }
                .dlcCard()

                movementSection(.receipt, title: "Recepciones", color: DLCTheme.green)
                movementSection(.loss, title: "Pérdidas y daños", color: DLCTheme.red)
            }
            .padding(20)
        }
        .navigationTitle("Detalle del corte")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
    }

    private func summaryValue(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(DLCTheme.muted)
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(DLCTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func movementSection(_ kind: MovementKind, title: String, color: Color) -> some View {
        let movements = cut.movements.filter { $0.kind == kind }
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(color)
            if movements.isEmpty {
                Text("Sin movimientos").font(.subheadline).foregroundStyle(DLCTheme.muted)
            } else {
                ForEach(movements) { movement in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(movement.fuel.rawValue).font(.subheadline.weight(.semibold))
                            Text(kind == .receipt
                                 ? "\(movement.supplier) · \(movement.documentReference)"
                                 : "\(movement.cause?.rawValue ?? "") · \(movement.explanation)")
                                .font(.caption).foregroundStyle(DLCTheme.muted)
                        }
                        Spacer()
                        Text("\(Int(movement.quantityLiters.rounded()).formatted()) L")
                            .font(.subheadline.weight(.bold)).foregroundStyle(color)
                    }
                    if movement.id != movements.last?.id { Divider() }
                }
            }
        }
        .dlcCard()
    }

    private func readingValue(_ title: String, gallons: Double, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(DLCTheme.muted)
            Text("\(gallons, specifier: "%.1f") gal")
                .font(.caption.weight(emphasized ? .bold : .medium))
                .foregroundStyle(DLCTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
struct RemotePumpsOverviewView: View {
    @StateObject private var vm: RemotePumpsViewModel
    let canCaptureMeter: Bool
    let canAuthorizeDispense: Bool
    let offlineStore: RemoteOfflineStore
    let branchID: UUID
    let prepaymentClient: RemoteAPIClient?
    let prepaymentScope: RemoteDataScope?
    let canCollectPrepayments: Bool
    let canReadCash: Bool
    let canReadPrepayments: Bool

    init(repository: RemotePumpRepository, offlineStore: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID, canCaptureMeter: Bool = false, canAuthorizeDispense: Bool = false, canReadSales: Bool = false, canCreateSales: Bool = false, prepaymentClient: RemoteAPIClient? = nil, canCollectPrepayments: Bool = false, canReadCash: Bool = false, canReadPrepayments: Bool = false) {
        self.canCaptureMeter = canCaptureMeter
        self.canAuthorizeDispense = canAuthorizeDispense
        self.offlineStore = offlineStore
        self.branchID = branchID
        self.prepaymentClient = prepaymentClient
        self.prepaymentScope = scope
        self.canCollectPrepayments = canCollectPrepayments
        self.canReadCash = canReadCash
        self.canReadPrepayments = canReadPrepayments
        _vm = StateObject(wrappedValue: RemotePumpsViewModel(repository: repository, offlineStore: offlineStore, scope: scope, branchID: branchID, canReadSales: canReadSales, canCreateSales: canCreateSales))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("Bombas").font(.largeTitle.weight(.bold))
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(DLCTheme.muted)
                    TextField("Buscar código o nombre", text: $vm.query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { Task { await vm.load() } }
                    Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Actualizar bombas")
                }
                .padding(12).background(DLCTheme.surface).clipShape(RoundedRectangle(cornerRadius: 12))
                if vm.isStale, let date = vm.lastUpdated {
                    Label("Datos guardados · actualización \(date.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(DLCTheme.orange)
                }
                if !vm.errorMessage.isEmpty {
                    Label(vm.errorMessage, systemImage: "wifi.exclamationmark")
                        .font(.footnote).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true)
                }
                if vm.isLoading && vm.dispensers.isEmpty {
                    ProgressView("Cargando bombas…").frame(maxWidth: .infinity).padding(28)
                } else if vm.dispensers.isEmpty {
                    ContentUnavailableView("Sin bombas", systemImage: "fuelpump", description: Text("No hay dispensadores para esta sucursal o búsqueda."))
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.dispensers) { dispenser in
                            NavigationLink {
                                RemoteDispenserDetailView(vm: vm, dispenserID: dispenser.id, canCaptureMeter: canCaptureMeter, canAuthorizeDispense: canAuthorizeDispense)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "fuelpump.fill").font(.title2).foregroundStyle(DLCTheme.orange)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(dispenser.code) · \(dispenser.name ?? "Dispensador")")
                                            .font(.headline).foregroundStyle(DLCTheme.ink)
                                        Text("\(dispenser.activeNozzles)/\(dispenser.nozzleCount) mangueras activas · \(dispenser.physicalStatus)")
                                            .font(.caption).foregroundStyle(DLCTheme.muted)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").foregroundStyle(DLCTheme.muted)
                                }.dlcCard()
                            }.buttonStyle(.plain)
                        }
                    }
                    if vm.hasMore {
                        Button { Task { await vm.loadMore() } } label: {
                            if vm.isLoadingMore { ProgressView() } else { Text("Cargar más") }
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
            }.padding(20)
        }
        .navigationTitle("Operación")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .task { if vm.dispensers.isEmpty { await vm.load() } }
    }
}

private enum RemotePumpDetailSheet: Identifiable {
    case meter(RemoteDispenserNozzle)
    case dispense(RemoteDispenserNozzle)

    var id: String {
        switch self {
        case .meter(let nozzle): "meter-\(nozzle.id.uuidString)"
        case .dispense(let nozzle): "dispense-\(nozzle.id.uuidString)"
        }
    }
}

@MainActor
private struct RemoteDispenserDetailView: View {
    @ObservedObject var vm: RemotePumpsViewModel
    let dispenserID: UUID
    let canCaptureMeter: Bool
    let canAuthorizeDispense: Bool
    @State private var activeSheet: RemotePumpDetailSheet?

    private var snapshot: RemoteDispenserSnapshot? {
        vm.selectedDispenser?.detail.id == dispenserID ? vm.selectedDispenser : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if vm.isStale, let date = vm.lastUpdated {
                    Label("Ficha guardada · \(date.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(DLCTheme.orange)
                }
                if vm.hasPartialDetail {
                    Label("La ficha cargó con datos parciales; actualiza para volver a consultar las mangueras.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(DLCTheme.orange)
                }
                if !vm.errorMessage.isEmpty {
                    Label(vm.errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true)
                }
                if let snapshot {
                    let detail = snapshot.detail
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail.name ?? "Dispensador \(detail.code)").font(.title2.weight(.bold))
                        Text("\(detail.code) · \(detail.physicalStatus)").font(.subheadline).foregroundStyle(DLCTheme.muted)
                    }.dlcCard(color: DLCTheme.orangeBG)

                    ForEach(detail.nozzles) { nozzle in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text("Manguera \(nozzle.code)").font(.headline)
                                Spacer()
                                Text(nozzle.physicalStatus).font(.caption.weight(.semibold))
                                    .foregroundStyle(nozzle.physicalStatus == "active" ? DLCTheme.green : DLCTheme.red)
                            }
                            Text("\(nozzle.fuelName) · \(nozzle.serviceMode == "full_service" ? "Servicio completo" : "Autoservicio") · Tanque \(nozzle.tankCode ?? "sin asignar")")
                                .font(.subheadline).foregroundStyle(DLCTheme.muted)
                            if let value = nozzle.meterValue {
                                Text("Totalizador: \(value) \(nozzle.meterUnit) · medidor \(nozzle.meterSerial ?? "sin serie")")
                                    .font(.caption.weight(.medium))
                            } else {
                                Text("Sin lectura de totalizador registrada.").font(.caption).foregroundStyle(DLCTheme.muted)
                            }
                            if canCaptureMeter {
                                Button {
                                    activeSheet = .meter(nozzle)
                                } label: {
                                    Label(nozzle.meterVersion == nil ? "Registrar lectura inicial" : "Registrar lectura", systemImage: "gauge.with.dots.needle.67percent")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DLCTheme.orange)
                                .accessibilityHint("Guarda una lectura auditada del totalizador de esta manguera.")
                            }
                            if let state = snapshot.nozzles[nozzle.id] {
                                if canAuthorizeDispense {
                                    Button {
                                        activeSheet = .dispense(nozzle)
                                    } label: {
                                        Label("Autorizar despacho", systemImage: "fuelpump.fill")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DLCTheme.ink)
                                    .disabled(state.availability?.selectable != true || state.availability?.price == nil)
                                }
                                if let availability = state.availability {
                                    Text(availability.selectable ? "Disponible para autorizar" : availability.reasons.map(\.message).joined(separator: " "))
                                        .font(.caption).foregroundStyle(availability.selectable ? DLCTheme.green : DLCTheme.red)
                                    if let price = availability.price {
                                        Text("Precio vigente: $\(price.amount) / \(price.unit == "us_gallon" ? "gal US" : "L")")
                                            .font(.caption).foregroundStyle(DLCTheme.muted)
                                    }
                                }
                                if let last = state.meterHistory?.readings.first {
                                    Text("Última lectura: \(last.value) \(last.unit) · \(last.capturedAt?.formatted(date: .abbreviated, time: .shortened) ?? "hora no disponible")")
                                        .font(.caption2).foregroundStyle(DLCTheme.muted)
                                }
                            }
                        }.dlcCard()
                    }
                } else if vm.isLoadingDetail {
                    ProgressView("Cargando ficha…").frame(maxWidth: .infinity).padding(28)
                }
            }.padding(20)
        }
        .navigationTitle("Detalle de bomba")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .task(id: dispenserID) { await vm.loadDispenser(dispenserID) }
        .sheet(item: $activeSheet) { sheet in
            Group {
                switch sheet {
                case .meter(let nozzle):
                    RemoteMeterCaptureSheet(vm: vm, dispenserID: dispenserID, nozzle: nozzle)
                case .dispense(let nozzle):
                    RemoteDispenseFlowSheet(vm: vm, nozzle: nozzle, currentPrice: snapshot?.nozzles[nozzle.id]?.availability?.price,
                        prepaymentClient: prepaymentClient, prepaymentStore: offlineStore,
                        prepaymentScope: prepaymentScope, prepaymentBranchID: branchID,
                        canCollectPrepayments: canCollectPrepayments, canReadCash: canReadCash,
                        canReadPrepayments: canReadPrepayments)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

@MainActor
private struct RemoteMeterCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemotePumpsViewModel
    let dispenserID: UUID
    let nozzle: RemoteDispenserNozzle
    @State private var value = ""
    @State private var meterSerial = ""
    @State private var note = ""
    @State private var errorMessage = ""
    @State private var commandID = UUID()
    @State private var isSaving = false

    private var isBaseline: Bool { nozzle.meterVersion == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Manguera") {
                    LabeledContent("Bomba / manguera", value: "\(nozzle.code) · \(nozzle.fuelName)")
                    LabeledContent("Unidad", value: nozzle.meterUnit)
                    if let previous = nozzle.meterValue {
                        LabeledContent("Lectura anterior", value: "\(previous) \(nozzle.meterUnit)")
                    } else {
                        Text("Esta será la lectura inicial. No se calculará venta a partir de ella.")
                            .font(.footnote).foregroundStyle(DLCTheme.muted)
                    }
                }
                Section("Lectura del totalizador") {
                    TextField("Valor acumulado", text: $value)
                        .keyboardType(.decimalPad)
                        .onChange(of: value) { _, _ in commandID = UUID() }
                    TextField("Serie del medidor (opcional)", text: $meterSerial)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: meterSerial) { _, _ in commandID = UUID() }
                    if isBaseline {
                        TextField("Nota de respaldo (opcional)", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .onChange(of: note) { _, _ in commandID = UUID() }
                    }
                }
                if !errorMessage.isEmpty {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(DLCTheme.red)
                    }
                }
            }
            .navigationTitle(isBaseline ? "Lectura inicial" : "Nueva lectura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Guardar") }
                    }
                    .disabled(isSaving || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = ""
        defer { isSaving = false }
        do {
            try await vm.recordMeterReading(
                dispenserID: dispenserID,
                nozzle: nozzle,
                value: value,
                meterSerial: meterSerial,
                note: note.isEmpty ? nil : note,
                commandID: commandID
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


@MainActor
private struct RemoteDispenseFlowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemotePumpsViewModel
    let nozzle: RemoteDispenserNozzle?
    let currentPrice: RemoteNozzleAvailability.Price?
    let prepaymentClient: RemoteAPIClient?
    let prepaymentStore: RemoteOfflineStore?
    let prepaymentScope: RemoteDataScope?
    let prepaymentBranchID: UUID?
    let canCollectPrepayments: Bool
    let canReadCash: Bool
    let canReadPrepayments: Bool
    @State private var authorization: RemoteDispenseAuthorization?
    @State private var requiresRefreshBeforeAction: Bool

    init(vm: RemotePumpsViewModel, nozzle: RemoteDispenserNozzle? = nil, currentPrice: RemoteNozzleAvailability.Price? = nil,
         initialAuthorization: RemoteDispenseAuthorization? = nil, requiresRefresh: Bool = false,
         prepaymentClient: RemoteAPIClient? = nil, prepaymentStore: RemoteOfflineStore? = nil,
         prepaymentScope: RemoteDataScope? = nil, prepaymentBranchID: UUID? = nil,
         canCollectPrepayments: Bool = false, canReadCash: Bool = false, canReadPrepayments: Bool = false) {
        _vm = ObservedObject(wrappedValue: vm)
        self.nozzle = nozzle
        self.currentPrice = currentPrice
        self.prepaymentClient = prepaymentClient
        self.prepaymentStore = prepaymentStore
        self.prepaymentScope = prepaymentScope
        self.prepaymentBranchID = prepaymentBranchID
        self.canCollectPrepayments = canCollectPrepayments
        self.canReadCash = canReadCash
        self.canReadPrepayments = canReadPrepayments
        _authorization = State(initialValue: initialAuthorization)
        _requiresRefreshBeforeAction = State(initialValue: requiresRefresh)
    }

    private var isBaseline: Bool { nozzle?.meterVersion == nil }

    @State private var requestByAmount = true
    @State private var amountUsd = ""
    @State private var requestedVolume = ""
    @State private var volumeUnit = "gallon_us"
    @State private var measuredQuantity = ""
    @State private var measuredUnit = "gallon_us"
    @State private var documentReference = ""
    @State private var reason = ""
    @State private var evidenceReference = ""
    @State private var errorMessage = ""
    @State private var isWorking = false
    @State private var commandIDs: [String: UUID] = [:]
    @State private var completionExpectedVersion: Int?
    @State private var deviceCapabilities: RemoteDeviceCapabilities?
    @State private var deviceScenario = "normal"
    @State private var deviceExpectedVersions: [String: Int] = [:]
    @State private var deviceMessage = ""
    @State private var fuelSale: RemoteFuelSale?
    @State private var saleLookupCompleted = false


    private func commandID(_ key: String) -> UUID {
        if let existing = commandIDs[key] { return existing }
        let next = UUID()
        commandIDs[key] = next
        return next
    }

    var body: some View {
        NavigationStack {
            Form {
                if let nozzle {
                    Section("Manguera") {
                        LabeledContent("Código", value: "\(nozzle.code) · \(nozzle.fuelName)")
                        LabeledContent("Modalidad", value: nozzle.serviceMode == "full_service" ? "Servicio completo" : "Autoservicio")
                        if let currentPrice {
                            LabeledContent("Precio actual", value: "$\(currentPrice.amount) / \(currentPrice.unit == "us_gallon" ? "galón US" : "litro")")
                        } else {
                            LabeledContent("Precio actual", value: "No disponible")
                        }
                        Text("El precio mostrado puede cambiar. El servidor vuelve a comprobar precio, inventario y reserva antes de autorizar.")
                            .font(.footnote).foregroundStyle(DLCTheme.muted)
                    }
                }

                if let authorization {
                    if requiresRefreshBeforeAction {
                        Section {
                            Label("La lista es una copia guardada. Actualiza esta autorización antes de actuar.", systemImage: "clock.arrow.circlepath")
                                .font(.footnote).foregroundStyle(DLCTheme.orange)
                        }
                    }
                    Section("Autorización · \(dispenseStatusLabel(authorization.status))") {
                        LabeledContent("Identificador", value: String(authorization.id.uuidString.prefix(8)))
                        LabeledContent("Reserva", value: "\(authorization.reservedL) L")
                        LabeledContent("Precio congelado", value: "$\(authorization.priceUsdPerUnit) / \(authorization.priceUnit)")
                        LabeledContent("Avance acumulado", value: "\(authorization.progressL) L")
                        LabeledContent("Versión", value: "\(authorization.version)")
                        if let expiresAt = authorization.expiresAt, authorization.status == "authorized" {
                            LabeledContent("Vence", value: expiresAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }

                    if deviceCapabilities?.mode == "simulated" {
                        Section("Simulador de despacho") {
                            Label("Prueba simulada · sin equipo físico", systemImage: "testtube.2")
                                .foregroundStyle(DLCTheme.orange)
                            if authorization.status == "authorized" {
                                Picker("Escenario", selection: $deviceScenario) {
                                    Text("Respuesta normal").tag("normal")
                                    Text("Timeout con despacho").tag("timeout_after_completion")
                                    Text("Timeout sin flujo").tag("timeout_before_start")
                                }
                                .onChange(of: deviceScenario) { _, _ in
                                    commandIDs.removeValue(forKey: "device-start")
                                    deviceExpectedVersions.removeValue(forKey: "device-start")
                                }
                                actionButton("Iniciar prueba simulada", symbol: "play.circle", key: "device-start") {
                                    try await runDevice(authorization, operation: "start")
                                }
                            } else if ["dispensing", "unknown", "posting"].contains(authorization.status) {
                                actionButton("Consultar resultado del simulador", symbol: "arrow.triangle.2.circlepath", key: "device-query") {
                                    try await runDevice(authorization, operation: "query")
                                }
                            }
                            if !deviceMessage.isEmpty { Text(deviceMessage).font(.footnote) }
                        }
                    }

                    switch authorization.status {
                    case "authorized":
                        Section("Operación") {
                            if deviceCapabilities?.mode != "simulated" {
                                actionButton("Confirmar inicio manual", symbol: "play.fill", key: "start") {
                                    try await vm.startAuthorization(authorization, commandID: commandID("start"))
                                }
                            }
                            actionButton("Cancelar autorización", symbol: "xmark.circle", key: "cancel") {
                                try await vm.cancelAuthorization(authorization, commandID: commandID("cancel"), reason: "Cancelación solicitada desde la app")
                            }
                        }
                    case "dispensing":
                        Section("Volumen observado") {
                            TextField("Cantidad acumulada", text: $measuredQuantity)
                                .keyboardType(.decimalPad)
                                .onChange(of: measuredQuantity) { _, _ in commandIDs.removeValue(forKey: "progress"); commandIDs.removeValue(forKey: "complete"); completionExpectedVersion = nil }
                            Picker("Unidad", selection: $measuredUnit) {
                                Text("Galón US").tag("gallon_us")
                                Text("Litro").tag("liter")
                            }.pickerStyle(.segmented)
                                .onChange(of: measuredUnit) { _, _ in commandIDs.removeValue(forKey: "progress"); commandIDs.removeValue(forKey: "complete"); completionExpectedVersion = nil }
                            actionButton("Registrar avance", symbol: "arrow.up.forward", key: "progress", isEnabled: !measuredQuantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                                try await vm.reportProgress(authorization, commandID: commandID("progress"), quantity: measuredQuantity, unit: measuredUnit)
                            }
                            TextField("Referencia de comprobante (opcional)", text: $documentReference)
                                .onChange(of: documentReference) { _, _ in commandIDs.removeValue(forKey: "complete"); completionExpectedVersion = nil }
                            actionButton("Completar y registrar venta", symbol: "checkmark.circle.fill", key: "complete", isEnabled: !measuredQuantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                                try await complete(authorization)
                            }
                            actionButton("Marcar resultado desconocido", symbol: "questionmark.circle", key: "unknown") {
                                try await vm.markAuthorizationUnknown(authorization, commandID: commandID("unknown"), reason: "Resultado físico pendiente de conciliación")
                            }
                        }
                    case "unknown":
                        Section("Conciliación") {
                            Text("No se debe volver a despachar desde esta autorización hasta comprobar el resultado físico.")
                                .font(.footnote).foregroundStyle(DLCTheme.red)
                            TextField("Volumen comprobado", text: $measuredQuantity).keyboardType(.decimalPad)
                                .onChange(of: measuredQuantity) { _, _ in commandIDs.removeValue(forKey: "complete"); completionExpectedVersion = nil }
                            Picker("Unidad", selection: $measuredUnit) {
                                Text("Galón US").tag("gallon_us")
                                Text("Litro").tag("liter")
                            }.pickerStyle(.segmented)
                                .onChange(of: measuredUnit) { _, _ in commandIDs.removeValue(forKey: "complete"); completionExpectedVersion = nil }
                            TextField("Referencia de evidencia", text: $documentReference)
                                .onChange(of: documentReference) { _, _ in commandIDs.removeValue(forKey: "complete"); completionExpectedVersion = nil }
                            actionButton("Conciliar con flujo observado", symbol: "checkmark.circle.fill", key: "complete", isEnabled: !measuredQuantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !documentReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                                try await complete(authorization)
                            }
                            TextField("Referencia de verificación sin flujo", text: $evidenceReference)
                                .onChange(of: evidenceReference) { _, _ in commandIDs.removeValue(forKey: "no-flow") }
                            TextField("Motivo", text: $reason, axis: .vertical).lineLimit(2...4)
                                .onChange(of: reason) { _, _ in commandIDs.removeValue(forKey: "no-flow") }
                            actionButton("Conciliar: no hubo despacho", symbol: "checkmark.shield", key: "no-flow", isEnabled: !evidenceReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                                try await vm.reconcileAuthorizationNoFlow(authorization, commandID: commandID("no-flow"), evidenceReference: evidenceReference, reason: reason)
                            }
                        }
                    case "posting":
                        Section("Confirmación pendiente") {
                            Text("La venta está en proceso. Si la primera solicitud perdió respuesta, repite exactamente la misma cantidad y referencia para recuperar el resultado idempotente.")
                                .font(.footnote).foregroundStyle(DLCTheme.orange)
                            TextField("Cantidad final", text: $measuredQuantity).keyboardType(.decimalPad)
                                .disabled(completionExpectedVersion != nil)
                            Picker("Unidad", selection: $measuredUnit) {
                                Text("Galón US").tag("gallon_us")
                                Text("Litro").tag("liter")
                            }.pickerStyle(.segmented)
                                .disabled(completionExpectedVersion != nil)
                            TextField("Referencia de comprobante", text: $documentReference)
                                .disabled(completionExpectedVersion != nil)
                            actionButton("Reintentar registro de venta", symbol: "arrow.clockwise", key: "complete", isEnabled: !measuredQuantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !documentReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                                try await complete(authorization)
                            }
                        }
                    default:
                        Section("Estado final") {
                            Text("La autorización está en estado «\(dispenseStatusLabel(authorization.status))». Consulta eventos para revisar el resultado.")
                                .font(.footnote).foregroundStyle(DLCTheme.muted)
                        }
                    }

                    if authorization.status == "authorized", canCollectPrepayments {
                        if let prepaymentClient, let prepaymentStore, let prepaymentScope, let prepaymentBranchID {
                            Section("Anticipo antes del despacho") {
                                RemotePrepaymentCollectionPanel(client: prepaymentClient, store: prepaymentStore,
                                    scope: prepaymentScope, branchID: prepaymentBranchID,
                                    authorizationID: authorization.id, canReadCash: canReadCash,
                                    canReadHistory: canReadPrepayments,
                                    canAct: !requiresRefreshBeforeAction)
                            }
                        } else {
                            Section { Label("No se pudo preparar el registro remoto del anticipo.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(DLCTheme.red) }
                        }
                    }

                    if authorization.status == "completed", vm.canReadSales || vm.canCreateSales {
                        Section("Venta del despacho") {
                            if let fuelSale {
                                RemoteFuelSaleContent(sale: fuelSale)
                            } else {
                                LabeledContent("Importe despachado", value: "$\(authorization.saleAmountUsd ?? "—")")
                                if vm.canReadSales {
                                    Button("Consultar comprobante") { Task { await lookupSale(authorization.id) } }
                                }
                                if vm.canCreateSales && (saleLookupCompleted || !vm.canReadSales) {
                                    Button {
                                        Task {
                                            isWorking = true
                                            defer { isWorking = false }
                                            do {
                                                fuelSale = try await vm.createFuelSale(for: authorization.id, commandID: commandID("sale"))
                                                errorMessage = ""
                                            } catch { errorMessage = error.localizedDescription }
                                        }
                                    } label: { Label("Registrar venta pendiente de cobro", systemImage: "receipt") }
                                    .disabled(isWorking || requiresRefreshBeforeAction)
                                }
                            }
                        }
                    }

                    Section("Trazabilidad") {
                        ForEach(authorization.events) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.eventType.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.subheadline.weight(.medium))
                                Text("\(event.previousStatus ?? "inicio") → \(event.nextStatus) · \(event.occurredAt?.formatted(date: .abbreviated, time: .shortened) ?? "hora no disponible")")
                                    .font(.caption).foregroundStyle(DLCTheme.muted)
                                if let reason = event.reason, !reason.isEmpty {
                                    Text(reason).font(.caption).foregroundStyle(DLCTheme.muted)
                                }
                            }
                        }
                    }
                    Section {
                        Button("Actualizar estado desde servidor") {
                            Task { await refresh() }
                        }
                        .disabled(isWorking)
                    }
                } else if let nozzle {
                    Section("Tipo de autorización") {
                        Picker("Solicitar por", selection: $requestByAmount) {
                            Text("Importe").tag(true)
                            Text("Volumen").tag(false)
                        }.pickerStyle(.segmented)
                            .onChange(of: requestByAmount) { _, _ in commandIDs.removeValue(forKey: "create") }
                        if requestByAmount {
                            TextField("Importe USD", text: $amountUsd).keyboardType(.decimalPad)
                                .onChange(of: amountUsd) { _, _ in commandIDs.removeValue(forKey: "create") }
                        } else {
                            TextField("Volumen solicitado", text: $requestedVolume).keyboardType(.decimalPad)
                                .onChange(of: requestedVolume) { _, _ in commandIDs.removeValue(forKey: "create") }
                            Picker("Unidad", selection: $volumeUnit) {
                                Text("Galón US").tag("gallon_us")
                                Text("Litro").tag("liter")
                            }.pickerStyle(.segmented)
                                .onChange(of: volumeUnit) { _, _ in commandIDs.removeValue(forKey: "create") }
                        }
                        actionButton("Solicitar autorización", symbol: "lock.open", key: "create", isEnabled: requestByAmount ? !amountUsd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : !requestedVolume.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                            try await vm.createAuthorization(
                                nozzleID: nozzle.id,
                                commandID: commandID("create"),
                                amountUsd: requestByAmount ? amountUsd : nil,
                                volume: requestByAmount ? nil : requestedVolume,
                                volumeUnit: requestByAmount ? nil : volumeUnit
                            )
                        }
                    }
                }

                if !errorMessage.isEmpty {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(DLCTheme.red)
                    }
                }
            }
            .navigationTitle("Despacho")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() }.disabled(isWorking) }
            }
            .disabled(isWorking)
            .task {
                do { deviceCapabilities = try await vm.deviceCapabilities() }
                catch { deviceCapabilities = nil }
                if let authorization, authorization.status == "completed", vm.canReadSales { await lookupSale(authorization.id) }
            }
        }
    }

    private func lookupSale(_ authorizationID: UUID) async {
        isWorking = true
        saleLookupCompleted = false
        defer { isWorking = false }
        do {
            fuelSale = try await vm.fuelSale(for: authorizationID)
            saleLookupCompleted = true
            errorMessage = ""
        } catch { errorMessage = error.localizedDescription }
    }

    private func runDevice(_ authorization: RemoteDispenseAuthorization, operation: String) async throws -> RemoteDispenseAuthorization {
        let key = "device-\(operation)"
        if deviceExpectedVersions[key] == nil { deviceExpectedVersions[key] = authorization.version }
        let response = try await vm.deviceOperation(authorization, commandID: commandID(key), operation: operation,
            expectedVersion: deviceExpectedVersions[key] ?? authorization.version, scenario: operation == "start" ? deviceScenario : nil)
        switch response.device.outcome?.status ?? "" {
        case "timeout": deviceMessage = "El simulador no respondió. La reserva se conserva; consulta el resultado original."
        case "completed": deviceMessage = "Resultado simulado confirmado: \(response.device.outcome?.measuredL ?? "") L."
        case "no_flow": deviceMessage = "El simulador confirmó que no hubo flujo; la reserva se liberó."
        default: deviceMessage = "Inicio simulado registrado. Consulta el resultado para finalizar la prueba."
        }
        return response.data
    }

    private func actionButton(
        _ title: String,
        symbol: String,
        key: String,
        isEnabled: Bool = true,
        operation: @escaping () async throws -> RemoteDispenseAuthorization
    ) -> some View {
        Button {
            Task { await perform(key: key, operation) }
        } label: {
            if isWorking { ProgressView() } else { Label(title, systemImage: symbol) }
        }
        .disabled(isWorking || requiresRefreshBeforeAction || !isEnabled)
    }

    private func perform(key: String, _ operation: @escaping () async throws -> RemoteDispenseAuthorization) async {
        isWorking = true
        errorMessage = ""
        defer { isWorking = false }
        do {
            authorization = try await operation()
            commandIDs[key] = UUID()
            deviceExpectedVersions.removeValue(forKey: key)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func complete(_ authorization: RemoteDispenseAuthorization) async throws -> RemoteDispenseAuthorization {
        if completionExpectedVersion == nil { completionExpectedVersion = authorization.version }
        return try await vm.completeAuthorization(
            authorization,
            commandID: commandID("complete"),
            quantity: measuredQuantity,
            unit: measuredUnit,
            documentReference: documentReference.isEmpty ? nil : documentReference,
            expectedVersion: completionExpectedVersion
        )
    }

    private func refresh() async {
        guard let authorization else { return }
        isWorking = true
        errorMessage = ""
        defer { isWorking = false }
        do {
            let refreshed = try await vm.refreshAuthorization(authorization.id)
            self.authorization = refreshed
            requiresRefreshBeforeAction = false
            commandIDs = commandIDs.filter { $0.key == "complete" || $0.key == "sale" || $0.key.hasPrefix("device-") }
            if refreshed.status != "posting" {
                commandIDs.removeValue(forKey: "complete")
                completionExpectedVersion = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


private func dispenseStatusLabel(_ status: String) -> String {
    switch status {
    case "authorized": "Autorizado"
    case "dispensing": "En despacho"
    case "unknown": "Pendiente de conciliación"
    case "posting": "Registrando venta"
    case "completed": "Completado"
    case "cancelled": "Cancelado"
    case "expired": "Vencido"
    default: status.capitalized
    }
}


private enum RemoteDispenseQueueFilter: String, CaseIterable, Identifiable {
    case active = "Activos"
    case unknown = "Por conciliar"
    case posting = "Registrando"
    case all = "Todos"
    var id: String { rawValue }
    var status: String? {
        switch self {
        case .active: "active"
        case .unknown: "unknown"
        case .posting: "posting"
        case .all: nil
        }
    }
}

@MainActor
struct RemoteDispenseQueueView: View {
    @ObservedObject var vm: RemotePumpsViewModel
    @State private var filter: RemoteDispenseQueueFilter = .active
    @State private var selectedAuthorization: RemoteDispenseAuthorization?
    let prepaymentClient: RemoteAPIClient?
    let prepaymentStore: RemoteOfflineStore?
    let prepaymentScope: RemoteDataScope?
    let prepaymentBranchID: UUID?
    let canCollectPrepayments: Bool
    let canReadCash: Bool
    let canReadPrepayments: Bool

    init(vm: RemotePumpsViewModel, prepaymentClient: RemoteAPIClient? = nil, prepaymentStore: RemoteOfflineStore? = nil,
         prepaymentScope: RemoteDataScope? = nil, prepaymentBranchID: UUID? = nil,
         canCollectPrepayments: Bool = false, canReadCash: Bool = false, canReadPrepayments: Bool = false) {
        _vm = ObservedObject(wrappedValue: vm)
        self.prepaymentClient = prepaymentClient
        self.prepaymentStore = prepaymentStore
        self.prepaymentScope = prepaymentScope
        self.prepaymentBranchID = prepaymentBranchID
        self.canCollectPrepayments = canCollectPrepayments
        self.canReadCash = canReadCash
        self.canReadPrepayments = canReadPrepayments
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Despachos").font(.largeTitle.weight(.bold))
                    Text("Reservas, ventas en curso y resultados por conciliar")
                        .font(.subheadline).foregroundStyle(DLCTheme.muted)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RemoteDispenseQueueFilter.allCases) { option in
                            Button {
                                guard option != filter else { return }
                                filter = option
                                Task { await vm.loadAuthorizations(status: option.status) }
                            } label: {
                                Text(option.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(filter == option ? Color.white : DLCTheme.ink)
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(filter == option ? DLCTheme.forest : DLCTheme.surface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button { Task { await vm.loadAuthorizations(status: filter.status) } } label: {
                        Label("Actualizar", systemImage: "arrow.clockwise")
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(vm.isLoadingAuthorizations)
                }
                if vm.authorizationsAreStale {
                    Label("Se muestran despachos guardados; confirma el estado en el servidor antes de actuar.", systemImage: "clock.arrow.circlepath")
                        .font(.footnote).foregroundStyle(DLCTheme.orange).fixedSize(horizontal: false, vertical: true)
                }
                if !vm.authorizationErrorMessage.isEmpty {
                    Label(vm.authorizationErrorMessage, systemImage: "wifi.exclamationmark")
                        .font(.footnote).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true)
                }
                if vm.isLoadingAuthorizations && vm.authorizations.isEmpty {
                    ProgressView("Consultando despachos…").frame(maxWidth: .infinity).padding(28)
                } else if vm.authorizations.isEmpty {
                    ContentUnavailableView("Sin despachos", systemImage: "fuelpump", description: Text("No hay autorizaciones para este filtro."))
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    Text("\(vm.authorizations.count) resultados cargados")
                        .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.muted)
                    LazyVStack(spacing: 10) {
                        ForEach(vm.authorizations) { authorization in
                            Button { selectedAuthorization = authorization } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(dispenseStatusLabel(authorization.status))
                                            .font(.headline).foregroundStyle(DLCTheme.ink)
                                        Spacer()
                                        Text("v\(authorization.version)")
                                            .font(.caption.monospacedDigit()).foregroundStyle(DLCTheme.muted)
                                    }
                                    Text("\(authorization.dispenserCode ?? "Bomba") · manguera \(authorization.nozzleCode ?? String(authorization.nozzleId.uuidString.prefix(8))) · \(authorization.fuelName ?? "Combustible")")
                                        .font(.caption).foregroundStyle(DLCTheme.muted)
                                    Text("Reserva \(authorization.reservedL) L · avance \(authorization.progressL) L")
                                        .font(.subheadline.weight(.medium)).foregroundStyle(DLCTheme.ink)
                                    Text("Precio: $\(authorization.priceUsdPerUnit) / \(authorization.priceUnit) · vence \(authorization.expiresAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")")
                                        .font(.caption).foregroundStyle(DLCTheme.muted)
                                    Label("Abrir ficha y continuar", systemImage: "chevron.right")
                                        .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.orange)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .dlcCard()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if vm.hasMoreAuthorizations {
                        Button { Task { await vm.loadMoreAuthorizations() } } label: {
                            if vm.isLoadingMoreAuthorizations { ProgressView() } else { Text("Cargar más") }
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
            }.padding(20)
        }
        .navigationTitle("Despachos pendientes")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .task { if vm.authorizations.isEmpty { await vm.loadAuthorizations(status: filter.status) } }
        .sheet(item: $selectedAuthorization, onDismiss: {
            Task { await vm.loadAuthorizations(status: filter.status) }
        }) { authorization in
            RemoteDispenseFlowSheet(vm: vm, initialAuthorization: authorization, requiresRefresh: vm.authorizationsAreStale,
                prepaymentClient: prepaymentClient, prepaymentStore: prepaymentStore, prepaymentScope: prepaymentScope,
                prepaymentBranchID: prepaymentBranchID, canCollectPrepayments: canCollectPrepayments, canReadCash: canReadCash,
                canReadPrepayments: canReadPrepayments)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct RemoteFuelSaleContent: View {
    let sale: RemoteFuelSale
    var body: some View {
        Group {
            LabeledContent("Comprobante", value: String(sale.id.uuidString.prefix(8)))
            Label(fuelSaleStatusTitle(sale.status), systemImage: sale.status == "paid" ? "checkmark.circle" : sale.status == "on_credit" ? "person.crop.circle.badge.clock" : "clock")
                .foregroundStyle(sale.status == "paid" ? DLCTheme.green : sale.status == "on_credit" ? DLCTheme.blue : DLCTheme.orange)
            if let outstanding = sale.outstandingUsd { LabeledContent("Saldo pendiente", value: "$\(outstanding)") }
            if let refunded = sale.refundedUsd, sale.refundStatus != "none" { LabeledContent("Reembolsado", value: "$\(refunded)") }
            LabeledContent("Importe", value: "$\(sale.totalUsd) USD")
            if let date = sale.occurredAt { LabeledContent("Fecha", value: date.formatted(date: .abbreviated, time: .shortened)) }
            ForEach(sale.lines) { line in
                Text(line.description).font(.headline)
                if let liters = line.quantityL { LabeledContent("Volumen vendido", value: "\(liters) L") }
                if let units = line.quantityUnits { LabeledContent("Cantidad", value: "\(units) unidades") }
                LabeledContent("Precio aplicado", value: "$\(line.priceUsdPerUnit) / \(line.priceUnit == "unit" ? "unidad" : (line.priceUnit == "us_gallon" ? "galón US" : "litro"))")
                if line.costQuality != "restricted" {
                    LabeledContent("Costo registrado", value: line.costUsd.map { "$\($0)" } ?? "Sin costo confirmado")
                }
            }
            if sale.taxStatus == "configured" {
                LabeledContent("Venta sin impuestos", value: "$\(sale.netUsd ?? "—")")
                ForEach(sale.taxComponents) { component in LabeledContent(component.label, value: "$\(component.taxUsd)") }
                LabeledContent("Total de impuestos", value: "$\(sale.taxUsd ?? "—")")
                Text("Comprobante interno").font(.footnote).foregroundStyle(DLCTheme.muted)
            } else {
                Text("Comprobante interno · desglose fiscal pendiente")
                    .font(.footnote).foregroundStyle(DLCTheme.muted)
            }
        }
    }
}

struct RemoteFuelSalesView: View {
    let repository: RemotePumpRepository
    let branchID: UUID
    var client: RemoteAPIClient? = nil
    var store: RemoteOfflineStore? = nil
    var scope: RemoteDataScope? = nil
    var canReadPayments = false
    var canCollectPayments = false
    var canResolvePayments = false
    var canReadCash = false
    var canRequestRefund = false
    var canDecideRefund = false
    var canExecuteRefund = false
    var canCreateSales = false
    @State private var query = ""
    @State private var rows: [RemoteFuelSaleSummary] = []
    @State private var nextCursor: String?
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var generation = 0
    var body: some View {
        List {
            Section {
                ForEach(rows) { row in
                    NavigationLink {
                        RemoteFuelSaleDetailView(
                            repository: repository, branchID: branchID, saleID: row.id,
                            client: client, store: store, scope: scope,
                            canCreateSales: canCreateSales,
                            canReadPayments: canReadPayments, canCollectPayments: canCollectPayments,
                            canResolvePayments: canResolvePayments, canReadCash: canReadCash,
                            canRequestRefund: canRequestRefund, canDecideRefund: canDecideRefund,
                            canExecuteRefund: canExecuteRefund
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(row.description).font(.headline); Spacer(); Text("$\(row.totalUsd)").bold() }
                            Text((row.quantityL.map { "\($0) L" } ?? "\(row.lineCount) líneas") + " · " + fuelSaleStatusTitle(row.status)).font(.caption).foregroundStyle(row.status == "paid" ? DLCTheme.green : row.status == "on_credit" ? DLCTheme.blue : DLCTheme.orange)
                            if let date = row.occurredAt { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption) }
                        }
                    }
                }
                if rows.isEmpty && !isLoading && errorMessage.isEmpty { Text("Sin ventas registradas para esta búsqueda.") }
                if nextCursor != nil { Button("Cargar más") { Task { await load(more: true) } }.disabled(isLoading) }
                if isLoading { ProgressView("Cargando ventas…") }
                if !errorMessage.isEmpty { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(DLCTheme.red) }
            }
        }
        .navigationTitle("Ventas")
        .searchable(text: $query, prompt: "Producto, servicio o ID de comprobante")
        .onSubmit(of: .search) { Task { await load(more: false) } }
        .refreshable { await load(more: false) }
        .task { await load(more: false) }
    }
    private func load(more: Bool) async {
        if more && isLoading { return }
        generation += 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = ""
        let requestedQuery = query
        let cursor = more ? nextCursor : nil
        if !more { rows = []; nextCursor = nil }
        defer { if requestGeneration == generation { isLoading = false } }
        do {
            let page = try await repository.fuelSales(branchId: branchID, query: requestedQuery, cursor: cursor)
            guard requestGeneration == generation else { return }
            rows = more ? rows + page.data.filter { incoming in !rows.contains { $0.id == incoming.id } } : page.data
            nextCursor = page.meta.nextCursor
        } catch {
            guard requestGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
private struct RemotePrepaymentCollectionPanel: View {
    @StateObject private var vm: RemotePrepaymentRefundViewModel
    let authorizationID: UUID
    let canReadCash: Bool
    let canReadHistory: Bool
    let canAct: Bool
    @State private var showCollection = false

    init(client: RemoteAPIClient, store: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID,
         authorizationID: UUID, canReadCash: Bool, canReadHistory: Bool, canAct: Bool) {
        _vm = StateObject(wrappedValue: RemotePrepaymentRefundViewModel(
            client: client, store: store, scope: scope, branchID: branchID,
            canReadCash: canReadCash, canReadPrepayments: canReadHistory, canCollectPrepayments: canAct
        ))
        self.authorizationID = authorizationID
        self.canReadCash = canReadCash
        self.canReadHistory = canReadHistory
        self.canAct = canAct
    }

    private var relatedAdvances: [RemotePrepayment] { vm.advances.filter { $0.authorizationId == authorizationID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Registra el dinero recibido antes de iniciar el despacho. Solo un pago confirmado se suma a caja.")
                .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
            if vm.isLoading && relatedAdvances.isEmpty { ProgressView("Consultando anticipos…").font(.caption) }
            ForEach(relatedAdvances) { advance in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(advance.method == "cash" ? "Efectivo" : "Tarjeta")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.ink)
                        Text(prepaymentRefundStatus(advance)).font(.caption).foregroundStyle(prepaymentRefundColor(advance))
                    }
                    Spacer()
                    Text("$\(advance.amountUsd)").font(.subheadline.monospacedDigit().weight(.bold))
                }.padding(9).background(DLCTheme.surface, in: RoundedRectangle(cornerRadius: 11))
            }
            if !canReadHistory {
                Label("Tienes permiso para registrar, pero no para consultar el historial de anticipos.", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
            } else if canReadCash && relatedAdvances.isEmpty && !vm.isLoading && vm.errorMessage.isEmpty {
                Text("Todavía no hay anticipos ligados a esta autorización.").font(.caption).foregroundStyle(DLCTheme.muted)
            }
            if canAct && !canReadCash {
                Label("Para registrar un anticipo necesitas también cash.read y una caja abierta propia.", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(DLCTheme.orange).fixedSize(horizontal: false, vertical: true)
            } else if canAct && vm.openSessions.isEmpty && !vm.isLoading {
                Label("Abre tu turno en Caja y arqueos antes de recibir el anticipo.", systemImage: "dollarsign.circle")
                    .font(.caption).foregroundStyle(DLCTheme.orange).fixedSize(horizontal: false, vertical: true)
            } else if canAct {
                Button { showCollection = true } label: {
                    Label("Registrar anticipo", systemImage: "creditcard.and.123").frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.borderedProminent).tint(DLCTheme.forest).disabled(!vm.canStartCommand || vm.isLoading)
            }
            if !vm.errorMessage.isEmpty { Label(vm.errorMessage, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true) }
            if !vm.recoveryError.isEmpty { Label(vm.recoveryError, systemImage: "lock.fill").font(.caption).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true) }
            if !vm.notice.isEmpty { Label(vm.notice, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(DLCTheme.green).fixedSize(horizontal: false, vertical: true) }
        }
        .task { await vm.load() }
        .sheet(isPresented: $showCollection) {
            RemotePrepaymentCollectSheet(vm: vm, authorizationID: authorizationID) { await vm.load() }
        }
    }
}

@MainActor
private struct RemotePrepaymentCollectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemotePrepaymentRefundViewModel
    let authorizationID: UUID
    let onSaved: () async -> Void
    @State private var amount = ""
    @State private var method = "cash"
    @State private var tenderKind = "captured"
    @State private var outcome = "confirmed"
    @State private var evidence = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Recepción previa al despacho") {
                    LabeledContent("Autorización", value: String(authorizationID.uuidString.prefix(8)))
                    TextField("Importe recibido (USD)", text: $amount).keyboardType(.decimalPad)
                    Picker("Medio", selection: $method) {
                        Text("Efectivo").tag("cash")
                        Text("Tarjeta").tag("card")
                    }.pickerStyle(.segmented)
                    Picker("Tipo", selection: $tenderKind) {
                        Text("Cobro capturado").tag("captured")
                        if method == "card" { Text("Retención de tarjeta").tag("authorization_hold") }
                    }.pickerStyle(.menu)
                    Picker("Resultado", selection: $outcome) {
                        Text("Confirmado").tag("confirmed")
                        if method == "card" {
                            if tenderKind == "captured" { Text("Rechazado").tag("declined") }
                            Text("Sin respuesta").tag("unknown")
                        }
                    }.pickerStyle(.segmented)
                    Picker("Caja / turno", selection: $vm.selectedCashSessionID) {
                        ForEach(vm.openSessions) { register in Text("Caja \(register.code)").tag(register.openSessionId) }
                    }
                }
                if method == "card" && (outcome != "unknown" || tenderKind == "authorization_hold") {
                    Section("Evidencia del terminal") {
                        TextField("Proveedor, terminal y referencia", text: $evidence).autocorrectionDisabled()
                        Text("No ingreses PAN completo, CVV ni credenciales. El sistema no procesa tarjetas.")
                            .font(.caption).foregroundStyle(DLCTheme.muted)
                    }
                }
                if method == "cash" {
                    Section { Text("Efectivo se registra únicamente como capturado y confirmado.").font(.caption).foregroundStyle(DLCTheme.muted) }
                } else if tenderKind == "authorization_hold" {
                    Section { Text("Una retención no se cuenta como efectivo recibido; su liberación se concilia aparte.").font(.caption).foregroundStyle(DLCTheme.muted) }
                }
                if !vm.errorMessage.isEmpty { Section { Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(DLCTheme.red) } }
                Section {
                    Button("Registrar anticipo") {
                        Task {
                            if await vm.collectPrepayment(authorizationID: authorizationID, amount: amount,
                                method: method, tenderKind: tenderKind, outcome: outcome, evidence: evidence) {
                                await onSaved()
                                dismiss()
                            }
                        }
                    }.frame(maxWidth: .infinity).buttonStyle(.borderedProminent).tint(DLCTheme.forest)
                        .disabled(vm.isPosting || !vm.canStartCommand || vm.selectedCashSessionID == nil || amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Registrar anticipo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(vm.isPosting) } }
            .interactiveDismissDisabled(vm.isPosting)
            .onChange(of: method) { _, value in
                if value == "cash" { tenderKind = "captured"; outcome = "confirmed"; evidence = "" }
            }
            .onChange(of: tenderKind) { _, value in
                if value == "authorization_hold" && outcome == "declined" { outcome = "unknown" }
            }
        }
    }
}

private enum RemotePrepaymentSheet: Identifiable {
    case request(RemotePrepayment)
    case decide(RemotePrepayment)
    case execute(RemotePrepayment)
    case allocate(RemotePrepayment)
    case resolve(RemotePrepayment)
    case requestRelease(RemotePrepayment)
    case confirmRelease(RemotePrepayment)

    var id: String {
        switch self {
        case .request(let advance): "request-\(advance.id.uuidString)"
        case .decide(let advance): "decide-\(advance.id.uuidString)"
        case .execute(let advance): "execute-\(advance.id.uuidString)"
        case .allocate(let advance): "allocate-\(advance.id.uuidString)"
        case .resolve(let advance): "resolve-\(advance.id.uuidString)"
        case .requestRelease(let advance): "request-release-\(advance.id.uuidString)"
        case .confirmRelease(let advance): "confirm-release-\(advance.id.uuidString)"
        }
    }
}

@MainActor
struct RemotePrepaymentsView: View {
    @StateObject private var vm: RemotePrepaymentRefundViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var activeSheet: RemotePrepaymentSheet?
    let canRequest: Bool
    let canDecide: Bool
    let canExecute: Bool
    let canAllocate: Bool
    let canResolve: Bool

    init(client: RemoteAPIClient, store: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID,
         canRequest: Bool, canDecide: Bool, canExecute: Bool, canReadCash: Bool,
         canAllocate: Bool, canResolve: Bool) {
        _vm = StateObject(wrappedValue: RemotePrepaymentRefundViewModel(
            client: client, store: store, scope: scope, branchID: branchID, canReadCash: canReadCash,
            canCollectPrepayments: canAllocate, canResolvePrepayments: canResolve
        ))
        self.canRequest = canRequest
        self.canDecide = canDecide
        self.canExecute = canExecute
        self.canAllocate = canAllocate
        self.canResolve = canResolve
    }

    private var filteredAdvances: [RemotePrepayment] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return vm.advances }
        return vm.advances.filter {
            $0.id.uuidString.lowercased().contains(term) || $0.authorizationId.uuidString.lowercased().contains(term)
                || $0.method.lowercased().contains(term) || ($0.requestStatus ?? "sin solicitud").lowercased().contains(term)
                || $0.outcome.lowercased().contains(term) || ($0.releaseStatus ?? "").lowercased().contains(term)
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    prepaymentMetric("Anticipos", value: "\(vm.advances.count)", color: DLCTheme.ink)
                    prepaymentMetric("Por revisar", value: "\(vm.advances.filter { $0.requestStatus == "pending" }.count)", color: DLCTheme.orange)
                    prepaymentMetric("Ejecutados", value: "\(vm.advances.filter { $0.refundId != nil }.count)", color: DLCTheme.green)
                }
                Text("Últimos 100 anticipos de esta sucursal. Desde cada registro puedes aplicar saldo a su venta o conciliar una retención con evidencia del terminal.")
                    .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
            } header: { Text("Control de anticipos") }

            Section("Registros") {
                if vm.isLoading && vm.advances.isEmpty { ProgressView("Consultando anticipos…") }
                if filteredAdvances.isEmpty && !vm.isLoading && vm.errorMessage.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Sin anticipos" : "Sin resultados", systemImage: "creditcard", description: Text(query.isEmpty ? "Los anticipos de despacho aparecerán aquí." : "Prueba con otro ID, medio o estado."))
                }
                ForEach(filteredAdvances) { advance in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(advance.method == "cash" ? "Anticipo en efectivo" : "Anticipo con tarjeta")
                                    .font(.headline).foregroundStyle(DLCTheme.ink)
                                Text("\(advance.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(advance.tenderKind == "captured" ? "capturado" : "retención") · \(advance.outcome == "confirmed" ? "confirmado" : advance.outcome == "unknown" ? "por conciliar" : "rechazado")")
                                    .font(.caption).foregroundStyle(advance.outcome == "confirmed" ? DLCTheme.muted : DLCTheme.orange)
                            }
                            Spacer(minLength: 6)
                            Text("$\(advance.amountUsd)").font(.headline.monospacedDigit()).foregroundStyle(DLCTheme.ink)
                        }
                        LabeledContent("Autorización", value: String(advance.authorizationId.uuidString.prefix(8)))
                        LabeledContent("Asignado a venta", value: "$\(advance.allocatedUsd)")
                        LabeledContent("No aplicado a venta", value: "$\(advance.remainingUsd)")
                        HStack {
                            Label(prepaymentRefundStatus(advance), systemImage: prepaymentRefundSymbol(advance))
                                .font(.caption.weight(.semibold)).foregroundStyle(prepaymentRefundColor(advance))
                            Spacer()
                            if let refundedAt = advance.refundedAt {
                                Text(refundedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(DLCTheme.muted)
                            }
                        }
                        if let reason = advance.reason, !reason.isEmpty {
                            Text("Motivo: \(reason)").font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        if let decisionReason = advance.decisionReason, !decisionReason.isEmpty {
                            Text("Resolución: \(decisionReason)").font(.caption2).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        if canResolve, advance.outcome == "unknown" {
                            Button("Conciliar resultado del terminal") { activeSheet = .resolve(advance) }
                                .buttonStyle(.bordered).tint(DLCTheme.orange).disabled(!vm.canStartCommand)
                        }
                        if canAllocate, advance.tenderKind == "captured", advance.outcome == "confirmed",
                           advance.disposition == nil, advance.requestStatus == nil, advance.refundId == nil,
                           (Decimal(string: advance.remainingUsd, locale: Locale(identifier: "en_US_POSIX")) ?? 0) > 0 {
                            Button("Aplicar anticipo a su venta") { activeSheet = .allocate(advance) }
                                .buttonStyle(.borderedProminent).tint(DLCTheme.forest).disabled(!vm.canStartCommand)
                        }
                        if canResolve, advance.tenderKind == "authorization_hold", advance.outcome == "confirmed" {
                            if advance.releaseStatus == "pending" {
                                Button("Confirmar liberación de tarjeta") { activeSheet = .confirmRelease(advance) }
                                    .buttonStyle(.borderedProminent).tint(DLCTheme.forest).disabled(!vm.canStartCommand)
                            } else if advance.releaseStatus == nil, advance.disposition == nil,
                                      (Decimal(string: advance.remainingUsd, locale: Locale(identifier: "en_US_POSIX")) ?? 0) > 0 {
                                Button("Solicitar liberación de retención") { activeSheet = .requestRelease(advance) }
                                    .buttonStyle(.bordered).tint(DLCTheme.orange).disabled(!vm.canStartCommand)
                            }
                        }
                        if advance.requestStatus == "pending", canDecide, advance.requestedBy != vm.scope.userId {
                            Button("Revisar devolución") { activeSheet = .decide(advance) }
                                .buttonStyle(.bordered).tint(DLCTheme.ink).disabled(!vm.canStartCommand)
                        } else if advance.requestStatus == "pending", advance.requestedBy == vm.scope.userId {
                            Label("Pendiente de decisión independiente", systemImage: "person.badge.clock").font(.caption).foregroundStyle(DLCTheme.orange)
                        }
                        if advance.requestStatus == "approved", advance.refundId == nil,
                           advance.requestedBy == vm.scope.userId, canExecute {
                            if vm.canReadCash && !vm.openSessions.isEmpty {
                                Button("Ejecutar devolución aprobada") { activeSheet = .execute(advance) }
                                    .buttonStyle(.borderedProminent).tint(DLCTheme.orangeFill).disabled(!vm.canStartCommand)
                            } else {
                                Label("Necesitas una caja abierta propia para registrar la salida.", systemImage: "lock.fill")
                                    .font(.caption).foregroundStyle(DLCTheme.muted)
                            }
                        }
                        if canRequest, refundableBalance(advance) > 0, advance.requestStatus == nil,
                           advance.tenderKind == "captured", advance.outcome == "confirmed" {
                            Button("Solicitar devolución del remanente · $\(advance.refundableUsd)") { activeSheet = .request(advance) }
                                .buttonStyle(.bordered).tint(DLCTheme.orange).disabled(!vm.canStartCommand)
                        }
                    }
                    .padding(.vertical, 5)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }

            if !vm.pending.isEmpty {
                Section("Acciones sin confirmar") {
                    ForEach(vm.pending) { draft in
                        VStack(alignment: .leading, spacing: 7) {
                            Label("El resultado de una acción no quedó confirmado en este dispositivo.", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.orange)
                            Button("Consultar / reintentar con el mismo comando") {
                                Task { _ = await vm.retry(draft) }
                            }.font(.caption.weight(.semibold)).disabled(vm.isPosting)
                        }
                    }
                }
            }
            if !vm.recoveryError.isEmpty { Section { Label(vm.recoveryError, systemImage: "lock.fill").font(.caption).foregroundStyle(DLCTheme.red) } }
            if !vm.errorMessage.isEmpty { Section { Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true) } }
            if !vm.notice.isEmpty { Section { Label(vm.notice, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(DLCTheme.green).fixedSize(horizontal: false, vertical: true) } }
        }
        .navigationTitle("Anticipos")
        .searchable(text: $query, prompt: "Autorización, medio o estado")
        .refreshable { await vm.load() }
        .task { vm.refreshPending(); await vm.load() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: filteredAdvances.count)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .request(let advance): RemotePrepaymentRefundActionSheet(vm: vm, advance: advance, action: .request)
            case .decide(let advance): RemotePrepaymentRefundActionSheet(vm: vm, advance: advance, action: .decide)
            case .execute(let advance): RemotePrepaymentRefundActionSheet(vm: vm, advance: advance, action: .execute)
            case .allocate(let advance): RemotePrepaymentAllocationSheet(client: vm.client, branchID: vm.branchID, vm: vm, advance: advance) { await vm.load() }
            case .resolve(let advance): RemotePrepaymentRefundActionSheet(vm: vm, advance: advance, action: .resolve)
            case .requestRelease(let advance): RemotePrepaymentRefundActionSheet(vm: vm, advance: advance, action: .requestRelease)
            case .confirmRelease(let advance): RemotePrepaymentRefundActionSheet(vm: vm, advance: advance, action: .confirmRelease)
            }
        }
    }

    private func prepaymentMetric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(DLCTheme.muted)
            Text(value).font(.title3.monospacedDigit().weight(.bold)).foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(DLCTheme.surface, in: RoundedRectangle(cornerRadius: 13))
    }

    private func refundableBalance(_ advance: RemotePrepayment) -> Decimal {
        Decimal(string: advance.refundableUsd, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }
}

@MainActor
private struct RemotePrepaymentAllocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemotePrepaymentRefundViewModel
    let client: RemoteAPIClient
    let branchID: UUID
    let advance: RemotePrepayment
    let onSaved: () async -> Void
    @State private var sale: RemoteFuelSale?
    @State private var amount = ""
    @State private var isLoading = false
    @State private var errorMessage = ""

    private var maximum: Decimal? {
        guard let sale, sale.status == "completed", sale.authorizationId == advance.authorizationId,
              let remaining = Decimal(string: advance.remainingUsd, locale: Locale(identifier: "en_US_POSIX")),
              let outstandingRaw = sale.outstandingUsd,
              let outstanding = Decimal(string: outstandingRaw, locale: Locale(identifier: "en_US_POSIX")),
              remaining > 0, outstanding > 0 else { return nil }
        return min(remaining, outstanding)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Anticipo confirmado") {
                    LabeledContent("Saldo no asignado", value: "$\(advance.remainingUsd)")
                    LabeledContent("Despacho", value: String(advance.authorizationId.uuidString.prefix(8)))
                }
                Section("Venta del despacho") {
                    if isLoading { ProgressView("Consultando venta…") }
                    if let sale {
                        LabeledContent("Venta", value: String(sale.id.uuidString.prefix(8)))
                        LabeledContent("Total", value: "$\(sale.totalUsd)")
                        LabeledContent("Pendiente", value: "$\(sale.outstandingUsd ?? "—")")
                        if let maximum {
                            TextField("Importe a aplicar (USD)", text: $amount).keyboardType(.decimalPad)
                            Button("Usar máximo disponible · $\(NSDecimalNumber(decimal: maximum).stringValue)") {
                                amount = NSDecimalNumber(decimal: maximum).stringValue
                            }.font(.caption.weight(.semibold))
                        }
                    } else if !isLoading && errorMessage.isEmpty {
                        ContentUnavailableView("Venta no disponible", systemImage: "receipt", description: Text("La asignación requiere que el despacho original tenga una venta completada."))
                    }
                }
                if !errorMessage.isEmpty { Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(DLCTheme.red) } }
                Section {
                    Button("Aplicar anticipo a la venta") {
                        guard let sale else { return }
                        Task {
                            if await vm.allocatePrepayment(advance, to: sale, amount: amount) {
                                await onSaved()
                                dismiss()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).buttonStyle(.borderedProminent).tint(DLCTheme.forest)
                    .disabled(isLoading || maximum == nil || amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isPosting || !vm.canStartCommand)
                }
            }
            .navigationTitle("Asignar anticipo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(vm.isPosting) } }
            .interactiveDismissDisabled(vm.isPosting)
            .task { await loadSale() }
        }
    }

    private func loadSale() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }
        do {
            guard let loaded = try await client.fuelSale(branchId: branchID, authorizationId: advance.authorizationId),
                  loaded.status == "completed", loaded.authorizationId == advance.authorizationId else {
                errorMessage = "No existe una venta completada asociada al despacho original."
                return
            }
            guard loaded.outstandingUsd != nil else {
                errorMessage = "La venta no devolvió el saldo pendiente. Actualiza la venta antes de asignar el anticipo."
                return
            }
            sale = loaded
            if let maximum { amount = NSDecimalNumber(decimal: maximum).stringValue }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum RemotePrepaymentRefundAction: Equatable {
    case request, decide, execute, resolve, requestRelease, confirmRelease
}

@MainActor
private struct RemotePrepaymentRefundActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemotePrepaymentRefundViewModel
    let advance: RemotePrepayment
    let action: RemotePrepaymentRefundAction
    @State private var reason = ""
    @State private var decision = "approved"
    @State private var evidence = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(advanceSectionTitle) {
                    LabeledContent("Medio", value: advance.method == "cash" ? "Efectivo" : "Tarjeta")
                    LabeledContent("Importe original", value: "$\(advance.amountUsd)")
                    LabeledContent("Asignado a venta", value: "$\(advance.allocatedUsd)")
                    LabeledContent("No aplicado / a devolver", value: "$\(advance.requestAmountUsd ?? advance.refundableUsd)")
                }
                if action == .request {
                    Section("Motivo") {
                        TextEditor(text: $reason).frame(minHeight: 100)
                        Text("La solicitud cubre el remanente completo y requiere una decisión de otra persona autorizada.").font(.caption).foregroundStyle(DLCTheme.muted)
                    }
                } else if action == .decide {
                    Section("Decisión independiente") {
                        Picker("Resultado", selection: $decision) {
                            Text("Aprobar").tag("approved")
                            Text("Rechazar").tag("rejected")
                        }.pickerStyle(.segmented)
                        TextEditor(text: $reason).frame(minHeight: 100).accessibilityLabel("Motivo de la decisión")
                        Text("No puedes aprobar una solicitud iniciada por tu mismo usuario.").font(.caption).foregroundStyle(DLCTheme.muted)
                    }
                } else if action == .execute {
                    Section("Salida de caja") {
                        Picker("Turno", selection: $vm.selectedCashSessionID) {
                            ForEach(vm.openSessions) { register in Text("Caja \(register.code)").tag(register.openSessionId) }
                        }
                        TextField("Referencia documental del terminal o comprobante", text: $evidence).autocorrectionDisabled()
                        Text("La devolución queda ligada a la aprobación y al turno abierto. No modifica inventario.").font(.caption).foregroundStyle(DLCTheme.muted)
                    }
                } else if action == .resolve {
                    Section("Resultado real del terminal") {
                        Picker("Resultado", selection: $decision) {
                            Text("Confirmado").tag("approved")
                            Text("Rechazado").tag("rejected")
                        }.pickerStyle(.segmented)
                        TextField("Referencia del terminal", text: $evidence).autocorrectionDisabled()
                        Text("Usa el resultado que figure en el terminal o comprobante. No se registra el número de tarjeta.")
                            .font(.caption).foregroundStyle(DLCTheme.muted)
                    }
                } else if action == .requestRelease {
                    Section("Liberar retención") {
                        LabeledContent("Saldo retenido", value: "$\(advance.remainingUsd)")
                        Text("Se registrará una solicitud de liberación por el saldo exacto. Después de que el terminal confirme la liberación, registra la referencia para cerrar la conciliación.")
                            .font(.caption).foregroundStyle(DLCTheme.muted)
                    }
                } else if action == .confirmRelease {
                    Section("Confirmación del terminal") {
                        LabeledContent("Saldo liberado", value: "$\(advance.remainingUsd)")
                        TextField("Referencia de confirmación", text: $evidence).autocorrectionDisabled()
                        Text("Confirma solo después de verificar en el terminal que la retención se liberó.")
                            .font(.caption).foregroundStyle(DLCTheme.muted)
                    }
                }
                if !vm.errorMessage.isEmpty { Section { Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(DLCTheme.red) } }
                Section {
                    Button(actionTitle) {
                        Task {
                            let success: Bool
                            switch action {
                            case .request: success = await vm.requestRefund(advance, reason: reason)
                            case .decide: success = await vm.decide(advance, decision: decision, reason: reason)
                            case .execute: success = await vm.executeRefund(advance, evidence: evidence)
                            case .resolve: success = await vm.resolvePrepayment(advance, outcome: decision == "approved" ? "confirmed" : "declined", evidence: evidence)
                            case .requestRelease: success = await vm.requestRelease(advance)
                            case .confirmRelease: success = await vm.confirmRelease(advance, evidence: evidence)
                            }
                            if success { dismiss() }
                        }
                    }
                    .frame(maxWidth: .infinity).buttonStyle(.borderedProminent)
                    .tint((action == .decide || action == .resolve) && decision == "rejected" ? DLCTheme.redFill : DLCTheme.forest)
                    .disabled(vm.isPosting || !vm.canStartCommand ||
                        ((action == .resolve || action == .confirmRelease) && !(1...200).contains(evidence.trimmingCharacters(in: .whitespacesAndNewlines).count)))
                }
            }
            .navigationTitle(actionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(vm.isPosting) } }
            .interactiveDismissDisabled(vm.isPosting)
        }
    }

    private var actionTitle: String {
        switch action {
        case .request: "Enviar a revisión"
        case .decide: decision == "approved" ? "Aprobar solicitud" : "Rechazar solicitud"
        case .execute: "Registrar devolución"
        case .resolve: decision == "approved" ? "Confirmar pago" : "Registrar rechazo"
        case .requestRelease: "Solicitar liberación"
        case .confirmRelease: "Confirmar liberación"
        }
    }

    private var advanceSectionTitle: String {
        switch action {
        case .request: "Anticipo capturado"
        case .decide: "Solicitud de devolución"
        case .execute: "Aprobación"
        case .resolve: "Pago por conciliar"
        case .requestRelease, .confirmRelease: "Retención de tarjeta"
        }
    }
}

private func prepaymentRefundStatus(_ advance: RemotePrepayment) -> String {
    if advance.refundId != nil { return "Devuelto y registrado" }
    if advance.releaseStatus == "released" { return "Liberación confirmada" }
    if advance.releaseStatus == "pending" { return "Liberación pendiente de confirmación" }
    if advance.requestStatus == "pending" { return "Pendiente de revisión" }
    if advance.requestStatus == "approved" { return "Aprobado · falta ejecutar" }
    if advance.requestStatus == "rejected" { return "Solicitud rechazada" }
    if advance.requestStatus == "cancelled" { return "Solicitud cancelada" }
    if advance.outcome == "unknown" { return "Pago por conciliar" }
    if advance.tenderKind == "authorization_hold" { return "Retención de tarjeta" }
    return "Sin devolución solicitada"
}

private func prepaymentRefundSymbol(_ advance: RemotePrepayment) -> String {
    if advance.refundId != nil || advance.releaseStatus == "released" { return "checkmark.circle.fill" }
    if advance.requestStatus == "pending" || advance.releaseStatus == "pending" { return "clock.fill" }
    if advance.requestStatus == "rejected" || advance.outcome == "declined" { return "xmark.circle.fill" }
    return "info.circle.fill"
}

private func prepaymentRefundColor(_ advance: RemotePrepayment) -> Color {
    if advance.refundId != nil { return DLCTheme.green }
    if advance.releaseStatus == "released" { return DLCTheme.green }
    if advance.requestStatus == "rejected" || advance.outcome == "declined" { return DLCTheme.red }
    if advance.requestStatus == "pending" || advance.requestStatus == "approved" || advance.outcome == "unknown" || advance.releaseStatus == "pending" { return DLCTheme.orange }
    return DLCTheme.muted
}

private struct RemoteFuelSaleDetailView: View {
    let repository: RemotePumpRepository
    let branchID: UUID
    let saleID: UUID
    let client: RemoteAPIClient?
    let store: RemoteOfflineStore?
    let scope: RemoteDataScope?
    let canCreateSales: Bool
    let canReadPayments: Bool
    let canCollectPayments: Bool
    let canResolvePayments: Bool
    let canReadCash: Bool
    let canRequestRefund: Bool
    let canDecideRefund: Bool
    let canExecuteRefund: Bool
    @State private var sale: RemoteFuelSale?
    @State private var combinedReceipt: RemoteCombinedInternalReceipt?
    @State private var errorMessage = ""
    @State private var showCombinedReceipt = false
    var body: some View {
        Form {
            if let sale {
                Section("Comprobante interno") { RemoteFuelSaleContent(sale: sale) }
                if sale.authorizationId != nil,
                   combinedReceipt != nil || (sale.status == "pending_collection" && canCreateSales && store != nil && scope != nil) {
                    Section("Comprobante combinado") {
                        if let combinedReceipt {
                            LabeledContent("Total interno combinado", value: "$\(combinedReceipt.totalUsd)")
                            LabeledContent("Cobro", value: fuelCombinedReceiptStatusTitle(combinedReceipt.collectionStatus))
                            Button("Ver desglose y estado por venta") { showCombinedReceipt = true }
                        } else if canCreateSales, store != nil, scope != nil {
                            Text("Agrupa una venta POS con esta venta de combustible sin alterar sus cobros ni sus datos fiscales.")
                                .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                            Button { showCombinedReceipt = true } label: {
                                Label("Combinar con una venta de tienda", systemImage: "doc.on.doc.fill")
                            }
                        }
                    }
                    .sheet(isPresented: $showCombinedReceipt, onDismiss: { Task { await reloadCombinedReceipt() } }) {
                        RemoteCombinedReceiptComposer(repository: repository, store: store, scope: scope, branchID: branchID, fuelSaleID: sale.id)
                    }
                }
                if let client, let store, let scope, canReadPayments || canCollectPayments {
                    Section("Cobros") {
                        RemoteSalePaymentsPanel(
                            client: client, store: store, scope: scope, branchID: branchID, sale: sale,
                            canReadPayments: canReadPayments, canCollectPayments: canCollectPayments,
                            canResolvePayments: canResolvePayments, canReadCash: canReadCash
                        ) {
                            await reloadSaleAndCombinedReceipt()
                        }
                    }
                }
                if let client, let store, let scope, canReadPayments,
                   canRequestRefund || canDecideRefund || canExecuteRefund {
                    Section("Devoluciones") {
                        RemoteSaleRefundPanel(
                            client: client, store: store, scope: scope, branchID: branchID, saleID: sale.id,
                            canReadCash: canReadCash, canRequest: canRequestRefund,
                            canDecide: canDecideRefund, canExecute: canExecuteRefund
                        ) { await reloadSale() }
                    }
                }
            } else if errorMessage.isEmpty { ProgressView("Cargando comprobante…") }
            if !errorMessage.isEmpty { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(DLCTheme.red) }
        }
        .navigationTitle("Detalle de venta")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { Task { await reloadSale() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Actualizar comprobante") } }
        .task {
            do {
                sale = try await repository.fuelSaleDetail(branchId: branchID, saleId: saleID)
                await reloadCombinedReceipt()
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func reloadSale() async {
        do { sale = try await repository.fuelSaleDetail(branchId: branchID, saleId: saleID); errorMessage = "" }
        catch { errorMessage = error.localizedDescription }
    }

    private func reloadCombinedReceipt() async {
        guard let sale, sale.authorizationId != nil else { combinedReceipt = nil; return }
        do { combinedReceipt = try await repository.combinedReceipt(branchId: branchID, saleId: sale.id) }
        catch { errorMessage = error.localizedDescription }
    }

    private func reloadSaleAndCombinedReceipt() async {
        await reloadSale()
        await reloadCombinedReceipt()
    }
}

@MainActor
private struct RemoteSalePaymentsPanel: View {
    @StateObject private var vm: RemotePaymentViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let sale: RemoteFuelSale
    let canReadPayments: Bool
    let canCollectPayments: Bool
    let canResolvePayments: Bool
    let canReadCash: Bool
    let onPaymentChanged: () async -> Void
    @State private var showCollection = false
    @State private var attemptToResolve: RemotePaymentAttempt?

    init(client: RemoteAPIClient, store: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID, sale: RemoteFuelSale,
         canReadPayments: Bool, canCollectPayments: Bool, canResolvePayments: Bool, canReadCash: Bool,
         onPaymentChanged: @escaping () async -> Void) {
        _vm = StateObject(wrappedValue: RemotePaymentViewModel(
            client: client, store: store, scope: scope, branchID: branchID, saleID: sale.id,
            saleStatus: sale.status, outstandingUsd: sale.outstandingUsd,
            canReadPayments: canReadPayments, canReadCash: canReadCash
        ))
        self.sale = sale
        self.canReadPayments = canReadPayments
        self.canCollectPayments = canCollectPayments
        self.canResolvePayments = canResolvePayments
        self.canReadCash = canReadCash
        self.onPaymentChanged = onPaymentChanged
    }

    private var hasBalance: Bool {
        guard sale.status != "on_credit" else { return false }
        guard let value = sale.outstandingUsd, let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return false }
        return amount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cobro de esta venta").font(.headline).foregroundStyle(DLCTheme.ink)
                    Text("Saldo por cobrar: $\(sale.outstandingUsd ?? "—")")
                        .font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(DLCTheme.orange)
                }
                Spacer()
                Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Actualizar pagos")
                    .disabled(vm.isLoading || vm.isPosting)
            }

            if sale.status == "on_credit" {
                Label("Esta venta está a crédito. El saldo se cobra desde el estado de cuenta comercial.", systemImage: "person.crop.circle.badge.clock")
                    .font(.caption).foregroundStyle(DLCTheme.blue).fixedSize(horizontal: false, vertical: true)
            }

            if canCollectPayments {
                if !canReadCash {
                    Label("Para registrar cobros también necesitas acceso de lectura a las cajas y sus turnos abiertos.", systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                } else if vm.openSessions.isEmpty && !vm.isLoading {
                    Label("No hay una caja abierta. Abre un turno desde Caja y arqueos antes de registrar el pago.", systemImage: "dollarsign.circle")
                        .font(.caption).foregroundStyle(DLCTheme.yellow).fixedSize(horizontal: false, vertical: true)
                } else if !vm.openSessions.isEmpty {
                    Picker("Turno que recibe el pago", selection: $vm.selectedCashSessionID) {
                        ForEach(vm.openSessions) { register in
                            Text("Caja \(register.code)").tag(register.openSessionId)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(vm.isPosting || !vm.pending.isEmpty)
                }
            }

            if vm.isLoading { ProgressView("Consultando pagos y caja…").font(.caption) }

            if canReadPayments {
                if vm.attempts.isEmpty && !vm.isLoading && vm.errorMessage.isEmpty {
                    Text("Todavía no hay intentos de cobro para este comprobante.")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
                ForEach(vm.attempts.reversed()) { attempt in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(attempt.method == "cash" ? "Efectivo" : "Tarjeta")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.ink)
                                Text("\(paymentStatusTitle(attempt.status)) · \(attempt.mode == "simulated" ? "simulado" : "manual") · \(attempt.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(paymentStatusColor(attempt.status)).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Text("$\(attempt.amountUsd)").font(.subheadline.monospacedDigit().weight(.bold)).foregroundStyle(DLCTheme.ink)
                        }
                        if let evidence = attempt.evidenceReference, !evidence.isEmpty {
                            Text("Referencia: \(evidence)").font(.caption2).foregroundStyle(DLCTheme.muted)
                        }
                        if (Decimal(string: attempt.refundedUsd, locale: Locale(identifier: "en_US_POSIX")) ?? 0) > 0 {
                            Text("Reembolsado: $\(attempt.refundedUsd)").font(.caption).foregroundStyle(DLCTheme.orange)
                        }
                        if attempt.status == "unknown" && canResolvePayments {
                            Button("Conciliar resultado del terminal") { attemptToResolve = attempt }
                                .font(.caption.weight(.semibold)).buttonStyle(.bordered).tint(DLCTheme.ink)
                                .disabled(!vm.canStartCommand)
                        }
                    }
                    .padding(11)
                    .background(attempt.status == "unknown" ? DLCTheme.yellowBG : DLCTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(DLCTheme.border, lineWidth: 1))
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            } else if canCollectPayments {
                Text("Tu permiso permite registrar el cobro, pero no consultar el historial de pagos.")
                    .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
            }

            if canCollectPayments && hasBalance && canReadCash && !vm.openSessions.isEmpty {
                Button { showCollection = true } label: {
                    Label("Registrar pago parcial o total", systemImage: "creditcard.and.123")
                        .frame(maxWidth: .infinity, alignment: .leading).font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent).tint(DLCTheme.forest)
                .disabled(!vm.canStartCommand || vm.isLoading)
            }

            if !vm.pending.isEmpty {
                ForEach(vm.pending) { draft in
                    VStack(alignment: .leading, spacing: 7) {
                        Label("El resultado del cobro no quedó confirmado en este dispositivo.", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.yellow)
                        Button("Consultar/reintentar con el mismo comando") {
                            Task {
                                if await vm.retry(draft) { await onPaymentChanged() }
                            }
                        }
                        .font(.caption.weight(.semibold)).buttonStyle(.bordered).tint(DLCTheme.ink).disabled(vm.isPosting)
                    }
                    .padding(10).background(DLCTheme.yellowBG, in: RoundedRectangle(cornerRadius: 13))
                }
            }
            if !vm.recoveryError.isEmpty { Label(vm.recoveryError, systemImage: "lock.fill").font(.caption).foregroundStyle(DLCTheme.red) }
            if !vm.sessionError.isEmpty { Label(vm.sessionError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(DLCTheme.red) }
            if !vm.errorMessage.isEmpty { Label(vm.errorMessage, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true) }
            if !vm.notice.isEmpty { Label(vm.notice, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(DLCTheme.green).fixedSize(horizontal: false, vertical: true) }
        }
        .onAppear { vm.refreshPending(); Task { await vm.load() } }
        .onChange(of: sale.outstandingUsd) { _, newValue in vm.updateSaleState(status: sale.status, outstanding: newValue) }
        .onChange(of: sale.status) { _, newValue in vm.updateSaleState(status: newValue, outstanding: sale.outstandingUsd) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: vm.attempts.count)
        .sheet(isPresented: $showCollection) {
            RemotePaymentCollectionSheet(vm: vm, onPaymentChanged: onPaymentChanged)
        }
        .sheet(item: $attemptToResolve) { attempt in
            RemotePaymentResolutionSheet(vm: vm, attempt: attempt, onPaymentChanged: onPaymentChanged)
        }
    }
}

private enum RemoteRefundSheet: Identifiable {
    case request(RemotePaymentAttempt)
    case decide(RemoteRefundRequest)
    case execute(RemoteRefundRequest)

    var id: String {
        switch self {
        case .request(let attempt): "request-\(attempt.id.uuidString)"
        case .decide(let request): "decide-\(request.id.uuidString)"
        case .execute(let request): "execute-\(request.id.uuidString)"
        }
    }
}

@MainActor
private struct RemoteSaleRefundPanel: View {
    @StateObject private var vm: RemoteRefundViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let canReadCash: Bool
    let canRequest: Bool
    let canDecide: Bool
    let canExecute: Bool
    let onRefundChanged: () async -> Void
    @State private var activeSheet: RemoteRefundSheet?

    init(client: RemoteAPIClient, store: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID, saleID: UUID,
         canReadCash: Bool, canRequest: Bool, canDecide: Bool, canExecute: Bool,
         onRefundChanged: @escaping () async -> Void) {
        _vm = StateObject(wrappedValue: RemoteRefundViewModel(
            client: client, store: store, scope: scope, branchID: branchID, saleID: saleID, canReadCash: canReadCash
        ))
        self.canReadCash = canReadCash
        self.canRequest = canRequest
        self.canDecide = canDecide
        self.canExecute = canExecute
        self.onRefundChanged = onRefundChanged
    }

    private var refundableAttempts: [RemotePaymentAttempt] {
        vm.attempts.filter { attempt in
            guard attempt.status == "confirmed", attempt.paymentEventId != nil,
                  let paid = Decimal(string: attempt.amountUsd, locale: Locale(identifier: "en_US_POSIX")),
                  let refunded = Decimal(string: attempt.refundedUsd, locale: Locale(identifier: "en_US_POSIX")), paid > refunded else { return false }
            return !vm.requests.contains { request in
                request.paymentEventId == attempt.paymentEventId && ["pending", "approved"].contains(request.status) && request.refundId == nil
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Control de devoluciones").font(.headline).foregroundStyle(DLCTheme.ink)
                    Text("Solicitud, revisión independiente y salida de caja")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
                Spacer()
                Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Actualizar devoluciones").disabled(vm.isLoading || vm.isPosting)
            }

            if vm.isLoading && vm.requests.isEmpty { ProgressView("Consultando devoluciones…") }

            ForEach(vm.requests) { request in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Solicitud por $\(request.amountUsd)")
                                .font(.subheadline.monospacedDigit().weight(.bold)).foregroundStyle(DLCTheme.ink)
                            Text("\(refundRequestStatusTitle(request)) · \(request.method == "cash" ? "efectivo" : "tarjeta")")
                                .font(.caption.weight(.medium)).foregroundStyle(refundRequestStatusColor(request))
                        }
                        Spacer()
                        Image(systemName: refundRequestSymbol(request))
                            .foregroundStyle(refundRequestStatusColor(request)).font(.title3)
                    }
                    Text(request.reason).font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                    if let decisionReason = request.decisionReason, !decisionReason.isEmpty {
                        Text("Resolución: \(decisionReason)").font(.caption2).foregroundStyle(DLCTheme.muted)
                    }
                    if request.status == "pending" && canDecide && request.requestedBy != vm.scope.userId {
                        Button("Revisar solicitud") { activeSheet = .decide(request) }
                            .font(.caption.weight(.semibold)).buttonStyle(.bordered).tint(DLCTheme.ink)
                            .disabled(!vm.canStartCommand)
                    }
                    if request.status == "pending" && request.requestedBy == vm.scope.userId {
                        Text("Esperando decisión de otra persona autorizada.").font(.caption2).foregroundStyle(DLCTheme.yellow)
                    }
                    if request.status == "approved" && request.refundId == nil && request.requestedBy == vm.scope.userId && canExecute {
                        if canReadCash && !vm.openSessions.isEmpty {
                            Button("Ejecutar devolución aprobada") { activeSheet = .execute(request) }
                                .font(.caption.weight(.semibold)).buttonStyle(.borderedProminent).tint(DLCTheme.orangeFill)
                                .disabled(!vm.canStartCommand)
                        } else {
                            Label("Necesitas una caja abierta para ejecutar la devolución.", systemImage: "lock.fill")
                                .font(.caption2).foregroundStyle(DLCTheme.muted)
                        }
                    }
                }
                .padding(11)
                .background(refundRequestStatusColor(request).opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(refundRequestStatusColor(request).opacity(0.22), lineWidth: 1))
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }

            if canRequest {
                if refundableAttempts.isEmpty && !vm.isLoading {
                    Text("No hay pagos confirmados con saldo disponible para una nueva solicitud.")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
                ForEach(refundableAttempts) { attempt in
                    Button { activeSheet = .request(attempt) } label: {
                        Label("Solicitar devolución de \(attempt.method == "cash" ? "efectivo" : "tarjeta") · saldo $\(refundableBalance(attempt))", systemImage: "arrow.uturn.backward.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered).tint(DLCTheme.orange).disabled(!vm.canStartCommand)
                }
            }

            ForEach(vm.pending) { draft in
                VStack(alignment: .leading, spacing: 7) {
                    Label("Acción de devolución por confirmar", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.yellow)
                    Button("Consultar / reintentar") {
                        Task { if await vm.retry(draft) { await onRefundChanged() } }
                    }
                    .font(.caption.weight(.semibold)).buttonStyle(.bordered).tint(DLCTheme.ink).disabled(vm.isPosting)
                }
                .padding(10).background(DLCTheme.yellowBG, in: RoundedRectangle(cornerRadius: 13))
            }

            if !vm.recoveryError.isEmpty { Label(vm.recoveryError, systemImage: "lock.fill").font(.caption).foregroundStyle(DLCTheme.red) }
            if !vm.errorMessage.isEmpty { Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true) }
            if !vm.notice.isEmpty { Label(vm.notice, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(DLCTheme.green).fixedSize(horizontal: false, vertical: true) }
        }
        .onAppear { vm.refreshPending(); Task { await vm.load() } }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: vm.requests.count)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .request(let attempt):
                RemoteRefundRequestSheet(vm: vm, attempt: attempt, onChanged: onRefundChanged)
            case .decide(let request):
                RemoteRefundDecisionSheet(vm: vm, request: request, onChanged: onRefundChanged)
            case .execute(let request):
                RemoteRefundExecutionSheet(vm: vm, request: request, onChanged: onRefundChanged)
            }
        }
    }

    private func refundableBalance(_ attempt: RemotePaymentAttempt) -> String {
        let paid = Decimal(string: attempt.amountUsd, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        let refunded = Decimal(string: attempt.refundedUsd, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        return NSDecimalNumber(decimal: paid - refunded).stringValue
    }
}

@MainActor
private struct RemoteRefundRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemoteRefundViewModel
    let attempt: RemotePaymentAttempt
    let onChanged: () async -> Void
    @State private var amount = ""
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Pago confirmado") {
                    LabeledContent("Medio", value: attempt.method == "cash" ? "Efectivo" : "Tarjeta")
                    LabeledContent("Pagado", value: "$\(attempt.amountUsd)")
                    LabeledContent("Ya reembolsado", value: "$\(attempt.refundedUsd)")
                    TextField("Importe a devolver (USD)", text: $amount).keyboardType(.decimalPad)
                }
                Section("Motivo") {
                    TextEditor(text: $reason).frame(minHeight: 100)
                    Text("El importe y el motivo quedarán ligados a la aprobación.").font(.caption).foregroundStyle(DLCTheme.muted)
                }
                if !vm.errorMessage.isEmpty { Section { Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(DLCTheme.red) } }
                Section {
                    Button("Enviar a revisión") {
                        Task { if await vm.requestRefund(attempt: attempt, amount: amount, reason: reason) { await onChanged(); dismiss() } }
                    }
                    .frame(maxWidth: .infinity).buttonStyle(.borderedProminent).tint(DLCTheme.forest).disabled(vm.isPosting)
                }
            }
            .navigationTitle("Solicitar devolución").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(vm.isPosting) } }
            .interactiveDismissDisabled(vm.isPosting)
        }
    }
}

@MainActor
private struct RemoteRefundDecisionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemoteRefundViewModel
    let request: RemoteRefundRequest
    let onChanged: () async -> Void
    @State private var decision = "approved"
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Solicitud") {
                    LabeledContent("Importe", value: "$\(request.amountUsd)")
                    Text(request.reason).font(.callout)
                }
                Section("Decisión independiente") {
                    Picker("Resultado", selection: $decision) {
                        Text("Aprobar").tag("approved")
                        Text("Rechazar").tag("rejected")
                    }.pickerStyle(.segmented)
                    TextEditor(text: $reason).frame(minHeight: 100).accessibilityLabel("Motivo de la decisión")
                    Text("La decisión se audita y solo quien solicitó podrá ejecutar una aprobación.").font(.caption).foregroundStyle(DLCTheme.muted)
                }
                if !vm.errorMessage.isEmpty { Section { Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(DLCTheme.red) } }
                Section {
                    Button(decision == "approved" ? "Aprobar solicitud" : "Rechazar solicitud") {
                        Task { if await vm.decide(request, decision: decision, reason: reason) { await onChanged(); dismiss() } }
                    }
                    .frame(maxWidth: .infinity).buttonStyle(.borderedProminent)
                    .tint(decision == "approved" ? DLCTheme.forest : DLCTheme.redFill).disabled(vm.isPosting)
                }
            }
            .navigationTitle("Revisar devolución").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(vm.isPosting) } }
            .interactiveDismissDisabled(vm.isPosting)
        }
    }
}

@MainActor
private struct RemoteRefundExecutionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemoteRefundViewModel
    let request: RemoteRefundRequest
    let onChanged: () async -> Void
    @State private var evidence = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Aprobación") {
                    LabeledContent("Importe", value: "$\(request.amountUsd)")
                    Text(request.reason).font(.callout)
                }
                Section("Salida") {
                    Picker("Turno de caja", selection: $vm.selectedCashSessionID) {
                        ForEach(vm.openSessions) { register in Text("Caja \(register.code)").tag(register.openSessionId) }
                    }
                    if request.method == "card" {
                        TextField("Referencia del terminal", text: $evidence).autocorrectionDisabled()
                        Text("No ingreses PAN completo, CVV ni credenciales.").font(.caption).foregroundStyle(DLCTheme.muted)
                    } else {
                        TextField("Referencia opcional", text: $evidence).autocorrectionDisabled()
                    }
                    Text("La devolución financiera no reincorpora combustible ni productos al inventario.").font(.caption).foregroundStyle(DLCTheme.muted)
                }
                if !vm.errorMessage.isEmpty { Section { Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(DLCTheme.red) } }
                Section {
                    Button("Registrar devolución") {
                        Task { if await vm.executeRefund(request, evidence: evidence) { await onChanged(); dismiss() } }
                    }
                    .frame(maxWidth: .infinity).buttonStyle(.borderedProminent).tint(DLCTheme.orangeFill).disabled(vm.isPosting || vm.openSessions.isEmpty)
                }
            }
            .navigationTitle("Ejecutar devolución").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(vm.isPosting) } }
            .interactiveDismissDisabled(vm.isPosting)
        }
    }
}

@MainActor
private struct RemotePaymentCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemotePaymentViewModel
    let onPaymentChanged: () async -> Void
    @State private var method = "cash"
    @State private var outcome = "confirmed"
    @State private var amount = ""
    @State private var evidence = ""
    @State private var validation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Importe y medio") {
                    LabeledContent("Saldo pendiente", value: "$\(vm.outstandingUsd ?? "—")")
                    TextField("Importe del pago (USD)", text: $amount).keyboardType(.decimalPad)
                    Picker("Medio de pago", selection: $method) {
                        Text("Efectivo").tag("cash")
                        Text("Tarjeta").tag("card")
                    }.pickerStyle(.segmented)
                    if method == "card" {
                        Picker("Resultado del terminal", selection: $outcome) {
                            Text("Aprobado").tag("confirmed")
                            Text("Rechazado").tag("declined")
                            Text("Sin respuesta").tag("unknown")
                        }.pickerStyle(.menu)
                        if outcome != "unknown" {
                            TextField("Referencia del terminal (sin número de tarjeta)", text: $evidence)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        }
                    }
                    Text(method == "cash"
                         ? "El efectivo confirmado se suma automáticamente a la caja seleccionada."
                         : "La app no procesa tarjetas. Registra el resultado observado en el terminal y conserva solo su referencia documental.")
                        .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    Button(method == "cash" ? "Confirmar cobro en efectivo" : "Registrar intento de tarjeta") {
                        Task {
                            let result = await vm.collect(method: method, amount: amount, outcome: method == "cash" ? "confirmed" : outcome, evidence: evidence)
                            if result { await onPaymentChanged(); dismiss() }
                            else { validation = vm.errorMessage }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!vm.canStartCommand || vm.isPosting || vm.outstandingUsd == nil)
                    if vm.isPosting { ProgressView("Registrando intento…") }
                    if !validation.isEmpty { Text(validation).font(.footnote).foregroundStyle(DLCTheme.red) }
                    if !vm.pending.isEmpty { Text("La respuesta es incierta. Reintenta el mismo comando antes de crear otro cobro.").font(.footnote).foregroundStyle(DLCTheme.yellow) }
                }
            }
            .scrollContentBackground(.hidden).dlcScreen().navigationTitle("Registrar pago")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() }.disabled(vm.isPosting) } }
            .onAppear { amount = vm.outstandingUsd ?? "" }
            .interactiveDismissDisabled(vm.isPosting)
        }.tint(DLCTheme.orange)
    }
}

@MainActor
private struct RemotePaymentResolutionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemotePaymentViewModel
    let attempt: RemotePaymentAttempt
    let onPaymentChanged: () async -> Void
    @State private var outcome = "confirmed"
    @State private var evidence = ""
    @State private var validation = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Intento de tarjeta · $\(attempt.amountUsd)") {
                    Text("El pago quedó sin respuesta. Confirma en el terminal antes de registrar una decisión.")
                        .font(.subheadline).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                    Picker("Resultado verificado", selection: $outcome) {
                        Text("Aprobado").tag("confirmed")
                        Text("Rechazado").tag("declined")
                    }.pickerStyle(.segmented)
                    TextField("Referencia consultada en terminal", text: $evidence)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Text("No guardes PAN, CVV ni credenciales del terminal.").font(.caption).foregroundStyle(DLCTheme.muted)
                }
                Section {
                    Button("Guardar conciliación") {
                        Task {
                            if await vm.resolve(attemptID: attempt.id, outcome: outcome, evidence: evidence) {
                                await onPaymentChanged()
                                dismiss()
                            } else { validation = vm.errorMessage }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!vm.canStartCommand || vm.isPosting)
                    if vm.isPosting { ProgressView("Guardando conciliación…") }
                    if !validation.isEmpty { Text(validation).font(.footnote).foregroundStyle(DLCTheme.red) }
                }
            }
            .scrollContentBackground(.hidden).dlcScreen().navigationTitle("Resolver pago")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() }.disabled(vm.isPosting) } }
            .interactiveDismissDisabled(vm.isPosting)
        }.tint(DLCTheme.orange)
    }
}

private func paymentStatusTitle(_ status: String) -> String {
    switch status {
    case "confirmed": "Confirmado"
    case "declined": "Rechazado"
    case "unknown": "Resultado sin confirmar · reservado"
    default: "Pendiente"
    }
}

private func paymentStatusColor(_ status: String) -> Color {
    switch status {
    case "confirmed": DLCTheme.green
    case "unknown": DLCTheme.yellow
    case "declined": DLCTheme.red
    default: DLCTheme.muted
    }
}

private func fuelSaleStatusTitle(_ status: String) -> String {
    switch status {
    case "paid": "Pagado"
    case "on_credit": "A crédito"
    case "pending_collection": "Pendiente de cobro"
    default: status.capitalized
    }
}

private func fuelCombinedReceiptStatusTitle(_ status: String) -> String {
    switch status {
    case "paid": return "Cobrado por componente"
    case "partially_collected": return "Cobro parcial"
    case "awaiting_confirmation": return "Pendiente de confirmación"
    default: return "Pendiente de cobro"
    }
}

struct RemoteFuelTaxPoliciesView: View {
    let repository: RemotePumpRepository
    let branchID: UUID
    let currentUserID: UUID
    let canPropose: Bool
    let canApprove: Bool
    @State private var page: RemoteFuelTaxPolicyPage?
    @State private var errorMessage = ""
    @State private var isWorking = false
    @State private var showProposal = false
    @State private var query = ""
    @State private var approvalCommands: [UUID: UUID] = [:]
    var body: some View {
        List {
            if let page {
                if page.data.isEmpty { ContentUnavailableView("Sin políticas fiscales", systemImage: "doc.text.magnifyingglass") }
                ForEach(page.data.filter { query.isEmpty || $0.fuelName.localizedCaseInsensitiveContains(query) || $0.sourceReference.localizedCaseInsensitiveContains(query) }) { policy in
                    Section(policy.fuelName) {
                        LabeledContent("Estado", value: statusName(policy.status))
                        LabeledContent("Tratamiento", value: modeName(policy.mode))
                        LabeledContent("Vigencia", value: policy.effectiveAt.formatted(date: .abbreviated, time: .shortened))
                        if let version = policy.version { LabeledContent("Versión", value: "\(version)") }
                        ForEach(policy.rules) { rule in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.label).font(.subheadline.bold())
                                Text(ruleDescription(rule)).font(.caption).foregroundStyle(DLCTheme.muted)
                            }
                        }
                        LabeledContent("Fuente", value: policy.sourceReference)
                        Text(policy.reason).font(.footnote).foregroundStyle(DLCTheme.muted)
                        if canApprove && policy.status == "awaiting_approval" && policy.proposedBy != currentUserID {
                            Button("Aprobar política") { Task { await approve(policy.id) } }
                                .disabled(isWorking || policy.effectiveAt <= Date())
                        }
                        if canApprove && policy.status == "awaiting_approval" && policy.proposedBy == currentUserID {
                            Text("Pendiente de aprobación por otra persona").font(.caption).foregroundStyle(DLCTheme.orange)
                        }
                    }
                }
            } else if isWorking { ProgressView("Cargando políticas…") }
            if !errorMessage.isEmpty { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(DLCTheme.red) }
        }
        .navigationTitle("Políticas fiscales")
        .searchable(text: $query, prompt: "Combustible o fuente")
        .toolbar {
            if canPropose {
                ToolbarItem(placement: .primaryAction) {
                    Button { showProposal = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Proponer política fiscal")
                        .disabled(isWorking || page?.products.isEmpty != false)
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showProposal) {
            RemoteFuelTaxProposalView(repository: repository, branchID: branchID, products: page?.products ?? []) {
                showProposal = false
                Task { await load() }
            }
        }
    }
    private func load() async {
        guard !isWorking else { return }
        isWorking = true; defer { isWorking = false }
        do { page = try await repository.fuelTaxPolicies(branchId: branchID); errorMessage = "" }
        catch { errorMessage = error.localizedDescription }
    }
    private func approve(_ id: UUID) async {
        guard !isWorking else { return }
        isWorking = true
        let command = approvalCommands[id] ?? UUID()
        approvalCommands[id] = command
        do {
            _ = try await repository.approveFuelTax(branchId: branchID, proposalId: id, commandId: command)
            page = try await repository.fuelTaxPolicies(branchId: branchID)
            approvalCommands.removeValue(forKey: id)
            errorMessage = ""
        } catch { errorMessage = error.localizedDescription }
        isWorking = false
    }
    private func statusName(_ value: String) -> String {
        switch value { case "awaiting_approval": return "Pendiente de aprobación"; case "scheduled": return "Programada"; case "superseded": return "Histórica"; default: return "Vigente" }
    }
    private func modeName(_ value: String) -> String {
        switch value { case "included": return "Impuestos incluidos"; case "exempt": return "Exención documentada"; default: return "Desglose pendiente" }
    }
    private func ruleDescription(_ rule: RemoteFuelTaxRule) -> String {
        if rule.kind == "percentage", let rate = Decimal(string: rule.rate) {
            let percentage = NSDecimalNumber(decimal: rate * 100).stringValue
            return "\(percentage) % · \(rule.base == "net" ? "base neta" : "base neta más cargos fijos")"
        }
        return "$\(rule.rate) / \(rule.kind == "fixed_per_liter" ? "litro" : "galón US")"
    }
}

private struct RemoteFuelTaxProposalView: View {
    struct RuleDraft: Identifiable {
        let id = UUID()
        var code = ""
        var label = ""
        var kind = "percentage"
        var base = "net"
        var rate = ""
    }
    @Environment(\.dismiss) private var dismiss
    let repository: RemotePumpRepository
    let branchID: UUID
    let products: [RemoteFuelTaxPolicyPage.Product]
    let onCreated: () -> Void
    @State private var productID: UUID?
    @State private var mode = "included"
    @State private var rules = [RuleDraft()]
    @State private var source = ""
    @State private var reason = ""
    @State private var effectiveAt = Date().addingTimeInterval(3600)
    @State private var isWorking = false
    @State private var pendingBody: RemoteFuelTaxProposalBody?
    @State private var errorMessage = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Aplicación") {
                    Picker("Combustible", selection: $productID) {
                        Text("Seleccionar").tag(Optional<UUID>.none)
                        ForEach(products) { product in Text(product.name).tag(Optional(product.id)) }
                    }
                    Picker("Tratamiento", selection: $mode) {
                        Text("Incluidos en el precio").tag("included")
                        Text("Exención documentada").tag("exempt")
                        Text("Desglose pendiente").tag("unconfigured")
                    }
                    DatePicker("Vigente desde", selection: $effectiveAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                }.disabled(isWorking || pendingBody != nil)
                if mode == "included" {
                    ForEach($rules) { $rule in
                        Section("Componente") {
                            TextField("Código", text: $rule.code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                            TextField("Nombre", text: $rule.label)
                            Picker("Tipo", selection: $rule.kind) {
                                Text("Porcentaje").tag("percentage")
                                Text("Importe por litro").tag("fixed_per_liter")
                                Text("Importe por galón US").tag("fixed_per_us_gallon")
                            }
                            if rule.kind == "percentage" {
                                Picker("Base", selection: $rule.base) {
                                    Text("Venta neta").tag("net")
                                    Text("Venta neta más cargos fijos").tag("net_plus_fixed")
                                }
                            }
                            TextField(rule.kind == "percentage" ? "Tasa (%)" : "Importe (USD)", text: $rule.rate).keyboardType(.decimalPad)
                            Button("Quitar componente", role: .destructive) { rules.removeAll { $0.id == rule.id } }.disabled(rules.count <= 1)
                        }.disabled(isWorking || pendingBody != nil)
                    }
                    if rules.count < 8 { Button("Agregar componente") { rules.append(RuleDraft()) }.disabled(isWorking || pendingBody != nil) }
                }
                Section("Respaldo") {
                    TextField("Referencia del documento", text: $source, axis: .vertical)
                    TextField("Motivo", text: $reason, axis: .vertical)
                }.disabled(isWorking || pendingBody != nil)
                Section {
                    Button(pendingBody == nil ? "Enviar a aprobación" : "Reintentar la misma propuesta") { Task { await submit() } }
                        .disabled(isWorking || productID == nil || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if isWorking { ProgressView() }
                    if !errorMessage.isEmpty { Text(errorMessage).foregroundStyle(DLCTheme.red).font(.footnote) }
                }
            }
            .navigationTitle("Proponer política")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() }.disabled(isWorking) } }
            .tint(DLCTheme.orange)
        }
    }
    private func submit() async {
        guard let productID, !isWorking else { return }
        isWorking = true; defer { isWorking = false }
        if pendingBody == nil {
            var components: [RemoteFuelTaxRule] = []
            if mode == "included" {
                for rule in rules {
                    guard let entered = Decimal(string: rule.rate.replacingOccurrences(of: ",", with: ".")), entered > 0,
                          !rule.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          !rule.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        errorMessage = "Completa código, nombre y tasa positiva de cada componente."; return
                    }
                    let rate = rule.kind == "percentage" ? entered / 100 : entered
                    components.append(RemoteFuelTaxRule(code: rule.code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines), label: rule.label.trimmingCharacters(in: .whitespacesAndNewlines), kind: rule.kind, base: rule.kind == "percentage" ? rule.base : "observed_volume", rate: NSDecimalNumber(decimal: rate).stringValue))
                }
            }
            pendingBody = RemoteFuelTaxProposalBody(commandId: UUID(), fuelProductId: productID, mode: mode, rules: components, sourceReference: source.trimmingCharacters(in: .whitespacesAndNewlines), reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), effectiveAt: effectiveAt)
        }
        guard let body = pendingBody else { return }
        do { _ = try await repository.proposeFuelTax(branchId: branchID, body: body); onCreated() }
        catch {
            errorMessage = error.localizedDescription
            if case RemoteAPIError.http(let status, _, _, _) = error, [400, 404, 409, 422].contains(status) {
                pendingBody = nil
            }
        }
    }
}
