import SwiftUI

@MainActor
struct RemotePOSCatalogView: View {
    @StateObject private var vm: RemotePOSViewModel
    let canManage: Bool
    let canReceive: Bool
    let canSell: Bool
    let canReadCost: Bool
    @State private var showNewProduct = false
    @State private var showBasket = false
    init(repository: RemotePumpRepository, store: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID,
         canManage: Bool, canReceive: Bool, canSell: Bool, canReadCost: Bool) {
        _vm = StateObject(wrappedValue: RemotePOSViewModel(repository: repository, store: store, scope: scope, branchID: branchID))
        self.canManage = canManage; self.canReceive = canReceive; self.canSell = canSell; self.canReadCost = canReadCost
    }
    var body: some View {
        List {
            if !vm.recoveryError.isEmpty { Section { Label(vm.recoveryError, systemImage: "lock.fill").foregroundStyle(DLCTheme.red) } }
            if !vm.pending.isEmpty {
                Section("Operaciones por confirmar") {
                    ForEach(vm.pending) { draft in
                        VStack(alignment: .leading, spacing: 6) {
                            Text((try? JSONDecoder().decode(RemotePOSCommand.self, from: draft.payload).title) ?? "Operación guardada").font(.headline)
                            Text(draft.savedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            Button("Consultar mediante el mismo comando") { Task { await vm.retry(draft) } }.disabled(vm.isPosting)
                        }
                    }
                }
            }
            Section {
                Picker("Tipo", selection: $vm.kind) {
                    Text("Todos").tag("all"); Text("Tienda").tag("store"); Text("Servicios").tag("service")
                }.pickerStyle(.segmented)
                if canManage { Toggle("Mostrar inactivos", isOn: $vm.includeInactive) }
                if let date = vm.lastUpdated { Text("Consultado: \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(DLCTheme.muted) }
            }
            Section("Catálogo") {
                ForEach(vm.products) { product in
                    NavigationLink {
                        RemotePOSProductDetailView(vm: vm, product: product, canManage: canManage, canReceive: canReceive, canSell: canSell, canReadCost: canReadCost)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: product.kind == "store" ? "basket.fill" : "wrench.and.screwdriver.fill").foregroundStyle(DLCTheme.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.description).font(.headline)
                                Text(product.sku).font(.caption).foregroundStyle(DLCTheme.muted)
                                if product.kind == "store" { Text("\(product.availableUnits) unidades disponibles").font(.caption) }
                                if !product.active { Text("Inactivo").font(.caption).foregroundStyle(DLCTheme.red) }
                            }
                            Spacer(); Text("$\(product.priceUsd)").bold()
                        }.accessibilityElement(children: .combine)
                    }
                }
                if vm.products.isEmpty && !vm.isLoading && vm.errorMessage.isEmpty { ContentUnavailableView("Sin productos", systemImage: "basket", description: Text("No hay resultados para estos filtros.")) }
                if vm.nextCursor != nil { Button("Cargar más") { Task { await vm.load(more: true) } }.disabled(vm.isLoading) }
                if vm.isLoading || vm.isPosting { ProgressView(vm.isPosting ? "Confirmando operación…" : "Cargando catálogo…") }
                if !vm.errorMessage.isEmpty { Label(vm.errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(DLCTheme.red) }
                if !vm.notice.isEmpty { Label(vm.notice, systemImage: "checkmark.circle.fill").foregroundStyle(DLCTheme.green) }
            }
            if let sale = vm.lastSale { Section("Último comprobante") { RemoteFuelSaleContent(sale: sale) } }
        }
        .scrollContentBackground(.hidden)
        .dlcScreen()
        .navigationTitle("Tienda y servicios")
        .searchable(text: $vm.query, prompt: "Nombre o código")
        .onSubmit(of: .search) { Task { await vm.load() } }
        .onChange(of: vm.kind) { _, _ in Task { await vm.load() } }
        .onChange(of: vm.includeInactive) { _, _ in Task { await vm.load() } }
        .refreshable { vm.refreshPending(); await vm.load() }
        .task { await vm.load() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if canSell { Button { showBasket = true } label: { Label("Venta (\(vm.basket.count))", systemImage: "cart") }.disabled(vm.isPosting) }
                if canManage { Button { showNewProduct = true } label: { Image(systemName: "plus") }.accessibilityLabel("Agregar producto o servicio").disabled(!vm.canStartCommand) }
            }
        }
        .sheet(isPresented: $showNewProduct) { RemotePOSOfferEditor(vm: vm, product: nil, canReadCost: canReadCost) }
        .sheet(isPresented: $showBasket) { RemotePOSBasketView(vm: vm) }
        .tint(DLCTheme.orange)
    }
}

@MainActor
struct RemoteCombinedReceiptComposer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm: RemoteCombinedReceiptViewModel
    @State private var selectedPOSSaleID: UUID?
    private let canCreate: Bool

    init(repository: RemotePumpRepository, store: RemoteOfflineStore?, scope: RemoteDataScope?, branchID: UUID, fuelSaleID: UUID) {
        _vm = StateObject(wrappedValue: RemoteCombinedReceiptViewModel(repository: repository, store: store, scope: scope, branchID: branchID, fuelSaleID: fuelSaleID))
        canCreate = store != nil && scope != nil
    }

    var body: some View {
        NavigationStack {
            List {
                if let receipt = vm.receipt {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Comprobante interno", systemImage: "doc.text.image").font(.headline).foregroundStyle(DLCTheme.forest)
                            Text("Total combinado: $\(receipt.totalUsd)").font(.title3.monospacedDigit().weight(.bold))
                            Text("\(combinedCollectionTitle(receipt.collectionStatus)) · No es comprobante fiscal. Los cobros e impuestos se conservan por venta.")
                                .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                    }
                    combinedSourceSection(title: "Combustible", sale: receipt.components.fuel)
                    combinedSourceSection(title: "Tienda y servicios", sale: receipt.components.pos)
                } else {
                    Section("Comprobante de combustible") {
                        Text(canCreate ? "Selecciona una venta POS pendiente para crear un resumen combinado." : "Este resumen conserva las ventas fuente y muestra sus estados por separado.")
                            .font(.subheadline).foregroundStyle(DLCTheme.muted)
                        Text("Las ventas fuente permanecen inmutables. El comprobante combinado no agrupa cobros ni sustituye un documento fiscal.")
                            .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    if canCreate { Section("Ventas POS pendientes") {
                        ForEach(vm.candidates) { sale in
                            Button { selectedPOSSaleID = sale.id } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedPOSSaleID == sale.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedPOSSaleID == sale.id ? DLCTheme.orange : DLCTheme.muted)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(sale.description).font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.forest)
                                        Text("\(sale.lineCount) líneas · pendiente de cobro")
                                            .font(.caption).foregroundStyle(DLCTheme.muted)
                                    }
                                    Spacer()
                                    Text("$\(sale.totalUsd)").font(.subheadline.monospacedDigit().weight(.bold)).foregroundStyle(DLCTheme.forest)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if vm.candidates.isEmpty && !vm.isLoading && vm.errorMessage.isEmpty {
                            Text("No hay ventas POS pendientes disponibles.").font(.caption).foregroundStyle(DLCTheme.muted)
                        }
                        if vm.nextCursor != nil {
                            Button("Cargar más ventas") { Task { await vm.load(more: true) } }.disabled(vm.isLoading)
                        }
                        if vm.isLoading { ProgressView("Consultando ventas…") }
                    } }
                    if let selectedPOSSaleID {
                        Section {
                            Button { Task { if await vm.create(posSaleID: selectedPOSSaleID) { self.selectedPOSSaleID = nil } } } label: {
                                Label(vm.isPosting ? "Consolidando…" : "Crear comprobante combinado", systemImage: "doc.on.doc.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.borderedProminent).tint(DLCTheme.forest)
                            .disabled(!vm.canStartCommand)
                        }
                    }
                }
                if !vm.pending.isEmpty {
                    Section("Operación pendiente") {
                        ForEach(vm.pending) { draft in
                            Button("Consultar o reintentar con el mismo comando") { Task { await vm.retry(draft) } }
                                .disabled(vm.isPosting || !vm.recoveryError.isEmpty)
                        }
                    }
                }
                if !vm.recoveryError.isEmpty { Section { Label(vm.recoveryError, systemImage: "lock.fill").foregroundStyle(DLCTheme.red) } }
                if !vm.errorMessage.isEmpty { Section { Label(vm.errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true) } }
                if !vm.notice.isEmpty { Section { Label(vm.notice, systemImage: "checkmark.circle.fill").foregroundStyle(DLCTheme.green).fixedSize(horizontal: false, vertical: true) } }
            }
            .scrollContentBackground(.hidden)
            .dlcScreen()
            .navigationTitle("Resumen combinado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
            .task { await vm.load() }
            .refreshable { vm.refreshPending(); await vm.load() }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: vm.receipt?.id)
            .tint(DLCTheme.orange)
        }
    }

    @ViewBuilder
    private func combinedSourceSection(title: String, sale: RemoteFuelSale) -> some View {
        Section(title) {
            LabeledContent("Estado de cobro", value: combinedComponentStatusTitle(sale.status))
            LabeledContent("Importe de esta venta", value: "$\(sale.totalUsd)")
            LabeledContent("Cobrado", value: "$\(sale.collectedUsd ?? "0.00")")
            LabeledContent("Reservado / por confirmar", value: "$\(sale.reservedUsd ?? "0.00")")
            LabeledContent("Fiscalidad", value: sale.taxStatus == "configured" ? "Desglose configurado" : "Pendiente")
            ForEach(sale.lines) { line in
                HStack {
                    Text(line.description).lineLimit(2)
                    Spacer()
                    Text("$\(line.totalUsd)").monospacedDigit().bold()
                }.font(.caption)
            }
        }
    }
}

private func combinedCollectionTitle(_ status: String) -> String {
    switch status {
    case "paid": "Cobrado por componente"
    case "partially_collected": "Cobro parcial"
    case "awaiting_confirmation": "Cobro pendiente de confirmar"
    default: "Pendiente de cobro"
    }
}

private func combinedComponentStatusTitle(_ status: String) -> String {
    switch status {
    case "paid": "Pagada"
    case "on_credit": "A crédito"
    default: "Pendiente de cobro"
    }
}

@MainActor
private struct RemotePOSProductDetailView: View {
    @ObservedObject var vm: RemotePOSViewModel
    let product: RemotePOSProduct
    let canManage: Bool
    let canReceive: Bool
    let canSell: Bool
    let canReadCost: Bool
    @StateObject private var lots: RemotePOSLotsViewModel
    @State private var showEdit = false
    @State private var showReceipt = false
    init(vm: RemotePOSViewModel, product: RemotePOSProduct, canManage: Bool, canReceive: Bool, canSell: Bool, canReadCost: Bool) {
        self.vm = vm; self.product = product; self.canManage = canManage; self.canReceive = canReceive; self.canSell = canSell; self.canReadCost = canReadCost
        _lots = StateObject(wrappedValue: RemotePOSLotsViewModel(repository: vm.repository, branchID: vm.branchID, productID: product.id))
    }
    private var current: RemotePOSProduct { lots.product ?? (vm.products.first { $0.id == product.id }) ?? product }
    var body: some View {
        List {
            Section(current.description) {
                if lots.isLoading { ProgressView("Actualizando ficha…") }
                if !lots.errorMessage.isEmpty { Label(lots.errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(DLCTheme.red) }
                LabeledContent("Código", value: current.sku)
                LabeledContent("Tipo", value: current.kind == "store" ? "Tienda" : "Servicio")
                LabeledContent("Estado", value: current.active ? "Activo" : "Inactivo")
                LabeledContent("Precio por unidad", value: "$\(current.priceUsd)")
                LabeledContent("Versión", value: "\(current.version)")
                if current.kind == "store" {
                    LabeledContent("Disponible", value: "\(current.availableUnits) unidades")
                    LabeledContent("Vencido", value: "\(current.expiredUnits) unidades")
                } else if canReadCost { LabeledContent("Costo por unidad", value: current.serviceUnitCostUsd.map { "$\($0)" } ?? "Sin costo confirmado") }
                if canSell && current.active {
                    Button("Agregar a la venta") { vm.add(current) }.disabled(!vm.canStartCommand || (current.kind == "store" && (Decimal(string: current.availableUnits) ?? 0) <= 0))
                }
                if canManage { Button("Editar nombre, precio o estado") { showEdit = true }.disabled(!vm.canStartCommand) }
                if canReceive && current.kind == "store" && current.active { Button("Registrar recepción") { showReceipt = true }.disabled(!vm.canStartCommand) }
                if !vm.errorMessage.isEmpty { Text(vm.errorMessage).foregroundStyle(DLCTheme.red).font(.footnote) }
            }
            if current.kind == "store" {
                Section("Lotes") {
                    ForEach(lots.lots) { lot in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(lot.lotCode).font(.headline)
                            LabeledContent("Restante / recibido", value: "\(lot.remainingUnits) / \(lot.receivedUnits)")
                            LabeledContent("Vencimiento", value: lot.expiresOn ?? "No aplica")
                            LabeledContent("Documento", value: lot.sourceReference)
                            if canReadCost { LabeledContent("Costo por unidad", value: lot.unitCostUsd.map { "$\($0)" } ?? "Sin costo confirmado") }
                        }
                    }
                    if lots.lots.isEmpty && !lots.isLoading && lots.errorMessage.isEmpty { Text("Sin lotes registrados.") }
                    if lots.isLoading { ProgressView("Cargando lotes…") }
                    if !lots.errorMessage.isEmpty { Text(lots.errorMessage).foregroundStyle(DLCTheme.red) }
                    if lots.nextCursor != nil { Button("Cargar más lotes") { Task { await lots.load(more: true) } }.disabled(lots.isLoading) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .dlcScreen()
        .navigationTitle("Detalle de producto")
        .task { await lots.load() }
        .refreshable { await vm.load(); await lots.load() }
        .sheet(isPresented: $showEdit, onDismiss: { Task { await lots.load() } }) { RemotePOSOfferEditor(vm: vm, product: current, canReadCost: canReadCost) }
        .sheet(isPresented: $showReceipt, onDismiss: { Task { await lots.load() } }) { RemotePOSReceiptEditor(vm: vm, product: current, canReadCost: canReadCost) }
    }
}

@MainActor
private struct RemotePOSOfferEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemotePOSViewModel
    let product: RemotePOSProduct?
    let canReadCost: Bool
    @State private var sku = ""
    @State private var name = ""
    @State private var kind = "store"
    @State private var expiry = false
    @State private var active = true
    @State private var price = ""
    @State private var cost = ""
    @State private var validation = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Producto o servicio") {
                    TextField("Código", text: $sku).textInputAutocapitalization(.characters).autocorrectionDisabled().disabled(product != nil)
                    Picker("Tipo", selection: $kind) { Text("Tienda").tag("store"); Text("Servicio").tag("service") }.disabled(product != nil)
                    if kind == "store" { Toggle("Requiere vencimiento por lote", isOn: $expiry).disabled(product != nil) }
                    TextField("Nombre", text: $name)
                    TextField("Precio por unidad (USD)", text: $price).keyboardType(.decimalPad)
                    if kind == "service" && canReadCost { TextField(product == nil ? "Costo por unidad, si se conoce" : "Costo por unidad; vacío conserva el anterior", text: $cost).keyboardType(.decimalPad) }
                    Toggle("Activo", isOn: $active)
                }.disabled(!vm.canStartCommand)
                Section {
                    Button(product == nil ? "Crear" : "Publicar cambios") { Task { await submit() } }.disabled(!vm.canStartCommand)
                    if !validation.isEmpty { Text(validation).foregroundStyle(DLCTheme.red) }
                    if !vm.errorMessage.isEmpty { Text(vm.errorMessage).foregroundStyle(DLCTheme.red) }
                    if !vm.pending.isEmpty { Text("La operación está guardada. Cierra esta ventana y confírmala desde el catálogo.").font(.footnote) }
                }
            }
            .scrollContentBackground(.hidden)
            .dlcScreen()
            .navigationTitle(product == nil ? "Nuevo producto" : "Editar producto")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() }.disabled(vm.isPosting) } }
            .onAppear { if let product { sku = product.sku; name = product.description; kind = product.kind; expiry = product.expiryRequired; active = product.active; price = product.priceUsd; cost = product.serviceUnitCostUsd ?? "" } }
            .interactiveDismissDisabled(vm.isPosting)
        }.tint(DLCTheme.orange)
    }
    private func submit() async {
        guard let priceValue = posDecimal(price, precision: 4, positive: true), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { validation = "Completa nombre y precio positivo."; return }
        let costValue = cost.isEmpty ? nil : posDecimal(cost, precision: 8, positive: false)
        guard cost.isEmpty || costValue != nil else { validation = "El costo debe ser un importe válido, igual o mayor que cero."; return }
        validation = ""
        let body = RemotePOSOfferBody(commandId: UUID(), productId: product?.id, expectedOfferVersionId: product?.offerVersionId,
            sku: sku.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), kind: kind, expiryRequired: kind == "store" && expiry,
            description: name.trimmingCharacters(in: .whitespacesAndNewlines), active: active, priceUsd: priceValue, serviceUnitCostUsd: kind == "service" ? costValue : nil)
        if await vm.perform(.offer(body)) { dismiss() }
    }
}

@MainActor
private struct RemotePOSReceiptEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemotePOSViewModel
    let product: RemotePOSProduct
    let canReadCost: Bool
    @State private var code = ""
    @State private var quantity = ""
    @State private var cost = ""
    @State private var source = ""
    @State private var date = Date()
    @State private var hasExpiry = false
    @State private var validation = ""
    var body: some View {
        NavigationStack {
            Form {
                Section(product.description) {
                    TextField("Código de lote", text: $code)
                    TextField("Unidades recibidas", text: $quantity).keyboardType(.numberPad)
                    if canReadCost { TextField("Costo por unidad, si se conoce (USD)", text: $cost).keyboardType(.decimalPad) }
                    TextField("Referencia de factura o documento", text: $source, axis: .vertical)
                    Toggle("Tiene vencimiento", isOn: $hasExpiry).disabled(product.expiryRequired)
                    if hasExpiry { DatePicker("Vencimiento", selection: $date, displayedComponents: .date) }
                }.disabled(!vm.canStartCommand)
                Section {
                    Button("Registrar recepción") { Task { await submit() } }.disabled(!vm.canStartCommand)
                    if !validation.isEmpty { Text(validation).foregroundStyle(DLCTheme.red) }
                    if !vm.errorMessage.isEmpty { Text(vm.errorMessage).foregroundStyle(DLCTheme.red) }
                    if !vm.pending.isEmpty { Text("La operación está guardada. Confírmala desde el catálogo antes de registrar otra.").font(.footnote) }
                }
            }
            .scrollContentBackground(.hidden)
            .dlcScreen()
            .navigationTitle("Recepción de lote")
            .onAppear { hasExpiry = product.expiryRequired }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() }.disabled(vm.isPosting) } }
            .interactiveDismissDisabled(vm.isPosting)
        }.tint(DLCTheme.orange)
    }
    private func submit() async {
        guard let units = posDecimal(quantity, precision: 3, positive: true), !units.contains("."), !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { validation = "Completa lote, documento y unidades completas positivas."; return }
        let unitCost = cost.isEmpty ? nil : posDecimal(cost, precision: 8, positive: false)
        guard cost.isEmpty || unitCost != nil else { validation = "Revisa el costo por unidad."; return }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let body = RemotePOSReceiptBody(commandId: UUID(), productId: product.id, lotCode: code.trimmingCharacters(in: .whitespacesAndNewlines), expiresOn: hasExpiry ? formatter.string(from: date) : nil, quantity: units, unitCostUsd: unitCost, sourceReference: source.trimmingCharacters(in: .whitespacesAndNewlines))
        validation = ""
        if await vm.perform(.receipt(body)) { dismiss() }
    }
}

@MainActor
private struct RemotePOSBasketView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemotePOSViewModel
    var body: some View {
        NavigationStack {
            Form {
                Section("Productos y servicios") {
                    ForEach($vm.basket) { $line in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(line.product.description).font(.headline)
                            Text("$\(line.product.priceUsd) por unidad").font(.caption)
                            TextField("Cantidad", text: $line.quantity).keyboardType(line.product.kind == "store" ? .numberPad : .decimalPad)
                            Button("Quitar", role: .destructive) { let id = line.id; vm.basket.removeAll { $0.id == id } }
                        }
                    }
                    if vm.basket.isEmpty { Text("Agrega productos desde sus fichas en el catálogo.") }
                }.disabled(!vm.canStartCommand)
                Section {
                    LabeledContent("Total calculado", value: "$\(vm.estimatedTotal)")
                    Button("Registrar venta pendiente de cobro") { Task { if await vm.submitBasket() { dismiss() } } }.disabled(!vm.canStartCommand || vm.basket.isEmpty)
                    if !vm.errorMessage.isEmpty { Text(vm.errorMessage).foregroundStyle(DLCTheme.red) }
                    if !vm.pending.isEmpty { Text("Confirma la operación guardada desde el catálogo.").font(.footnote) }
                }
            }
            .scrollContentBackground(.hidden)
            .dlcScreen()
            .navigationTitle("Nueva venta")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() }.disabled(vm.isPosting) } }
            .interactiveDismissDisabled(vm.isPosting)
        }.tint(DLCTheme.orange)
    }
}

@MainActor
struct RemoteCashCenterView: View {
    @StateObject private var vm: RemoteCashViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let currentUserID: UUID
    let canManageRegisters: Bool
    let canOpen: Bool
    let canMove: Bool
    let canClose: Bool
    let canDecideVariance: Bool
    @State private var showNewRegister = false
    @State private var registerToOpen: RemoteCashRegister?

    init(client: RemoteAPIClient, store: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID,
         currentUserID: UUID, canManageRegisters: Bool, canOpen: Bool, canMove: Bool, canClose: Bool, canDecideVariance: Bool) {
        _vm = StateObject(wrappedValue: RemoteCashViewModel(client: client, store: store, scope: scope, branchID: branchID))
        self.currentUserID = currentUserID
        self.canManageRegisters = canManageRegisters
        self.canOpen = canOpen
        self.canMove = canMove
        self.canClose = canClose
        self.canDecideVariance = canDecideVariance
    }

    private var openRegisters: Int { vm.registers.filter { $0.openSessionId != nil }.count }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Caja por turno").font(.title2.bold()).foregroundStyle(DLCTheme.forest)
                            Text("Apertura, movimientos y arqueo conciliado")
                                .font(.subheadline).foregroundStyle(DLCTheme.muted)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "dollarsign.arrow.circlepath")
                            .font(.title2.weight(.semibold)).foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(LinearGradient(colors: [DLCTheme.orange, DLCTheme.yellow], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: 8) {
                        CashMetricPill(title: "Cajas", value: "\(vm.registers.count)", color: DLCTheme.forest)
                        CashMetricPill(title: "Turnos abiertos", value: "\(openRegisters)", color: openRegisters > 0 ? DLCTheme.green : DLCTheme.muted)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }

            if !vm.recoveryError.isEmpty {
                Section {
                    Label(vm.recoveryError, systemImage: "lock.fill")
                        .font(.footnote.weight(.medium)).foregroundStyle(DLCTheme.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !vm.pending.isEmpty {
                Section("Operación por confirmar") {
                    ForEach(vm.pending) { draft in
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Comando guardado", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.forest)
                            Text("Se conserva el mismo identificador para consultar o reintentar sin duplicar el movimiento.")
                                .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                            Button("Consultar estado del comando") { Task { await vm.retry(draft) } }
                                .buttonStyle(.borderedProminent).tint(DLCTheme.forest).disabled(vm.isPosting)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                if vm.isLoading && vm.registers.isEmpty {
                    ProgressView("Consultando cajas…").frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 14)
                } else if vm.registers.isEmpty && vm.errorMessage.isEmpty {
                    ContentUnavailableView("No hay cajas registradas", systemImage: "dollarsign.square", description: Text("Crea una caja para iniciar la conciliación de turnos."))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(vm.registers) { register in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 11) {
                                Image(systemName: register.openSessionId == nil ? "dollarsign.square" : "lock.open.fill")
                                    .font(.headline).foregroundStyle(register.openSessionId == nil ? DLCTheme.orange : DLCTheme.green)
                                    .frame(width: 42, height: 42)
                                    .background(register.openSessionId == nil ? DLCTheme.orangeBG : DLCTheme.greenBG, in: RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Caja \(register.code)").font(.headline).foregroundStyle(DLCTheme.forest)
                                    Text(register.openSessionId == nil ? "Sin turno abierto" : "Turno en curso · entra para ver movimientos")
                                        .font(.caption).foregroundStyle(DLCTheme.muted)
                                }
                                Spacer(minLength: 4)
                                Circle().fill(register.openSessionId == nil ? DLCTheme.border : DLCTheme.green).frame(width: 9, height: 9)
                                    .accessibilityLabel(register.openSessionId == nil ? "Sin turno" : "Turno abierto")
                            }
                            if let sessionID = register.openSessionId {
                                NavigationLink {
                                    RemoteCashSessionView(client: vm.client, store: vm.store, scope: vm.scope, branchID: vm.branchID,
                                        sessionID: sessionID, currentUserID: currentUserID, canMove: canMove, canClose: canClose,
                                        canDecideVariance: canDecideVariance)
                                } label: {
                                    Label("Abrir turno y arqueo", systemImage: "arrow.right.circle.fill")
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.forest)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 2)
                            } else if canOpen {
                                Button { registerToOpen = register } label: {
                                    Label("Abrir turno", systemImage: "play.circle.fill")
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.orange)
                                }
                                .buttonStyle(.plain).disabled(!vm.canStartCommand)
                            }
                        }
                        .padding(14)
                        .background(DLCTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(DLCTheme.border, lineWidth: 1))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                if vm.isLoading && !vm.registers.isEmpty { ProgressView("Actualizando cajas…") }
                if vm.isPosting { ProgressView("Confirmando en el servidor…") }
                if !vm.errorMessage.isEmpty {
                    Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true)
                }
                if !vm.notice.isEmpty {
                    Label(vm.notice, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium)).foregroundStyle(DLCTheme.green).fixedSize(horizontal: false, vertical: true)
                }
            } header: { Text("Cajas de la sucursal") }

            Section {
                Picker("Estado del arqueo", selection: $vm.reviewFilter) {
                    Text("Todos").tag("all")
                    Text("Pendientes").tag("pending")
                    Text("Conciliados").tag("balanced")
                    Text("Aprobados").tag("approved")
                    Text("Rechazados").tag("rejected")
                }
                .pickerStyle(.menu)
                .onChange(of: vm.reviewFilter) { _, _ in Task { await vm.loadReviews() } }
                if vm.reviews.isEmpty && vm.reviewListError.isEmpty {
                    ContentUnavailableView("Sin arqueos registrados", systemImage: "checkmark.seal", description: Text("Los cierres recientes de caja aparecerán aquí."))
                        .listRowBackground(Color.clear)
                }
                ForEach(vm.reviews.prefix(10)) { review in
                    NavigationLink {
                        RemoteCashSessionView(client: vm.client, store: vm.store, scope: vm.scope, branchID: vm.branchID,
                            sessionID: review.sessionId, currentUserID: currentUserID, canMove: canMove, canClose: canClose,
                            canDecideVariance: canDecideVariance)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(cashReviewStatusColor(review.status))
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(cashReviewStatusTitle(review.status)).font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.forest)
                                Text(review.closedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Cierre registrado")
                                    .font(.caption).foregroundStyle(DLCTheme.muted)
                            }
                            Spacer(minLength: 5)
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Efectivo Δ \(review.varianceCashUsd.map { "$\($0)" } ?? "—")")
                                Text("Tarjeta Δ \(review.varianceCardUsd.map { "$\($0)" } ?? "—")")
                            }
                            .font(.caption2.monospacedDigit().weight(.medium)).foregroundStyle(DLCTheme.muted)
                        }
                        .padding(.vertical, 3)
                    }
                }
                if !vm.reviewListError.isEmpty {
                    Label("No se pudieron cargar los arqueos: \(vm.reviewListError)", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true)
                }
            } header: { Text("Arqueos recientes") } footer: {
                Text("Se muestran hasta 10 cierres recientes. Las diferencias requieren resolución de otra persona.")
            }

            Section {
                Label("El saldo esperado se calcula con el fondo de apertura y los movimientos confirmados. El arqueo queda inmutable al cerrar.", systemImage: "info.circle.fill")
                    .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(DLCTheme.orangeBG)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dlcScreen()
        .navigationTitle("Caja y arqueos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if canManageRegisters {
                    Button { showNewRegister = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Registrar caja")
                        .disabled(!vm.canStartCommand)
                }
            }
        }
        .refreshable { vm.refreshPending(); await vm.load() }
        .onAppear {
            vm.refreshPending()
            Task { await vm.load() }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: vm.registers.count)
        .sheet(isPresented: $showNewRegister, onDismiss: { Task { await vm.load() } }) {
            RemoteCashRegisterSheet(vm: vm)
        }
        .sheet(item: $registerToOpen, onDismiss: { Task { await vm.load() } }) { register in
            RemoteCashOpenSheet(vm: vm, register: register)
        }
        .tint(DLCTheme.orange)
    }
}

@MainActor
private struct RemoteCashSessionView: View {
    @StateObject private var vm: RemoteCashViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let currentUserID: UUID
    let canMove: Bool
    let canClose: Bool
    let canDecideVariance: Bool
    @State private var movementKind: String?
    @State private var showMovement = false
    @State private var showClose = false
    @State private var showVarianceDecision = false

    init(client: RemoteAPIClient, store: RemoteOfflineStore, scope: RemoteDataScope, branchID: UUID, sessionID: UUID,
         currentUserID: UUID, canMove: Bool, canClose: Bool, canDecideVariance: Bool) {
        _vm = StateObject(wrappedValue: RemoteCashViewModel(client: client, store: store, scope: scope, branchID: branchID, sessionID: sessionID))
        self.currentUserID = currentUserID
        self.canMove = canMove
        self.canClose = canClose
        self.canDecideVariance = canDecideVariance
    }

    private var isClosed: Bool { vm.session?.closureId != nil }
    private var pendingDecisions: [RemoteCashApprovalCommand] {
        vm.pendingReviewCommands.filter { $0.sessionId == vm.session?.id }
    }

    var body: some View {
        List {
            if let session = vm.session {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(isClosed ? "Turno cerrado" : "Turno en curso")
                                    .font(.title2.bold()).foregroundStyle(DLCTheme.forest)
                                Text("Abierto \(session.openedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(DLCTheme.muted)
                            }
                            Spacer()
                            Image(systemName: isClosed ? "checkmark.seal.fill" : "clock.badge.checkmark.fill")
                                .font(.title2).foregroundStyle(isClosed ? DLCTheme.green : DLCTheme.orange)
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text("Efectivo esperado")
                                .font(.subheadline.weight(.medium)).foregroundStyle(DLCTheme.muted)
                            Spacer()
                            Text("$\(session.expectedCashUsd)")
                                .font(.title2.monospacedDigit().weight(.bold)).foregroundStyle(DLCTheme.forest)
                                .contentTransition(.numericText())
                        }
                        HStack(spacing: 8) {
                            CashMetricPill(title: "Fondo inicial", value: "$\(session.openingUsd)", color: DLCTheme.forest)
                            CashMetricPill(title: "Visibles", value: "\(vm.movements.count)", color: DLCTheme.orange)
                        }
                        if !isClosed && canMove {
                            HStack(spacing: 10) {
                                cashAction("Entrada", symbol: "plus", kind: "cash_in", tint: DLCTheme.green)
                                cashAction("Retiro", symbol: "arrow.up.right", kind: "withdrawal", tint: DLCTheme.orange)
                                cashAction("Depósito", symbol: "building.columns", kind: "deposit", tint: DLCTheme.forest)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(15)
                    .background(LinearGradient(colors: [DLCTheme.surface, DLCTheme.greenBG.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(DLCTheme.border, lineWidth: 1))
                    .listRowBackground(Color.clear)
                }

                if isClosed {
                    Section("Resultado del arqueo") {
                        if let review = vm.review {
                            CashReviewSummary(
                                review: review,
                                canDecide: canDecideVariance && review.cashierId != currentUserID,
                                onDecide: { showVarianceDecision = true }
                            )
                        } else if !vm.reviewError.isEmpty {
                            Label("No se pudo cargar la revisión: \(vm.reviewError)", systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true)
                        } else {
                            ProgressView("Cargando resultado…")
                        }
                    }
                } else if canClose {
                    Section {
                        Button { showClose = true } label: {
                            Label("Realizar arqueo y cerrar turno", systemImage: "checkmark.shield.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent).tint(DLCTheme.forest)
                        .disabled(!vm.canStartCommand)
                        Text("Al cerrar se comparan los saldos esperados con el efectivo contado y la liquidación de tarjeta.")
                            .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                    } header: { Text("Cierre del turno") }
                }
            } else if vm.isLoading {
                ProgressView("Cargando turno…").frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 18)
            }

            if !vm.recoveryError.isEmpty {
                Section { Label(vm.recoveryError, systemImage: "lock.fill").font(.footnote).foregroundStyle(DLCTheme.red) }
            }
            if !vm.pending.isEmpty {
                Section("Operación por confirmar") {
                    ForEach(vm.pending) { draft in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Hay un comando de caja pendiente de confirmar.").font(.subheadline.weight(.semibold))
                            Button("Consultar estado con el mismo comando") { Task { await vm.retry(draft) } }
                                .buttonStyle(.borderedProminent).tint(DLCTheme.forest).disabled(vm.isPosting)
                        }
                    }
                }
            }
            if !pendingDecisions.isEmpty {
                Section("Decisión por confirmar") {
                    ForEach(pendingDecisions) { command in
                        VStack(alignment: .leading, spacing: 8) {
                            Label("La decisión quedó guardada en este dispositivo.", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.forest)
                            Text("Se consulta primero el estado del servidor. Si aún está pendiente, se reintenta con el mismo motivo.")
                                .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                            Button("Consultar estado / reintentar decisión") { Task { await vm.retryVarianceDecision(command) } }
                                .buttonStyle(.borderedProminent).tint(DLCTheme.forest).disabled(vm.isPosting)
                        }
                    }
                }
            }

            Section {
                Picker("Tipo de movimiento", selection: $vm.movementFilter) {
                    Text("Todos").tag("all")
                    Text("Cobros").tag("collection")
                    Text("Reembolsos").tag("refund")
                    Text("Entradas").tag("cash_in")
                    Text("Retiros").tag("withdrawal")
                    Text("Depósitos").tag("deposit")
                }
                .pickerStyle(.menu)
                .onChange(of: vm.movementFilter) { _, _ in Task { await vm.loadMovements(more: false) } }
            } header: { Text("Historial de caja") }

            if vm.isLoadingMovements && vm.movements.isEmpty {
                ProgressView("Consultando movimientos…").frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
                    .listRowBackground(Color.clear)
            } else if vm.movements.isEmpty && !vm.isLoading && vm.errorMessage.isEmpty {
                ContentUnavailableView("Sin movimientos", systemImage: "list.bullet.rectangle", description: Text("Los cobros, reembolsos y movimientos de caja aparecerán aquí."))
                    .listRowBackground(Color.clear)
            }
            ForEach(vm.movements) { movement in
                HStack(spacing: 11) {
                    Image(systemName: cashMovementSymbol(movement.kind))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(cashMovementColor(movement.kind))
                        .frame(width: 38, height: 38)
                        .background(cashMovementColor(movement.kind).opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cashMovementTitle(movement.kind)).font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.forest)
                        Text(movement.reason).font(.caption).foregroundStyle(DLCTheme.muted).lineLimit(2)
                        Text(movement.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(DLCTheme.muted)
                    }
                    Spacer(minLength: 8)
                    Text("$\(movement.deltaUsd)")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(movement.deltaUsd.hasPrefix("-") ? DLCTheme.red : DLCTheme.green)
                }
                .padding(12)
                .background(DLCTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(DLCTheme.border, lineWidth: 1))
                .listRowSeparator(.hidden).listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            if vm.nextCursor != nil {
                Section {
                    Button { Task { await vm.loadMovements(more: true) } } label: {
                        if vm.isLoadingMore { ProgressView("Cargando más…") }
                        else { Label("Cargar movimientos anteriores", systemImage: "arrow.down.circle") }
                    }.disabled(vm.isLoadingMore)
                }
            }
            if vm.isLoading { ProgressView("Actualizando turno…") }
            if !vm.errorMessage.isEmpty {
                Section { Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(DLCTheme.red) }
            }
            if !vm.notice.isEmpty {
                Section { Label(vm.notice, systemImage: "checkmark.circle.fill").font(.footnote.weight(.medium)).foregroundStyle(DLCTheme.green) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dlcScreen()
        .navigationTitle("Detalle de caja")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { Task { await vm.load() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Actualizar turno") } }
        .refreshable { vm.refreshPending(); await vm.load() }
        .task { await vm.load() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: vm.movements.count)
        .sheet(isPresented: $showMovement) {
            if let movementKind { RemoteCashMovementSheet(vm: vm, kind: movementKind) }
        }
        .sheet(isPresented: $showClose) { RemoteCashCloseSheet(vm: vm) }
        .sheet(isPresented: $showVarianceDecision) {
            if let review = vm.review { RemoteCashVarianceDecisionSheet(vm: vm, review: review) }
        }
        .tint(DLCTheme.orange)
    }

    private func cashAction(_ title: String, symbol: String, kind: String, tint: Color) -> some View {
        Button {
            movementKind = kind
            showMovement = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.headline)
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .foregroundStyle(tint)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain).disabled(!vm.canStartCommand || isClosed)
    }
}

private struct CashMetricPill: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(DLCTheme.muted)
            Text(value).font(.subheadline.monospacedDigit().weight(.bold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(DLCTheme.surface.opacity(0.86), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CashReviewSummary: View {
    let review: RemoteCashReview
    let canDecide: Bool
    let onDecide: () -> Void
    private var statusText: String { cashReviewStatusTitle(review.status) }
    private var statusColor: Color { cashReviewStatusColor(review.status) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(statusText, systemImage: review.status == "balanced" ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
                .font(.subheadline.weight(.bold)).foregroundStyle(statusColor)
            cashReviewRow("Efectivo esperado", review.expectedCashUsd)
            cashReviewRow("Efectivo contado", review.countedCashUsd)
            cashReviewRow("Diferencia de efectivo", review.varianceCashUsd, emphasized: true)
            Divider()
            cashReviewRow("Tarjeta esperada", review.expectedCardUsd)
            cashReviewRow("Tarjeta liquidada", review.settledCardUsd)
            cashReviewRow("Diferencia de tarjeta", review.varianceCardUsd, emphasized: true)
            if let reason = review.cashierReason, !reason.isEmpty {
                Text("Nota del cierre: \(reason)").font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            if review.status == "pending" {
                if canDecide {
                    Text("La decisión queda registrada con usuario, fecha y motivo; el cierre original no se modifica.")
                        .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                    Button(action: onDecide) {
                        Label("Revisar diferencia", systemImage: "checkmark.shield")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent).tint(DLCTheme.forest)
                } else {
                    Text("Solo un usuario con permisos de aprobación, distinto de quien cerró el turno, puede resolver esta diferencia.")
                        .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                }
            } else if let decision = review.decisionReason, !decision.isEmpty {
                Text("Resolución: \(decision)").font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14).background(statusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(statusColor.opacity(0.25), lineWidth: 1))
        .listRowBackground(Color.clear)
    }

    @ViewBuilder private func cashReviewRow(_ title: String, _ value: String?, emphasized: Bool = false) -> some View {
        HStack {
            Text(title).font(emphasized ? .subheadline.weight(.semibold) : .caption).foregroundStyle(emphasized ? DLCTheme.forest : DLCTheme.muted)
            Spacer()
            Text(value.map { "$\($0)" } ?? "—").font(emphasized ? .subheadline.monospacedDigit().weight(.bold) : .caption.monospacedDigit())
                .foregroundStyle(emphasized ? DLCTheme.forest : DLCTheme.muted)
        }
    }
}

@MainActor
private struct RemoteCashVarianceDecisionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemoteCashViewModel
    let review: RemoteCashReview
    @State private var decision = "approved"
    @State private var reason = ""
    @State private var validation = ""

    private var normalizedReason: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { (3...1000).contains(normalizedReason.count) && !vm.isPosting && vm.pendingReviewCommands.isEmpty && vm.recoveryError.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Diferencia") {
                    HStack { Text("Efectivo"); Spacer(); Text("$\(review.varianceCashUsd ?? "—")").monospacedDigit().bold() }
                    HStack { Text("Tarjeta"); Spacer(); Text("$\(review.varianceCardUsd ?? "—")").monospacedDigit().bold() }
                    Text("La decisión se registra en una auditoría separada. El arqueo cerrado permanece inmutable.")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
                Section("Decisión") {
                    Picker("Resultado", selection: $decision) {
                        Text("Aprobar diferencia").tag("approved")
                        Text("Rechazar diferencia").tag("rejected")
                    }
                    .pickerStyle(.segmented)
                    TextEditor(text: $reason)
                        .frame(minHeight: 110)
                        .accessibilityLabel("Motivo de la decisión")
                        .onChange(of: reason) { _, value in
                            if value.count > 1000 { reason = String(value.prefix(1000)) }
                        }
                    HStack {
                        Text("Motivo obligatorio, de 3 a 1,000 caracteres.").font(.caption).foregroundStyle(DLCTheme.muted)
                        Spacer()
                        Text("\(normalizedReason.count)/1000").font(.caption.monospacedDigit()).foregroundStyle(normalizedReason.count >= 3 ? DLCTheme.green : DLCTheme.muted)
                    }
                }
                if !validation.isEmpty {
                    Section { Label(validation, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(DLCTheme.red) }
                }
                if !vm.errorMessage.isEmpty {
                    Section { Label(vm.errorMessage, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(DLCTheme.red).fixedSize(horizontal: false, vertical: true) }
                }
                if vm.isPosting {
                    Section { ProgressView("Verificando y guardando decisión…") }
                }
                Section {
                    Button {
                        guard canSubmit else {
                            validation = "Escribe un motivo de 3 a 1,000 caracteres y resuelve cualquier decisión pendiente."
                            return
                        }
                        Task {
                            if await vm.decideVariance(review: review, decision: decision, reason: normalizedReason) { dismiss() }
                        }
                    } label: {
                        Label(decision == "approved" ? "Aprobar diferencia" : "Rechazar diferencia", systemImage: decision == "approved" ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent).tint(decision == "approved" ? DLCTheme.forest : DLCTheme.red)
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Revisión independiente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(vm.isPosting) } }
            .interactiveDismissDisabled(vm.isPosting)
        }
        .tint(DLCTheme.orange)
    }
}

@MainActor
private struct RemoteCashRegisterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemoteCashViewModel
    @State private var code = ""
    @State private var validation = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Identificación") {
                    TextField("Código de caja", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Text("Usa un código único de la sucursal, por ejemplo CAJA-01.")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
                Section {
                    Button("Registrar caja") {
                        Task {
                            if await vm.createRegister(code: code) { dismiss() }
                            else { validation = vm.errorMessage }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!vm.canStartCommand || vm.isPosting)
                    if vm.isPosting { ProgressView("Guardando…") }
                    if !validation.isEmpty { Text(validation).font(.footnote).foregroundStyle(DLCTheme.red) }
                    if !vm.pending.isEmpty { Text("El servidor no confirmó el resultado. La operación quedó guardada para consultar su estado.").font(.footnote).foregroundStyle(DLCTheme.yellow) }
                }
            }
            .scrollContentBackground(.hidden).dlcScreen().navigationTitle("Nueva caja")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(vm.isPosting) } }
            .interactiveDismissDisabled(vm.isPosting)
        }.tint(DLCTheme.orange)
    }
}

@MainActor
private struct RemoteCashOpenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemoteCashViewModel
    let register: RemoteCashRegister
    @State private var opening = "0.00"
    @State private var validation = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Apertura · Caja \(register.code)") {
                    TextField("Fondo inicial (USD)", text: $opening).keyboardType(.decimalPad)
                    Text("El fondo inicial forma parte del efectivo esperado del turno.").font(.caption).foregroundStyle(DLCTheme.muted)
                }
                Section {
                    Button("Abrir turno") {
                        Task {
                            if await vm.openRegister(register.id, opening: opening) { dismiss() }
                            else { validation = vm.errorMessage }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!vm.canStartCommand || vm.isPosting)
                    if vm.isPosting { ProgressView("Abriendo turno…") }
                    if !validation.isEmpty { Text(validation).font(.footnote).foregroundStyle(DLCTheme.red) }
                    if !vm.pending.isEmpty { Text("La apertura está guardada para confirmar usando el mismo identificador.").font(.footnote).foregroundStyle(DLCTheme.yellow) }
                }
            }
            .scrollContentBackground(.hidden).dlcScreen().navigationTitle("Abrir turno")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(vm.isPosting) } }
            .interactiveDismissDisabled(vm.isPosting)
        }.tint(DLCTheme.orange)
    }
}

@MainActor
private struct RemoteCashMovementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemoteCashViewModel
    let kind: String
    @State private var amount = ""
    @State private var reason = ""
    @State private var validation = ""
    private var title: String { cashMovementTitle(kind) }
    var body: some View {
        NavigationStack {
            Form {
                Section(title) {
                    TextField("Importe (USD)", text: $amount).keyboardType(.decimalPad)
                    TextField("Motivo y referencia", text: $reason, axis: .vertical).lineLimit(2...5)
                    Text("Este movimiento quedará en la bitácora del turno.").font(.caption).foregroundStyle(DLCTheme.muted)
                }
                Section {
                    Button("Confirmar \(title.lowercased())") {
                        Task {
                            guard let sessionID = vm.sessionID else { validation = "No se encontró el turno."; return }
                            if await vm.recordMovement(sessionID: sessionID, kind: kind, amount: amount, reason: reason) { dismiss() }
                            else { validation = vm.errorMessage }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!vm.canStartCommand || vm.isPosting)
                    if vm.isPosting { ProgressView("Registrando movimiento…") }
                    if !validation.isEmpty { Text(validation).font(.footnote).foregroundStyle(DLCTheme.red) }
                    if !vm.pending.isEmpty { Text("El movimiento quedó guardado para confirmar; no registres otro hasta consultar el resultado.").font(.footnote).foregroundStyle(DLCTheme.yellow) }
                }
            }
            .scrollContentBackground(.hidden).dlcScreen().navigationTitle(title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(vm.isPosting) } }
            .interactiveDismissDisabled(vm.isPosting)
        }.tint(DLCTheme.orange)
    }
}

@MainActor
private struct RemoteCashCloseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: RemoteCashViewModel
    @State private var countedCash = ""
    @State private var settledCard = "0.00"
    @State private var reason = ""
    @State private var validation = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Conteo físico y liquidación") {
                    if let session = vm.session {
                        LabeledContent("Efectivo esperado", value: "$\(session.expectedCashUsd)")
                    }
                    TextField("Efectivo contado (USD)", text: $countedCash).keyboardType(.decimalPad)
                    TextField("Neto de tarjeta liquidado (USD)", text: $settledCard).keyboardType(.numbersAndPunctuation)
                    TextField("Observación si hay diferencia", text: $reason, axis: .vertical).lineLimit(2...5)
                    Text("Usa un importe negativo si hubo contracargos netos. El servidor calcula las diferencias y las envía a revisión independiente.")
                        .font(.caption).foregroundStyle(DLCTheme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    Button("Confirmar arqueo y cerrar") {
                        Task {
                            guard let sessionID = vm.sessionID else { validation = "No se encontró el turno."; return }
                            if await vm.closeSession(sessionID: sessionID, countedCash: countedCash, settledCard: settledCard, reason: reason) { dismiss() }
                            else { validation = vm.errorMessage }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!vm.canStartCommand || vm.isPosting)
                    if vm.isPosting { ProgressView("Cerrando turno…") }
                    if !validation.isEmpty { Text(validation).font(.footnote).foregroundStyle(DLCTheme.red) }
                    if !vm.pending.isEmpty { Text("El cierre quedó guardado para confirmar. Consulta el mismo comando antes de intentar otro cierre.").font(.footnote).foregroundStyle(DLCTheme.yellow) }
                }
            }
            .scrollContentBackground(.hidden).dlcScreen().navigationTitle("Arqueo de caja")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(vm.isPosting) } }
            .interactiveDismissDisabled(vm.isPosting)
        }.tint(DLCTheme.orange)
    }
}

private func cashMovementTitle(_ kind: String) -> String {
    switch kind {
    case "collection": "Cobro de venta"
    case "refund": "Reembolso"
    case "cash_in": "Entrada de efectivo"
    case "withdrawal": "Retiro de efectivo"
    case "deposit": "Depósito"
    default: "Movimiento"
    }
}

private func cashMovementSymbol(_ kind: String) -> String {
    switch kind {
    case "collection": "cart.fill"
    case "refund": "arrow.uturn.backward.circle.fill"
    case "cash_in": "plus.circle.fill"
    case "withdrawal": "arrow.up.right.circle.fill"
    case "deposit": "building.columns.fill"
    default: "circle.fill"
    }
}

private func cashMovementColor(_ kind: String) -> Color {
    switch kind {
    case "collection", "cash_in": DLCTheme.green
    case "refund", "withdrawal", "deposit": DLCTheme.orange
    default: DLCTheme.muted
    }
}

private func cashReviewStatusTitle(_ status: String) -> String {
    switch status {
    case "balanced": "Conciliado"
    case "pending": "Pendiente de revisión"
    case "approved": "Diferencia aprobada"
    case "rejected": "Diferencia rechazada"
    default: status.capitalized
    }
}

private func cashReviewStatusColor(_ status: String) -> Color {
    switch status {
    case "balanced", "approved": DLCTheme.green
    case "pending": DLCTheme.yellow
    case "rejected": DLCTheme.red
    default: DLCTheme.muted
    }
}
