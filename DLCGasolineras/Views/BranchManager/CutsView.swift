import SwiftUI

struct CutsView: View {
    @ObservedObject var vm: BranchManagerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Cortes de hoy").font(.largeTitle.weight(.bold))
                    Text("\(vm.branch.name) · dos cortes operativos por día")
                        .font(.subheadline).foregroundStyle(DLCTheme.muted)
                }

                ForEach(CutType.allCases) { type in
                    if let cut = vm.latestCut(for: type) {
                        NavigationLink(destination: CutFormView(cut: cut)) {
                            CutScheduleCard(cut: cut)
                        }
                        .buttonStyle(.plain)
                    }
                }

                NavigationLink(destination: PumpsOverviewView(vm: vm)) {
                    OperationsLinkRow(title: "Historial de cortes", subtitle: "Filtrar por periodo y turno; abrir detalle", symbol: "clock.arrow.circlepath")
                }

                Label("Registra recepción y pérdidas en litros; captura las lecturas acumuladas de las seis bombas en galones.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dlcCard(color: DLCTheme.orangeBG)
            }
            .padding(20)
        }
        .navigationTitle("Cortes")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .onAppear { vm.reload() }
    }
}

private struct CutScheduleCard: View {
    let cut: DailyCut

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: cut.isClosed ? "checkmark.circle.fill" : "fuelpump.fill")
                .font(.title2).foregroundStyle(cut.isClosed ? DLCTheme.green : DLCTheme.orange)
                .frame(width: 46, height: 46)
                .background(cut.isClosed ? DLCTheme.greenBG : DLCTheme.orangeBG)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(cut.type.rawValue).font(.headline).foregroundStyle(DLCTheme.forest)
                Text(cut.type.schedule).font(.caption).foregroundStyle(DLCTheme.muted)
                Text(cut.isClosed ? "Cerrado · \(Int(cut.totalSoldGallons.rounded()).formatted()) gal vendidos" : "\(cut.completedPumpCount) de 6 bombas registradas")
                    .font(.caption.weight(.semibold)).foregroundStyle(cut.isClosed ? DLCTheme.green : DLCTheme.orange)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(DLCTheme.muted)
        }
        .dlcCard()
        .accessibilityElement(children: .combine)
    }
}

struct RemoteCutsDirectoryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm: RemoteCutsDirectoryViewModel
    private let repository: RemoteCutRepository
    private let pumpRepository: RemotePumpRepository?
    private let branchID: UUID
    private let currentUserID: UUID
    private let timezoneIdentifier: String
    private let canCapture: Bool
    private let canMeasureMeters: Bool
    private let canSubmit: Bool
    private let canReviewOrClose: Bool

    init(
        repository: RemoteCutRepository,
        pumpRepository: RemotePumpRepository?,
        branchID: UUID,
        branchName: String,
        timezoneIdentifier: String,
        currentUserID: UUID,
        canRead: Bool,
        canCapture: Bool,
        canMeasureMeters: Bool,
        canSubmit: Bool,
        canReviewOrClose: Bool
    ) {
        self.repository = repository
        self.pumpRepository = pumpRepository
        self.branchID = branchID
        self.currentUserID = currentUserID
        self.timezoneIdentifier = timezoneIdentifier
        self.canCapture = canCapture
        self.canMeasureMeters = canMeasureMeters
        self.canSubmit = canSubmit
        self.canReviewOrClose = canReviewOrClose
        _vm = StateObject(wrappedValue: RemoteCutsDirectoryViewModel(
            repository: repository,
            branchID: branchID,
            timezoneIdentifier: timezoneIdentifier,
            canGenerate: canCapture
        ))
        self.branchName = branchName
        self.canRead = canRead
    }

    private let branchName: String
    private let canRead: Bool

    private var branchTimeZone: TimeZone {
        TimeZone(identifier: timezoneIdentifier) ?? TimeZone(identifier: "America/El_Salvador")!
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Cortes de operación")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(DLCTheme.forest)
                            Text(branchName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DLCTheme.muted)
                        }
                        Spacer()
                        Button { Task { await vm.load() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.headline)
                                .foregroundStyle(DLCTheme.forest)
                                .frame(width: 42, height: 42)
                                .background(DLCTheme.surface, in: Circle())
                                .overlay(Circle().stroke(DLCTheme.border, lineWidth: 1))
                        }
                        .accessibilityLabel("Actualizar cortes")
                    }
                    Text("Dos turnos por día · lecturas acumuladas en la unidad de cada medidor · inventario físico en litros")
                        .font(.footnote)
                        .foregroundStyle(DLCTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Fecha operativa", systemImage: "calendar")
                        .font(.caption.weight(.bold)).textCase(.uppercase)
                        .foregroundStyle(DLCTheme.muted)
                    DatePicker("Seleccionar fecha", selection: $vm.selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .environment(\.timeZone, branchTimeZone)
                        .environment(\.calendar, branchCalendar)
                        .onChange(of: vm.operationalDate) { _, _ in Task { await vm.load() } }
                }
                .dlcCard(color: DLCTheme.surface)

                if !canRead {
                    permissionNotice("Tu cuenta no tiene permiso para consultar cortes.")
                } else {
                    if !vm.errorMessage.isEmpty {
                        Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.medium)).foregroundStyle(DLCTheme.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .dlcCard(color: DLCTheme.redBG)
                    }
                    if vm.isLoading && vm.cuts.isEmpty {
                        ProgressView("Consultando cortes")
                            .frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if vm.cuts.isEmpty && vm.errorMessage.isEmpty {
                        emptyDayCard
                    } else if !vm.cuts.isEmpty {
                        if vm.cuts.count != 2 {
                            Label("El servidor devolvió \(vm.cuts.count) cortes para esta fecha; verifica la configuración del turno.", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote).foregroundStyle(DLCTheme.red)
                                .dlcCard(color: DLCTheme.redBG)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Turnos del día").font(.title3.weight(.bold)).foregroundStyle(DLCTheme.forest)
                                Spacer()
                                Text("\(vm.cuts.count) cortes")
                                    .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.muted)
                                    .contentTransition(.numericText())
                            }
                            ForEach(vm.cuts) { cut in
                                NavigationLink {
                                    RemoteCutDetailView(
                                        cut: cut,
                                        repository: repository,
                                        pumpRepository: pumpRepository,
                                        branchID: branchID,
                                        currentUserID: currentUserID,
                                    timezoneIdentifier: timezoneIdentifier,
                                        canCapture: canCapture,
                                        canMeasureMeters: canMeasureMeters,
                                        canSubmit: canSubmit,
                                        canReviewOrClose: canReviewOrClose
                                    )
                                    .onDisappear { Task { await vm.load() } }
                                } label: {
                                    RemoteCutScheduleCard(cut: cut, timezoneIdentifier: timezoneIdentifier)
                                }
                                .buttonStyle(.plain)
                                .scrollTransition(.animated(.spring(duration: 0.38))) { content, phase in
                                    reduceMotion ? content : content.opacity(phase.isIdentity ? 1 : 0.88)
                                        .scaleEffect(phase.isIdentity ? 1 : 0.975)
                                }
                            }
                        }
                    }
                }

                if let lastUpdated = vm.lastUpdated {
                    Label("Actualizado \(lastUpdated.formatted(date: .omitted, time: .shortened)) · hora de El Salvador", systemImage: "clock")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
            }
            .padding(20)
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: vm.cuts.map(\.id))
        }
        .navigationTitle("Cortes")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .task { if canRead { await vm.load() } }
    }

    private var emptyDayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.title2.weight(.semibold)).foregroundStyle(DLCTheme.orange)
                    .frame(width: 50, height: 50)
                    .background(DLCTheme.orangeBG, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aún no hay cortes generados")
                        .font(.headline).foregroundStyle(DLCTheme.forest)
                    Text("Al generarlos, el servidor crea Matutino y Vespertino con sus horarios configurados.")
                        .font(.subheadline).foregroundStyle(DLCTheme.muted)
                }
            }
            if canCapture {
                Button {
                    Task { await vm.generatePair() }
                } label: {
                    HStack {
                        if vm.isGenerating { ProgressView().tint(.white) }
                        else { Image(systemName: "plus.circle.fill") }
                        Text(vm.isGenerating ? "Generando turnos…" : "Generar los dos cortes")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(LinearGradient(colors: [DLCTheme.orange, Color(red: 0.72, green: 0.22, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
                }
                .disabled(vm.isGenerating || vm.isFutureDate)
                .opacity(vm.isFutureDate ? 0.55 : 1)
                if vm.isFutureDate {
                    Text("Los cortes solo se generan para una fecha actual o anterior.")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
            } else {
                Text("Se requiere permiso de captura para generar la agenda de cortes.")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            }
        }
        .dlcCard()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var branchCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = branchTimeZone
        return calendar
    }

    private func permissionNotice(_ text: String) -> some View {
        Label(text, systemImage: "lock.fill")
            .font(.footnote).foregroundStyle(DLCTheme.red)
            .fixedSize(horizontal: false, vertical: true)
            .dlcCard(color: DLCTheme.redBG)
    }
}

private struct RemoteCutScheduleCard: View {
    let cut: RemoteOperationalCut
    let timezoneIdentifier: String

    private var fraction: Double {
        switch cut.status {
        case "closed": 1
        case "prepared": 0.82
        case "inReview": 0.7
        case "open": 0.38
        default: 0.08
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            CutProgressOrb(fraction: fraction, status: cut.status, size: 54)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(cut.title).font(.headline).foregroundStyle(DLCTheme.forest)
                    Text(statusLabel(cut.status))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(statusColor(cut.status))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(statusBackground(cut.status), in: Capsule())
                }
                Text("\(cutTime(cut.startsAt, timezoneIdentifier: timezoneIdentifier)) – \(cutTime(cut.endsAt, timezoneIdentifier: timezoneIdentifier))")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
                if cut.status == "closed" {
                    Text("Cerrado \(cut.closedAt.map { cutTime($0, timezoneIdentifier: timezoneIdentifier) } ?? "") · \(cut.closedByName ?? "responsable registrado")")
                        .font(.caption2.weight(.semibold)).foregroundStyle(DLCTheme.green)
                } else if cut.status == "inReview" {
                    Text("Conciliación pendiente de revisión independiente")
                        .font(.caption2.weight(.semibold)).foregroundStyle(DLCTheme.yellow)
                } else {
                    Text(cut.status == "scheduled" ? "Pendiente de apertura" : "Versión de corte \(cut.version)")
                        .font(.caption2.weight(.semibold)).foregroundStyle(DLCTheme.muted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold)).foregroundStyle(DLCTheme.muted)
        }
        .padding(15)
        .background(
            LinearGradient(colors: [DLCTheme.surface, Color.white.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(DLCTheme.border, lineWidth: 1))
        .shadow(color: DLCTheme.forest.opacity(0.055), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
    }
}

private struct CutProgressOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fraction: Double
    let status: String
    var size: CGFloat = 48

    private var tint: Color { statusColor(status) }

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.14), lineWidth: 5)
            Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(AngularGradient(colors: [DLCTheme.orange, tint], center: .center), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.72), value: fraction)
            Image(systemName: status == "closed" ? "checkmark" : "fuelpump.fill")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Avance del corte")
    }
}

private struct RemoteCutDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm: RemoteCutWorkflowViewModel
    @State private var reviewReason = ""
    private let timezoneIdentifier: String

    init(
        cut: RemoteOperationalCut,
        repository: RemoteCutRepository,
        pumpRepository: RemotePumpRepository?,
        branchID: UUID,
        currentUserID: UUID,
        timezoneIdentifier: String,
        canCapture: Bool,
        canMeasureMeters: Bool,
        canSubmit: Bool,
        canReviewOrClose: Bool
    ) {
        self.timezoneIdentifier = timezoneIdentifier
        _vm = StateObject(wrappedValue: RemoteCutWorkflowViewModel(
            cut: cut,
            repository: repository,
            pumpRepository: pumpRepository,
            branchID: branchID,
            currentUserID: currentUserID,
            canCapture: canCapture,
            canMeasureMeters: canMeasureMeters,
            canSubmit: canSubmit,
            canReviewOrClose: canReviewOrClose
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                if !vm.errorMessage.isEmpty {
                    Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium)).foregroundStyle(DLCTheme.red)
                        .fixedSize(horizontal: false, vertical: true).dlcCard(color: DLCTheme.redBG)
                }
                if !vm.statusMessage.isEmpty {
                    Label(vm.statusMessage, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium)).foregroundStyle(DLCTheme.green)
                        .fixedSize(horizontal: false, vertical: true).dlcCard(color: DLCTheme.greenBG)
                }
                if vm.isLoading && vm.assets == nil && vm.cut.status != "scheduled" {
                    ProgressView("Cargando equipos y conciliación")
                        .frame(maxWidth: .infinity).padding(.vertical, 22)
                }
                if vm.cut.status == "scheduled" {
                    scheduledSection
                } else if let assets = vm.assets {
                    if let progress = vm.progress { progressSummary(progress) }
                    if vm.cut.status == "open" {
                        meterSection(assets)
                        tankSection(assets)
                        prepareSection
                    }
                    if let reconciliation = vm.reconciliation {
                        reconciliationSection(reconciliation)
                    }
                    reviewAndCloseSection
                }
                if let lastUpdated = vm.lastUpdated {
                    Label("Información sincronizada \(lastUpdated.formatted(date: .abbreviated, time: .shortened))", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
            }
            .padding(20)
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.86), value: vm.cut.status)
        }
        .navigationTitle(vm.cut.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Actualizar estado del corte")
            }
        }
        .dlcScreen()
        .task { await vm.load() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(vm.cut.title).font(.title.weight(.bold)).foregroundStyle(.white)
                    Text(vm.cut.operationalDate)
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                CutProgressOrb(fraction: heroFraction, status: vm.cut.status, size: 60)
                    .colorMultiply(.white)
            }
            HStack(spacing: 8) {
                Label(cutTime(vm.cut.startsAt, timezoneIdentifier: timezoneIdentifier), systemImage: "sunrise.fill")
                Text("→")
                Label(cutTime(vm.cut.endsAt, timezoneIdentifier: timezoneIdentifier), systemImage: "sunset.fill")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
            HStack {
                Text(statusLabel(vm.cut.status).uppercased())
                    .font(.caption2.weight(.heavy)).tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(.white.opacity(0.16), in: Capsule())
                Spacer()
                Text("v\(vm.cut.version)").font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.68))
            }
        }
        .padding(19)
        .background(LinearGradient(colors: [DLCTheme.forest, Color(red: 0.08, green: 0.31, blue: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .bottomTrailing) {
            Circle().fill(DLCTheme.orange.opacity(0.18)).frame(width: 104, height: 104).blur(radius: 1).offset(x: 28, y: 28).clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: DLCTheme.forest.opacity(0.18), radius: 18, y: 9)
        .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
    }

    private var heroFraction: Double {
        switch vm.cut.status {
        case "closed": 1
        case "prepared": 0.82
        case "inReview": 0.7
        case "open": 0.36
        default: 0.08
        }
    }

    private var scheduledSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Antes de iniciar", systemImage: "list.bullet.clipboard")
                .font(.headline).foregroundStyle(DLCTheme.forest)
            Text("Al abrir, se fija la configuración de bombas, mangueras y tanques para este corte. El sistema exige continuidad con el turno anterior.")
                .font(.subheadline).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await vm.open() }
            } label: {
                actionLabel(vm.isWorking ? "Abriendo turno…" : "Abrir corte", icon: "arrow.up.forward.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(!vm.canCapture || vm.isWorking || Date() < vm.cut.startsAt)
            .opacity((!vm.canCapture || Date() < vm.cut.startsAt) ? 0.55 : 1)
            if Date() < vm.cut.startsAt {
                Text("El turno se puede abrir a las \(cutTime(vm.cut.startsAt, timezoneIdentifier: timezoneIdentifier)).")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            }
        }
        .dlcCard(color: DLCTheme.surface)
    }

    private func progressSummary(_ progress: RemoteCutProgress) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avance de lecturas").font(.headline).foregroundStyle(DLCTheme.forest)
                    Text("Boquillas esperadas del snapshot de este turno")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
                Spacer()
                Text("\(vm.capturedNozzles)/\(vm.expectedNozzles.count)")
                    .font(.title3.monospacedDigit().weight(.bold)).foregroundStyle(DLCTheme.forest)
                    .contentTransition(.numericText())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(DLCTheme.border.opacity(0.48))
                    Capsule().fill(LinearGradient(colors: [DLCTheme.orange, DLCTheme.green], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * progressFraction)
                        .animation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.76), value: progressFraction)
                }
            }
            .frame(height: 9)
            HStack(spacing: 8) {
                ForEach(progress.products) { product in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.productName).font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.forest)
                        Text("\(product.captured)/\(product.expected) · \(product.meterLiters) L")
                            .font(.caption2.monospacedDigit()).foregroundStyle(DLCTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(DLCTheme.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if progress.provisional {
                Label("Los valores son provisionales hasta cerrar y consolidar el corte.", systemImage: "info.circle")
                    .font(.caption2).foregroundStyle(DLCTheme.muted)
            }
        }
        .dlcCard()
    }

    private var progressFraction: Double {
        guard vm.expectedNozzles.count > 0 else { return 0 }
        return Double(vm.capturedNozzles) / Double(vm.expectedNozzles.count)
    }

    private func meterSection(_ assets: RemoteCutAssets) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Lecturas de bombas", detail: "Cada totalizador conserva su unidad configurada.", symbol: "fuelpump.fill", tint: DLCTheme.orange)
            ForEach(assets.dispensers) { dispenser in
                let nozzles = assets.nozzles.filter { $0.dispenserId == dispenser.id }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Bomba \(dispenser.code)", systemImage: "fuelpump")
                            .font(.subheadline.weight(.bold)).foregroundStyle(DLCTheme.forest)
                        Spacer()
                        Text(dispenser.physicalStatus == "active" ? "Activa" : "No activa")
                            .font(.caption2.weight(.semibold)).foregroundStyle(dispenser.physicalStatus == "active" ? DLCTheme.green : DLCTheme.muted)
                    }
                    ForEach(nozzles) { nozzle in
                        RemoteCutNozzleEntry(nozzle: nozzle, canCapture: vm.canCapture && vm.canMeasureMeters && vm.cut.status == "open", canLinkLatest: vm.canLinkLatestReading(nozzle), isWorking: vm.isWorking) { value in
                            await vm.captureMeter(nozzle: nozzle, value: value)
                        } onLink: {
                            await vm.linkLatestReading(for: nozzle)
                        }
                    }
                }
                .dlcCard(color: DLCTheme.surface)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if assets.nozzles.isEmpty {
                Text("No hay mangueras incluidas en la configuración congelada del corte.")
                    .font(.subheadline).foregroundStyle(DLCTheme.muted).dlcCard(color: DLCTheme.yellowBG)
            }
        }
    }

    private func tankSection(_ assets: RemoteCutAssets) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Medición física de tanques", detail: "Volumen y agua se capturan en litros; temperatura es opcional.", symbol: "drop.fill", tint: DLCTheme.blue)
            ForEach(assets.tanks) { tank in
                RemoteCutTankEntry(tank: tank, canEdit: vm.canCapture && vm.cut.status == "open", isWorking: vm.isWorking) { measured, water, temperature in
                    await vm.measureTank(tank: tank, measured: measured, water: water, temperature: temperature)
                }
                .id("\(tank.id)-\(tank.measuredLiters ?? "sin-medicion")-\(tank.waterLiters ?? "sin-agua")")
            }
            if assets.tanks.isEmpty {
                Text("Esta sucursal no devolvió tanques activos para medir.")
                    .font(.subheadline).foregroundStyle(DLCTheme.red).dlcCard(color: DLCTheme.redBG)
            }
        }
    }

    private var prepareSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeading("Conciliar y preparar", detail: "Se validan lecturas, ventas, movimientos, inventario y despachos pendientes.", symbol: "checkmark.seal.fill", tint: DLCTheme.green)
            HStack(spacing: 9) {
                evidencePill("\(vm.capturedNozzles)/\(vm.expectedNozzles.count) mangueras", done: vm.capturedNozzles == vm.expectedNozzles.count && vm.expectedNozzles.count > 0)
                evidencePill("\(vm.tankMeasurementCount)/\(vm.assets?.tanks.count ?? 0) tanques", done: vm.tankMeasurementCount == (vm.assets?.tanks.count ?? -1))
            }
            Button { Task { await vm.prepare() } } label: {
                actionLabel(vm.isWorking ? "Calculando conciliación…" : "Preparar conciliación", icon: "equal.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(!vm.canSubmit || !vm.allEvidenceRecorded || vm.isWorking)
            .opacity((!vm.canSubmit || !vm.allEvidenceRecorded) ? 0.5 : 1)
            if !vm.canSubmit {
                Text("Tu perfil puede registrar evidencia, pero no preparar el cierre.")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            } else if !vm.allEvidenceRecorded {
                Text("Completa las mangueras esperadas y mide todos los tanques activos antes de preparar.")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            }
        }
        .dlcCard(color: DLCTheme.orangeBG)
    }

    private func reconciliationSection(_ reconciliation: RemoteCutReconciliation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Conciliación", detail: "Esperado vs. medido · valores del servidor", symbol: "chart.bar.xaxis", tint: DLCTheme.forest)
            if reconciliation.reviewRequired {
                Label("Hay diferencias fuera de tolerancia; hace falta una revisión independiente.", systemImage: "exclamationmark.shield.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.yellow)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(DLCTheme.yellowBG, in: RoundedRectangle(cornerRadius: 14))
            } else {
                Label("Dentro de las tolerancias configuradas", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.green)
            }
            ForEach(reconciliation.products) { product in
                VStack(alignment: .leading, spacing: 8) {
                    Text(product.productName ?? "Combustible").font(.subheadline.weight(.bold)).foregroundStyle(DLCTheme.forest)
                    comparisonRow("Medido por bombas", value: product.meterLiters?.value, unit: "L")
                    comparisonRow("Despachos confirmados", value: product.soldLiters?.value, unit: "L")
                    comparisonRow("Variación", value: product.varianceLiters?.value, unit: "L", emphasize: true)
                    comparisonRow("Ventas registradas", value: product.salesUsd?.value, unit: "USD")
                    comparisonRow("Recepciones", value: product.receiptsLiters?.value, unit: "L")
                    comparisonRow("Pérdidas", value: product.lossLiters?.value, unit: "L")
                    if let prices = product.priceVersions, !prices.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Precios aplicados en este turno")
                                .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.muted)
                            ForEach(prices) { price in
                                HStack {
                                    Text(price.unitPriceUsd.map { "USD/\(price.priceUnit) \(number($0.value))" } ?? "Precio registrado")
                                    Spacer()
                                    Text("\(price.liters.map { number($0.value) } ?? "—") L · $\(price.salesUsd.map { number($0.value) } ?? "—")")
                                }.font(.caption2.monospacedDigit()).foregroundStyle(DLCTheme.forest)
                            }
                        }
                        .padding(.top, 3)
                    }
                }
                .padding(12)
                .background(DLCTheme.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 15))
            }
            if !reconciliation.tanks.isEmpty {
                Text("Niveles de tanque").font(.subheadline.weight(.bold)).foregroundStyle(DLCTheme.forest).padding(.top, 3)
                ForEach(reconciliation.tanks) { tank in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(tank.tankCode ?? tank.tankName ?? "Tanque") · \(tank.fuelName ?? "Combustible")")
                            .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.forest)
                        comparisonRow("Libro", value: tank.ledgerLiters?.value, unit: "L")
                        comparisonRow("Medición física", value: tank.measuredLiters?.value, unit: "L")
                        comparisonRow("Variación", value: tank.varianceLiters?.value, unit: "L", emphasize: true)
                    }.padding(.vertical, 3)
                }
            }
            financialSummary(reconciliation.finance)
            if let reviewer = reconciliation.review {
                Label("Revisó \(reviewer.reviewedByName ?? "otro usuario") · \(reviewer.reviewedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "person.badge.shield.checkmark")
                    .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.green)
                Text(reviewer.reason).font(.caption).foregroundStyle(DLCTheme.muted)
            } else if reconciliation.reviewRequired && reconciliation.preparedBy == vm.currentUserID {
                Label("Preparaste este corte. Otra persona con permiso debe aprobar la diferencia.", systemImage: "person.2.fill")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            } else if let preparer = reconciliation.preparedByName {
                Text("Preparó \(preparer) · \(reconciliation.preparedAt?.formatted(date: .abbreviated, time: .shortened) ?? "fecha no disponible")")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            }
        }
        .dlcCard()
    }

    private var reviewAndCloseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Aprobación y cierre", detail: "El cierre es inmutable y conserva responsable y hora.", symbol: "lock.shield.fill", tint: DLCTheme.forest)
            if vm.cut.status == "closed" {
                Label("Corte cerrado", systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(DLCTheme.green)
                Text("Responsable: \(vm.cut.closedByName ?? "registrado en auditoría") · \(vm.cut.closedAt?.formatted(date: .long, time: .shortened) ?? "hora registrada en el servidor")")
                    .font(.subheadline).foregroundStyle(DLCTheme.muted)
            } else if vm.cut.status == "inReview", vm.reconciliation?.review == nil {
                TextField("Motivo de la revisión independiente", text: $reviewReason, axis: .vertical)
                    .lineLimit(3...5)
                    .padding(12).background(DLCTheme.background, in: RoundedRectangle(cornerRadius: 13))
                Button { Task { await vm.review(reason: reviewReason) } } label: {
                    actionLabel(vm.isWorking ? "Guardando revisión…" : "Aprobar revisión", icon: "person.badge.shield.checkmark")
                }
                .buttonStyle(.plain)
                .disabled(!vm.canReview || vm.isWorking || reviewReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                .opacity((!vm.canReview || reviewReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 8) ? 0.5 : 1)
                if !vm.canReview {
                    Text(vm.reconciliation?.preparedBy == vm.currentUserID
                         ? "Quien preparó el corte no puede aprobar su propia conciliación."
                         : "Se requiere el permiso de revisión y una cuenta distinta de quien preparó.")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
            } else if vm.cut.status == "prepared" || (vm.cut.status == "inReview" && vm.reconciliation?.review != nil) {
                if vm.waitForWindowToEnd {
                    Label("Disponible al terminar el turno · \(cutTime(vm.cut.endsAt, timezoneIdentifier: timezoneIdentifier))", systemImage: "hourglass")
                        .font(.subheadline.weight(.medium)).foregroundStyle(DLCTheme.yellow)
                }
                Button { Task { await vm.close() } } label: {
                    actionLabel(vm.isWorking ? "Cerrando corte…" : "Cerrar y consolidar corte", icon: "lock.fill")
                }
                .buttonStyle(.plain)
                .disabled(!vm.canClose || vm.isWorking)
                .opacity(vm.canClose ? 1 : 0.52)
            } else if vm.cut.status == "open" {
                Text("Primero prepara la conciliación para habilitar el cierre.")
                    .font(.subheadline).foregroundStyle(DLCTheme.muted)
            }
        }
        .dlcCard(color: vm.cut.status == "closed" ? DLCTheme.greenBG : DLCTheme.surface)
    }

    private func sectionHeading(_ title: String, detail: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol).font(.headline).foregroundStyle(tint)
                .frame(width: 38, height: 38).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(DLCTheme.forest)
                Text(detail).font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.headline)
            Text(title).font(.headline)
            Spacer(minLength: 0)
            Image(systemName: "arrow.right").font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 15).padding(.vertical, 14)
        .background(LinearGradient(colors: [DLCTheme.orange, Color(red: 0.73, green: 0.22, blue: 0.10)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 15))
    }

    private func evidencePill(_ title: String, done: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : "circle.dashed")
            .font(.caption2.weight(.semibold)).foregroundStyle(done ? DLCTheme.green : DLCTheme.muted)
            .padding(.horizontal, 9).padding(.vertical, 8)
            .background(done ? DLCTheme.greenBG : DLCTheme.surface.opacity(0.75), in: Capsule())
    }

    private func comparisonRow(_ title: String, value: Decimal?, unit: String, emphasize: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(DLCTheme.muted)
            Spacer(minLength: 8)
            Text(value.map(number) ?? "—")
                .font(.subheadline.monospacedDigit().weight(emphasize ? .bold : .medium))
                .foregroundStyle(emphasize ? DLCTheme.orange : DLCTheme.forest)
            Text(unit).font(.caption2.weight(.semibold)).foregroundStyle(DLCTheme.muted)
        }
        .font(.caption)
    }

    private func financialSummary(_ finance: RemoteCutReconciliation.Finance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Caja y ventas · USD").font(.subheadline.weight(.bold)).foregroundStyle(DLCTheme.forest)
            comparisonRow("Ventas", value: finance.salesUsd?.value, unit: "USD")
            comparisonRow("Cobro confirmado", value: finance.confirmedCollectionUsd?.value, unit: "USD")
            comparisonRow("Efectivo", value: finance.cashConfirmedUsd?.value, unit: "USD")
            comparisonRow("Tarjeta", value: finance.cardConfirmedUsd?.value, unit: "USD")
            comparisonRow("Reembolsos", value: finance.refundedUsd?.value, unit: "USD")
        }
        .padding(12)
        .background(DLCTheme.greenBG.opacity(0.75), in: RoundedRectangle(cornerRadius: 15))
    }

    private func number(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es_SV")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
    }
}

private struct RemoteCutNozzleEntry: View {
    let nozzle: RemoteCutAssets.Nozzle
    let canCapture: Bool
    let canLinkLatest: Bool
    let isWorking: Bool
    let onSave: (String) async -> Void
    let onLink: () async -> Void
    @State private var value: String

    init(nozzle: RemoteCutAssets.Nozzle, canCapture: Bool, canLinkLatest: Bool, isWorking: Bool, onSave: @escaping (String) async -> Void, onLink: @escaping () async -> Void) {
        self.nozzle = nozzle
        self.canCapture = canCapture
        self.canLinkLatest = canLinkLatest
        self.isWorking = isWorking
        self.onSave = onSave
        self.onLink = onLink
        _value = State(initialValue: nozzle.lastMeterValue ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Manguera \(nozzle.code) · \(nozzle.fuelName)")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.forest)
                    Text(nozzle.participation == "excused" ? "Excluida · \(nozzle.exclusionReason ?? "motivo registrado")" : "Totalizador acumulado · \(nozzle.meterUnitLabel)")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
                Spacer()
                if nozzle.cutReadingId != nil {
                    Label("Lista", systemImage: "checkmark.circle.fill").font(.caption2.weight(.bold)).foregroundStyle(DLCTheme.green)
                }
            }
            if nozzle.participation == "expected" {
                if nozzle.cutReadingId == nil {
                    if canLinkLatest {
                        Button {
                            Task { await onLink() }
                        } label: {
                            Label("Vincular lectura de este turno · \(nozzle.lastMeterValue ?? "") \(nozzle.meterUnitLabel)", systemImage: "link.circle.fill")
                                .font(.caption.weight(.bold)).foregroundStyle(DLCTheme.forest)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .disabled(isWorking)
                    } else if nozzle.meterVersion == nil || nozzle.lastMeterValue == nil {
                        Label("Falta una lectura base. Regístrala desde el detalle de esta bomba.", systemImage: "exclamationmark.circle.fill")
                            .font(.caption).foregroundStyle(DLCTheme.yellow).fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: 8) {
                            TextField("Lectura final", text: $value)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Lectura final de manguera \(nozzle.code)")
                            Text(nozzle.meterUnitLabel).font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.muted)
                            Button {
                                Task { await onSave(value) }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2).foregroundStyle(.white)
                                    .frame(width: 42, height: 42)
                                    .background(DLCTheme.orange, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(!canCapture || isWorking || value.isEmpty)
                            .opacity((!canCapture || value.isEmpty) ? 0.45 : 1)
                            .accessibilityLabel("Registrar lectura final")
                        }
                        HStack {
                            Text("Anterior: \(nozzle.lastMeterValue ?? "—") \(nozzle.meterUnitLabel)")
                            Spacer()
                            if let at = nozzle.lastReadingAt { Text(at.formatted(date: .omitted, time: .shortened)) }
                        }
                        .font(.caption2.monospacedDigit()).foregroundStyle(DLCTheme.muted)
                    }
                } else {
                    Text("Lectura capturada: \(nozzle.measuredLiters ?? "—") L medidos en el turno")
                        .font(.caption.weight(.medium)).foregroundStyle(DLCTheme.green)
                }
            }
        }
        .padding(11)
        .background(DLCTheme.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct RemoteCutTankEntry: View {
    let tank: RemoteCutAssets.Tank
    let canEdit: Bool
    let isWorking: Bool
    let onSave: (String, String, String) async -> Void
    @State private var measured: String
    @State private var water: String
    @State private var temperature: String

    init(tank: RemoteCutAssets.Tank, canEdit: Bool, isWorking: Bool, onSave: @escaping (String, String, String) async -> Void) {
        self.tank = tank
        self.canEdit = canEdit
        self.isWorking = isWorking
        self.onSave = onSave
        _measured = State(initialValue: tank.measuredLiters ?? "")
        _water = State(initialValue: tank.waterLiters ?? "")
        _temperature = State(initialValue: tank.temperatureC ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(tank.name ?? tank.code) · \(tank.fuelName)")
                        .font(.subheadline.weight(.bold)).foregroundStyle(DLCTheme.forest)
                    Text("Capacidad \(tank.capacityLiters) L · tanque \(tank.code)")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
                Spacer()
                if tank.measuredLiters != nil {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(DLCTheme.green)
                }
            }
            HStack(spacing: 8) {
                measurementField("Nivel (L)", value: $measured)
                measurementField("Agua (L)", value: $water)
                measurementField("°C", value: $temperature)
            }
            Button {
                Task { await onSave(measured, water, temperature) }
            } label: {
                Label(isWorking ? "Guardando…" : tank.measuredLiters == nil ? "Guardar medición" : "Actualizar medición", systemImage: "drop.circle.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(DLCTheme.blue, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canEdit || isWorking || measured.isEmpty)
            .opacity((!canEdit || measured.isEmpty) ? 0.48 : 1)
        }
        .dlcCard(color: DLCTheme.surface)
    }

    private func measurementField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(DLCTheme.muted)
            TextField("—", text: value)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity)
    }
}

private func statusLabel(_ status: String) -> String {
    switch status {
    case "scheduled": "Programado"
    case "open": "En captura"
    case "prepared": "Preparado"
    case "inReview": "Requiere revisión"
    case "closed": "Cerrado"
    default: status.capitalized
    }
}

private func statusColor(_ status: String) -> Color {
    switch status {
    case "closed": DLCTheme.green
    case "inReview": DLCTheme.yellow
    case "prepared": DLCTheme.blue
    case "open": DLCTheme.orange
    default: DLCTheme.muted
    }
}

private func statusBackground(_ status: String) -> Color {
    switch status {
    case "closed": DLCTheme.greenBG
    case "inReview": DLCTheme.yellowBG
    case "prepared": Color(red: 0.89, green: 0.93, blue: 0.95)
    case "open": DLCTheme.orangeBG
    default: DLCTheme.background
    }
}

private func cutTime(_ date: Date, timezoneIdentifier: String) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(identifier: timezoneIdentifier) ?? TimeZone(identifier: "America/El_Salvador")!
    formatter.locale = Locale(identifier: "es_SV")
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
