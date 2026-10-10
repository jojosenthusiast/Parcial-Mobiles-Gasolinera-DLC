import SwiftUI

enum OperationsSection {
    case management
    case store
    case team
}

struct OperationsRootView: View {
    let actor: AppUser
    let branchID: UUID?
    let section: OperationsSection
    @StateObject private var vm: OperationsViewModel

    init(actor: AppUser, branchID: UUID?, section: OperationsSection) {
        self.actor = actor
        self.branchID = branchID
        self.section = section
        _vm = StateObject(wrappedValue: OperationsViewModel(actor: actor, branchID: branchID))
    }

    var body: some View {
        Group {
            switch section {
            case .management: NetworkManagementHomeView(vm: vm)
            case .store: BranchStoreHomeView(vm: vm)
            case .team: TeamOperationsHomeView(vm: vm)
            }
        }
    }
}

struct NetworkManagementHomeView: View {
    @ObservedObject var vm: OperationsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HeaderView(role: "Gerente General", location: "Gestión de la red")
                Text("Operaciones y recursos").font(.largeTitle.weight(.bold))
                Text("Administra catálogos y revisa lo que requiere acción en las sucursales.")
                    .font(.subheadline).foregroundStyle(DLCTheme.muted)

                Picker("Sucursal", selection: $vm.selectedBranchID) {
                    Text("Toda la red").tag(UUID?.none)
                    ForEach(vm.activeBranches) { branch in Text(branch.name).tag(Optional(branch.id)) }
                }
                .pickerStyle(.menu)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DLCTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 10) {
                    compactMetric("Productos bajos", value: "\(vm.stockAlerts.count)", symbol: "shippingbox.fill", color: vm.stockAlerts.isEmpty ? DLCTheme.green : DLCTheme.red)
                    compactMetric("Lotes por vencer", value: "\(vm.expiringSoonLots.count)", symbol: "calendar.badge.clock", color: vm.expiringSoonLots.isEmpty ? DLCTheme.green : DLCTheme.yellow)
                }
                HStack(spacing: 10) {
                    compactMetric("Personal activo", value: "\(vm.activeStaffCount)", symbol: "person.2.fill", color: DLCTheme.blue)
                    compactMetric("Órdenes abiertas", value: "\(vm.openMaintenanceCount)", symbol: "wrench.and.screwdriver.fill", color: vm.openMaintenanceCount == 0 ? DLCTheme.green : DLCTheme.orange)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Atención de inventario").font(.headline)
                    if vm.stockAlerts.isEmpty && vm.expiredLots.isEmpty {
                        Label("Sin alertas de existencias o vencimientos.", systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(DLCTheme.green)
                    } else {
                        ForEach(vm.stockAlerts.prefix(3)) { alert in
                            Label("\(alert.branch.name) · \(alert.product.name): \(alert.quantity) \(alert.product.unitName)", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.medium)).foregroundStyle(DLCTheme.red)
                        }
                        if !vm.expiredLots.isEmpty {
                            Label("\(vm.expiredLots.count) lote(s) vencido(s) requieren retiro.", systemImage: "calendar.badge.exclamationmark")
                                .font(.caption.weight(.medium)).foregroundStyle(DLCTheme.red)
                        }
                    }
                }
                .dlcCard(color: vm.stockAlerts.isEmpty && vm.expiredLots.isEmpty ? DLCTheme.greenBG : DLCTheme.redBG)

                VStack(spacing: 10) {
                    NavigationLink { ProductCatalogView(vm: vm) } label: {
                        OperationsLinkRow(title: "Catálogo de tienda", subtitle: "Productos, precios y estado de venta", symbol: "square.grid.2x2.fill")
                    }
                    NavigationLink { SuppliersListView(vm: vm, canEdit: true) } label: {
                        OperationsLinkRow(title: "Proveedores", subtitle: "Contactos y abastecimiento", symbol: "truck.box.fill")
                    }
                    NavigationLink { StoreInventoryView(vm: vm) } label: {
                        OperationsLinkRow(title: "Inventario y lotes", subtitle: "Existencias, vencimientos y recepciones", symbol: "shippingbox.fill")
                    }
                    NavigationLink { StoreSalesHistoryView(vm: vm) } label: {
                        OperationsLinkRow(title: "Ventas de tienda", subtitle: "Historial, pagos y detalle de cada ticket", symbol: "receipt.fill")
                    }
                    NavigationLink { StaffManagementView(vm: vm) } label: {
                        OperationsLinkRow(title: "Personal y turnos", subtitle: "Equipo asignado por sucursal", symbol: "person.2.fill")
                    }
                    NavigationLink { EquipmentMaintenanceView(vm: vm) } label: {
                        OperationsLinkRow(title: "Activos y mantenimiento", subtitle: "Bombas, tanques, equipos y órdenes", symbol: "wrench.and.screwdriver.fill")
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Gestión")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
    }

    private func compactMetric(_ title: String, value: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.title2.weight(.bold)).foregroundStyle(DLCTheme.forest)
            Text(title).font(.caption).foregroundStyle(DLCTheme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(13)
        .background(DLCTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct BranchStoreHomeView: View {
    @ObservedObject var vm: OperationsViewModel

    private var todaySales: [StoreSale] {
        vm.sales(from: Date(), through: Date(), branchID: vm.fixedBranchID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HeaderView(role: "Gerente de Sucursal", location: vm.localBranch?.name ?? "Tienda")
                Text("Tienda").font(.largeTitle.weight(.bold))
                Text("Venta, recepción e inventario por lote.").font(.subheadline).foregroundStyle(DLCTheme.muted)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ventas de hoy").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.8))
                    Text(todaySales.reduce(0) { $0 + $1.totalCents }.moneyUSD)
                        .font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                    Text("\(todaySales.count) transacciones · \(todaySales.reduce(0) { $0 + $1.itemCount }) artículos")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                .padding(19).frame(maxWidth: .infinity, alignment: .leading)
                .background(DLCTheme.forest).clipShape(RoundedRectangle(cornerRadius: 20))

                if !vm.stockAlerts.isEmpty || !vm.expiredLots.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Revisión de tienda", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundStyle(DLCTheme.red)
                        ForEach(vm.stockAlerts.prefix(3)) { alert in
                            Text("\(alert.product.name): \(alert.quantity) disponibles; mínimo \(alert.product.minimumStock).")
                                .font(.caption).foregroundStyle(DLCTheme.forest)
                        }
                        if !vm.expiredLots.isEmpty {
                            Text("\(vm.expiredLots.count) lote(s) vencido(s) deben retirarse antes de vender.")
                                .font(.caption).foregroundStyle(DLCTheme.red)
                        }
                        if !vm.expiringSoonLots.isEmpty {
                            Text("\(vm.expiringSoonLots.count) lote(s) vencen en los próximos 30 días.")
                                .font(.caption).foregroundStyle(DLCTheme.yellow)
                        }
                    }
                    .dlcCard(color: DLCTheme.redBG)
                }

                VStack(spacing: 10) {
                    NavigationLink { StorePOSView(vm: vm) } label: {
                        OperationsLinkRow(title: "Nueva venta", subtitle: "Punto de venta y cobro", symbol: "cart.fill")
                    }
                    NavigationLink { StoreInventoryView(vm: vm) } label: {
                        OperationsLinkRow(title: "Inventario y recepción", subtitle: "Registrar compras, lotes y ajustes", symbol: "shippingbox.fill")
                    }
                    NavigationLink { StoreSalesHistoryView(vm: vm) } label: {
                        OperationsLinkRow(title: "Historial de ventas", subtitle: "Buscar tickets por fecha y artículo", symbol: "receipt.fill")
                    }
                }
                Text("La venta descuenta primero los lotes con vencimiento más próximo. Los lotes vencidos no se ofrecen para venta.")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            }
            .padding(20)
        }
        .navigationTitle("Tienda")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
    }
}

struct TeamOperationsHomeView: View {
    @ObservedObject var vm: OperationsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HeaderView(role: vm.actor.roleLabel, location: vm.localBranch?.name ?? "Toda la red")
                Text("Equipo y activos").font(.largeTitle.weight(.bold))
                Text("Personal, turnos programados y estado del equipo de estación.")
                    .font(.subheadline).foregroundStyle(DLCTheme.muted)
                HStack(spacing: 10) {
                    teamMetric("Personas activas", "\(vm.activeStaffCount)", "person.2.fill")
                    teamMetric("Órdenes abiertas", "\(vm.openMaintenanceCount)", "wrench.and.screwdriver.fill")
                }
                NavigationLink { StaffManagementView(vm: vm) } label: {
                    OperationsLinkRow(title: "Personal y turnos", subtitle: "Altas, edición, estado y horarios", symbol: "person.2.fill")
                }
                NavigationLink { EquipmentMaintenanceView(vm: vm) } label: {
                    OperationsLinkRow(title: "Activos y mantenimiento", subtitle: "Inventario técnico y órdenes de trabajo", symbol: "wrench.and.screwdriver.fill")
                }
            }
            .padding(20)
        }
        .navigationTitle("Equipo")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
    }

    private func teamMetric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(DLCTheme.orange)
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(DLCTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(DLCTheme.surface).clipShape(RoundedRectangle(cornerRadius: 15))
    }
}

struct OperationsLinkRow: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(DLCTheme.orange)
                .frame(width: 40, height: 40).background(DLCTheme.orangeBG).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.forest)
                Text(subtitle).font(.caption).foregroundStyle(DLCTheme.muted)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(DLCTheme.muted)
        }
        .padding(13).background(DLCTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(DLCTheme.border))
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .contentShape(Rectangle())
    }
}

struct ProductCatalogView: View {
    @ObservedObject var vm: OperationsViewModel
    @State private var editingProduct: StoreProduct?
    @State private var showNewProduct = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                searchField("Buscar por nombre, SKU o código de barras", text: $vm.searchText)
                Picker("Categoría", selection: $vm.selectedCategory) {
                    Text("Todas").tag(StoreCategory?.none)
                    ForEach(StoreCategory.allCases) { category in Text(category.rawValue).tag(Optional(category)) }
                }
                .pickerStyle(.menu).padding(11).background(DLCTheme.surface).clipShape(RoundedRectangle(cornerRadius: 11))
                Toggle("Mostrar productos inactivos", isOn: $vm.showInactiveProducts)
                    .font(.caption.weight(.medium)).tint(DLCTheme.orange)
                HStack {
                    Text("Catálogo").font(.headline)
                    Spacer()
                    Text("\(vm.filteredProducts.count) productos").font(.caption).foregroundStyle(DLCTheme.muted)
                    Button { showNewProduct = true } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(DLCTheme.orange) }
                        .accessibilityLabel("Agregar producto")
                }
                ForEach(vm.filteredProducts) { product in
                    Button { editingProduct = product } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(product.name).font(.headline).foregroundStyle(DLCTheme.forest)
                                    Text("\(product.sku) · \(product.category.rawValue)").font(.caption).foregroundStyle(DLCTheme.muted)
                                }
                                Spacer()
                                Text(product.unitPriceCents.moneyUSD).font(.subheadline.weight(.bold)).foregroundStyle(DLCTheme.forest)
                            }
                            HStack {
                                Text("Costo \(product.unitCostCents.moneyUSD) · Margen \(product.marginCents.moneyUSD)")
                                Spacer()
                                Text("Mín. \(product.minimumStock)")
                            }.font(.caption2).foregroundStyle(DLCTheme.muted)
                        }
                    }
                    .buttonStyle(.plain).dlcCard()
                }
            }
            .padding(18)
        }
        .navigationTitle("Catálogo")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .sheet(isPresented: $showNewProduct) { NavigationStack { ProductFormView(vm: vm, product: nil) } }
        .sheet(item: $editingProduct) { product in NavigationStack { ProductFormView(vm: vm, product: product) } }
    }
}

private struct ProductFormView: View {
    @ObservedObject var vm: OperationsViewModel
    let product: StoreProduct?
    @Environment(\.dismiss) private var dismiss
    @State private var sku: String
    @State private var barcode: String
    @State private var name: String
    @State private var brand: String
    @State private var unit: String
    @State private var category: StoreCategory
    @State private var cost: String
    @State private var price: String
    @State private var minimum: String
    @State private var isActive: Bool
    @State private var error = ""

    init(vm: OperationsViewModel, product: StoreProduct?) {
        self.vm = vm
        self.product = product
        _sku = State(initialValue: product?.sku ?? "")
        _barcode = State(initialValue: product?.barcode ?? "")
        _name = State(initialValue: product?.name ?? "")
        _brand = State(initialValue: product?.brand ?? "")
        _unit = State(initialValue: product?.unitName ?? "unidad")
        _category = State(initialValue: product?.category ?? .convenience)
        _cost = State(initialValue: product.map { $0.unitCostCents.moneyPlain } ?? "")
        _price = State(initialValue: product.map { $0.unitPriceCents.moneyPlain } ?? "")
        _minimum = State(initialValue: product.map { String($0.minimumStock) } ?? "0")
        _isActive = State(initialValue: product?.isActive ?? true)
    }

    var body: some View {
        Form {
            Section("Identificación") {
                TextField("SKU único", text: $sku).textInputAutocapitalization(.characters)
                TextField("Código de barras (opcional)", text: $barcode).keyboardType(.numberPad)
                TextField("Nombre", text: $name)
                TextField("Marca", text: $brand)
                TextField("Unidad de venta", text: $unit)
                Picker("Categoría", selection: $category) { ForEach(StoreCategory.allCases) { Text($0.rawValue).tag($0) } }
            }
            Section("Precio e inventario") {
                TextField("Costo por unidad · USD", text: $cost).keyboardType(.decimalPad)
                TextField("Precio por unidad · USD", text: $price).keyboardType(.decimalPad)
                TextField("Mínimo de existencias", text: $minimum).keyboardType(.numberPad)
                Toggle("Disponible para venta", isOn: $isActive)
            }
            if !error.isEmpty { Section { Text(error).foregroundStyle(DLCTheme.red) } }
            Section {
                Button(product == nil ? "Crear producto" : "Guardar cambios", action: save)
                    .frame(maxWidth: .infinity, alignment: .center).fontWeight(.semibold)
            }
        }
        .navigationTitle(product == nil ? "Nuevo producto" : "Editar producto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } } }
    }

    private func save() {
        guard let costCents = Double(cost.replacingOccurrences(of: ",", with: ".")).flatMap({ $0.isFinite && $0 >= 0 && $0 <= 500_000 ? Int(($0 * 100).rounded()) : nil }),
              let priceCents = Double(price.replacingOccurrences(of: ",", with: ".")).flatMap({ $0.isFinite && $0 > 0 && $0 <= 500_000 ? Int(($0 * 100).rounded()) : nil }),
              let minimumValue = Int(minimum), minimumValue >= 0 else {
            error = "Ingresa costo, precio y mínimo con valores válidos."
            return
        }
        if var product {
            product.sku = sku; product.barcode = barcode; product.name = name; product.brand = brand
            product.unitName = unit; product.category = category; product.unitCostCents = costCents
            product.unitPriceCents = priceCents; product.minimumStock = minimumValue; product.isActive = isActive
            error = vm.saveProduct(product) ?? ""
        } else {
            error = vm.createProduct(sku: sku, barcode: barcode, name: name, brand: brand, category: category, unitName: unit, costCents: costCents, priceCents: priceCents, minimumStock: minimumValue) ?? ""
        }
        if error.isEmpty { dismiss() }
    }
}

struct SuppliersListView: View {
    @ObservedObject var vm: OperationsViewModel
    let canEdit: Bool
    @State private var showNewSupplier = false
    @State private var editingSupplier: StoreSupplier?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                searchField("Buscar proveedor o contacto", text: $vm.searchText)
                HStack {
                    Text("Proveedores de tienda").font(.headline)
                    Spacer()
                    Text("\(vm.filteredSuppliers.count)").font(.caption).foregroundStyle(DLCTheme.muted)
                    if canEdit {
                        Button { showNewSupplier = true } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(DLCTheme.orange) }
                            .accessibilityLabel("Agregar proveedor")
                    }
                }
                ForEach(vm.filteredSuppliers) { supplier in
                    Button { if canEdit { editingSupplier = supplier } } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(supplier.name).font(.headline).foregroundStyle(DLCTheme.forest)
                                Spacer()
                                Text(supplier.isActive ? "Activo" : "Inactivo")
                                    .font(.caption2.weight(.bold)).foregroundStyle(supplier.isActive ? DLCTheme.green : DLCTheme.red)
                            }
                            Text(supplier.contactName).font(.subheadline).foregroundStyle(DLCTheme.muted)
                            HStack(spacing: 12) {
                                Label(supplier.phone.isEmpty ? "Sin teléfono" : supplier.phone, systemImage: "phone")
                                if !supplier.email.isEmpty { Label(supplier.email, systemImage: "envelope") }
                            }.font(.caption2).foregroundStyle(DLCTheme.muted)
                        }
                    }.buttonStyle(.plain).dlcCard()
                }
            }.padding(18)
        }
        .navigationTitle("Proveedores")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .sheet(isPresented: $showNewSupplier) { NavigationStack { SupplierFormView(vm: vm, supplier: nil) } }
        .sheet(item: $editingSupplier) { supplier in NavigationStack { SupplierFormView(vm: vm, supplier: supplier) } }
    }
}

private struct SupplierFormView: View {
    @ObservedObject var vm: OperationsViewModel
    let supplier: StoreSupplier?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var taxID: String
    @State private var contact: String
    @State private var phone: String
    @State private var email: String
    @State private var address: String
    @State private var scope: SupplierScope
    @State private var isActive: Bool
    @State private var error = ""

    init(vm: OperationsViewModel, supplier: StoreSupplier?) {
        self.vm = vm; self.supplier = supplier
        _name = State(initialValue: supplier?.name ?? "")
        _taxID = State(initialValue: supplier?.taxIdentifier ?? "")
        _contact = State(initialValue: supplier?.contactName ?? "")
        _phone = State(initialValue: supplier?.phone ?? "")
        _email = State(initialValue: supplier?.email ?? "")
        _address = State(initialValue: supplier?.address ?? "")
        _scope = State(initialValue: supplier?.scope ?? .store)
        _isActive = State(initialValue: supplier?.isActive ?? true)
    }

    var body: some View {
        Form {
            Section("Datos del proveedor") {
                TextField("Nombre comercial", text: $name)
                TextField("Identificador fiscal (opcional)", text: $taxID)
                TextField("Persona de contacto", text: $contact)
                TextField("Teléfono", text: $phone).keyboardType(.phonePad)
                TextField("Correo", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                TextField("Dirección", text: $address)
                Picker("Abastece", selection: $scope) { ForEach(SupplierScope.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Proveedor activo", isOn: $isActive)
            }
            if !error.isEmpty { Section { Text(error).foregroundStyle(DLCTheme.red) } }
            Section { Button(supplier == nil ? "Guardar proveedor" : "Guardar cambios", action: save).frame(maxWidth: .infinity, alignment: .center) }
        }
        .navigationTitle(supplier == nil ? "Nuevo proveedor" : "Editar proveedor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } } }
    }

    private func save() {
        if var supplier {
            supplier.name = name; supplier.taxIdentifier = taxID; supplier.contactName = contact
            supplier.phone = phone; supplier.email = email; supplier.address = address
            supplier.scope = scope; supplier.isActive = isActive
            error = vm.saveSupplier(supplier) ?? ""
        } else {
            error = vm.createSupplier(name: name, taxID: taxID, contact: contact, phone: phone, email: email, address: address, scope: scope) ?? ""
        }
        if error.isEmpty { dismiss() }
    }
}

private extension Int {
    var moneyUSD: String { (Double(self) / 100).formatted(.currency(code: "USD")) }
    var moneyPlain: String { String(format: "%.2f", Double(self) / 100) }
}

private func searchField(_ placeholder: String, text: Binding<String>) -> some View {
    HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").foregroundStyle(DLCTheme.muted)
        TextField(placeholder, text: text).textInputAutocapitalization(.never).autocorrectionDisabled()
        if !text.wrappedValue.isEmpty {
            Button { text.wrappedValue = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DLCTheme.muted) }
                .accessibilityLabel("Limpiar búsqueda")
        }
    }
    .padding(12).background(DLCTheme.surface)
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(DLCTheme.border))
    .clipShape(RoundedRectangle(cornerRadius: 12))
}

struct StoreInventoryView: View {
    @ObservedObject var vm: OperationsViewModel
    @State private var showReceipt = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if vm.fixedBranchID == nil {
                    Picker("Sucursal", selection: $vm.selectedBranchID) {
                        Text("Toda la red").tag(UUID?.none)
                        ForEach(vm.activeBranches) { branch in Text(branch.name).tag(Optional(branch.id)) }
                    }
                    .pickerStyle(.menu).padding(12).background(DLCTheme.surface).clipShape(RoundedRectangle(cornerRadius: 11))
                }
                searchField("Buscar producto, SKU o sucursal", text: $vm.searchText)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Existencias por producto").font(.headline)
                        Text("Las existencias disponibles excluyen lotes vencidos.")
                            .font(.caption).foregroundStyle(DLCTheme.muted)
                    }
                    Spacer()
                    if let branchID = vm.fixedBranchID ?? vm.selectedBranchID,
                       vm.repository.branch(withID: branchID)?.isActive == true {
                        Button { showReceipt = true } label: {
                            Label("Recibir", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent).tint(DLCTheme.orange)
                    }
                }
                if vm.scopedBranches.isEmpty {
                    ContentUnavailableView("Selecciona una sucursal", systemImage: "building.2", description: Text("Elige una sucursal para registrar una recepción."))
                        .padding(.top, 20)
                } else {
                    ForEach(vm.scopedBranches) { branch in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(branch.name).font(.headline)
                            ForEach(vm.repository.products.filter { $0.isActive }.filter { productMatches($0, query: vm.searchText) }) { product in
                                NavigationLink {
                                    StoreLotListView(vm: vm, branchID: branch.id, product: product)
                                } label: {
                                    let stock = vm.stock(for: product, branchID: branch.id)
                                    HStack(spacing: 9) {
                                        Image(systemName: "shippingbox.fill").foregroundStyle(stock <= product.minimumStock ? DLCTheme.red : DLCTheme.orange)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(product.name).font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.forest)
                                            Text("\(product.sku) · \(vm.lotCount(branchID: branch.id, productID: product.id)) lotes · mínimo \(product.minimumStock)")
                                                .font(.caption2).foregroundStyle(DLCTheme.muted)
                                        }
                                        Spacer()
                                        Text("\(stock) \(product.unitName)").font(.subheadline.bold())
                                            .foregroundStyle(stock <= product.minimumStock ? DLCTheme.red : DLCTheme.forest)
                                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(DLCTheme.muted)
                                    }
                                    .padding(12).background(DLCTheme.background).clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .dlcCard()
                    }
                }
                if !vm.expiredLots.isEmpty {
                    Label("\(vm.expiredLots.count) lotes vencidos · retíralos con un ajuste documentado.", systemImage: "calendar.badge.exclamationmark")
                        .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.red).dlcCard(color: DLCTheme.redBG)
                }
            }
            .padding(18)
        }
        .navigationTitle("Inventario")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .sheet(isPresented: $showReceipt) {
            if let branchID = vm.fixedBranchID ?? vm.selectedBranchID {
                NavigationStack { ReceiveStoreLotView(vm: vm, branchID: branchID) }
            }
        }
    }

    private func productMatches(_ product: StoreProduct, query: String) -> Bool {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty || [product.name, product.sku, product.barcode, product.brand]
            .contains { $0.localizedCaseInsensitiveContains(clean) }
    }
}

private struct StoreLotListView: View {
    @ObservedObject var vm: OperationsViewModel
    let branchID: UUID
    let product: StoreProduct
    @State private var selectedLot: StoreLot?

    private var lots: [StoreLot] { vm.repository.storeLots(branchID: branchID, productID: product.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(product.name).font(.title2.bold())
                    Text("\(product.sku) · Existencia vendible: \(vm.stock(for: product, branchID: branchID)) \(product.unitName)")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading).dlcCard(color: DLCTheme.orangeBG)
                Text("Lotes").font(.headline)
                if lots.isEmpty {
                    ContentUnavailableView("Sin lotes", systemImage: "shippingbox", description: Text("Registra una recepción para añadir inventario."))
                } else {
                    ForEach(lots) { lot in
                        Button { selectedLot = lot } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(lot.lotCode).font(.headline).foregroundStyle(DLCTheme.forest)
                                    Spacer()
                                    Text("\(lot.remainingQuantity) \(product.unitName)").font(.subheadline.bold())
                                }
                                HStack {
                                    Text("Recibido \(lot.receivedAt.formatted(date: .abbreviated, time: .omitted))")
                                    Spacer()
                                    Text(lot.expiresAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Sin vencimiento")
                                }.font(.caption).foregroundStyle(DLCTheme.muted)
                                HStack {
                                    Text("Costo \(lot.unitCostCents.moneyUSD)")
                                    Spacer()
                                    Text(lot.isExpired() ? "Vencido" : "Vigente")
                                        .fontWeight(.semibold).foregroundStyle(lot.isExpired() ? DLCTheme.red : DLCTheme.green)
                                }.font(.caption2).foregroundStyle(DLCTheme.muted)
                            }
                        }
                        .buttonStyle(.plain).dlcCard()
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Kardex").font(.headline)
                    ForEach(vm.repository.stockMovements.filter { $0.branchID == branchID && $0.productID == product.id }.sorted { $0.recordedAt > $1.recordedAt }.prefix(20)) { movement in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(movement.kind.rawValue).font(.subheadline.weight(.semibold))
                                Text("\(movement.reason) · \(movement.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2).foregroundStyle(DLCTheme.muted)
                            }
                            Spacer()
                            Text(movement.quantityDelta > 0 ? "+\(movement.quantityDelta)" : "\(movement.quantityDelta)")
                                .font(.subheadline.bold()).foregroundStyle(movement.quantityDelta >= 0 ? DLCTheme.green : DLCTheme.red)
                        }
                        if movement.id != vm.repository.stockMovements.first?.id { Divider() }
                    }
                }
                .dlcCard()
            }.padding(18)
        }
        .navigationTitle("Lotes")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .sheet(item: $selectedLot) { lot in NavigationStack { StoreLotAdjustmentView(vm: vm, lot: lot, product: product) } }
    }
}

private struct ReceiveStoreLotView: View {
    @ObservedObject var vm: OperationsViewModel
    let branchID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var productID: UUID?
    @State private var supplierID: UUID?
    @State private var lotCode = ""
    @State private var reference = ""
    @State private var quantity = ""
    @State private var unitCost = ""
    @State private var receivedAt = Date()
    @State private var hasExpiry = true
    @State private var expiresAt = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var error = ""

    private var availableProducts: [StoreProduct] { vm.repository.products.filter(\.isActive) }
    private var availableSuppliers: [StoreSupplier] { vm.repository.suppliers.filter { $0.isActive && $0.supportsStore } }

    var body: some View {
        Form {
            Section("Recepción") {
                Picker("Producto", selection: $productID) {
                    Text("Selecciona producto").tag(UUID?.none)
                    ForEach(availableProducts) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Proveedor", selection: $supplierID) {
                    Text("Selecciona proveedor").tag(UUID?.none)
                    ForEach(availableSuppliers) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField("Código de lote", text: $lotCode).textInputAutocapitalization(.characters)
                TextField("Factura, nota o folio", text: $reference).textInputAutocapitalization(.characters)
                TextField("Cantidad recibida", text: $quantity).keyboardType(.numberPad)
                TextField("Costo unitario · USD", text: $unitCost).keyboardType(.decimalPad)
                DatePicker("Fecha de recepción", selection: $receivedAt, displayedComponents: .date)
            }
            Section("Vencimiento") {
                Toggle("El producto vence", isOn: $hasExpiry)
                if hasExpiry { DatePicker("Vence el", selection: $expiresAt, in: receivedAt..., displayedComponents: .date) }
            }
            if !error.isEmpty { Section { Text(error).foregroundStyle(DLCTheme.red) } }
            Section {
                Button("Registrar recepción", action: save).frame(maxWidth: .infinity, alignment: .center).fontWeight(.semibold)
            }
        }
        .navigationTitle("Nuevo lote")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
        .onAppear {
            if productID == nil { productID = availableProducts.first?.id }
            if supplierID == nil { supplierID = availableSuppliers.first?.id }
        }
    }

    private func save() {
        guard let productID, let supplierID, let count = Int(quantity), count > 0,
              let cost = Double(unitCost.replacingOccurrences(of: ",", with: ".")),
              cost.isFinite, cost >= 0, cost <= 500_000 else {
            error = "Selecciona producto y proveedor; completa cantidad y costo válidos."
            return
        }
        error = vm.receiveLot(
            branchID: branchID, productID: productID, supplierID: supplierID,
            lotCode: lotCode, reference: reference, quantity: count,
            costCents: Int((cost * 100).rounded()), receivedAt: receivedAt,
            expiresAt: hasExpiry ? expiresAt : nil
        ) ?? ""
        if error.isEmpty { dismiss() }
    }
}

private struct StoreLotAdjustmentView: View {
    @ObservedObject var vm: OperationsViewModel
    let lot: StoreLot
    let product: StoreProduct
    @Environment(\.dismiss) private var dismiss
    @State private var kind: StockMovementKind = .adjustment
    @State private var quantity = ""
    @State private var direction = -1
    @State private var reason = ""
    @State private var error = ""

    var body: some View {
        Form {
            Section("Lote \(lot.lotCode)") {
                LabeledContent("Producto", value: product.name)
                LabeledContent("Existencia actual", value: "\(lot.remainingQuantity) \(product.unitName)")
                LabeledContent("Vencimiento", value: lot.expiresAt?.formatted(date: .abbreviated, time: .omitted) ?? "Sin vencimiento")
            }
            Section("Movimiento") {
                Picker("Motivo", selection: $kind) {
                    Text(StockMovementKind.adjustment.rawValue).tag(StockMovementKind.adjustment)
                    Text(StockMovementKind.damaged.rawValue).tag(StockMovementKind.damaged)
                    Text(StockMovementKind.expired.rawValue).tag(StockMovementKind.expired)
                }
                if kind == .adjustment {
                    Picker("Operación", selection: $direction) {
                        Text("Retirar").tag(-1)
                        Text("Agregar").tag(1)
                    }.pickerStyle(.segmented)
                }
                TextField("Cantidad", text: $quantity).keyboardType(.numberPad)
                TextField("Motivo y observación", text: $reason, axis: .vertical).lineLimit(2...4)
            }
            if !error.isEmpty { Section { Text(error).foregroundStyle(DLCTheme.red) } }
            Section {
                Button("Guardar movimiento", action: save).frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Ajuste de lote")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
    }

    private func save() {
        guard let count = Int(quantity), count > 0, count <= 100_000 else { error = "Ingresa una cantidad entera positiva."; return }
        let delta = kind == .adjustment ? count * direction : -count
        error = vm.adjustLot(id: lot.id, delta: delta, kind: kind, reason: reason) ?? ""
        if error.isEmpty { dismiss() }
    }
}

struct StorePOSView: View {
    @ObservedObject var vm: OperationsViewModel
    @State private var cart: [UUID: Int] = [:]
    @State private var payment: PaymentMethod = .cash
    @State private var tendered = ""
    @State private var selectedCategory: StoreCategory?
    @State private var error = ""
    @State private var completedSale: StoreSale?

    private var branchID: UUID? { vm.fixedBranchID ?? vm.selectedBranchID }
    private var cartLines: [StoreProduct] {
        vm.repository.products.filter { cart[$0.id, default: 0] > 0 }.sorted { $0.name < $1.name }
    }
    private var totalCents: Int {
        cartLines.reduce(0) { $0 + $1.unitPriceCents * cart[$1.id, default: 0] }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let branchID {
                    Text(vm.repository.branch(withID: branchID)?.name ?? "Sucursal")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.muted)
                }
                searchField("Buscar productos disponibles", text: $vm.searchText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        categoryChip(nil, title: "Todos")
                        ForEach(StoreCategory.allCases) { category in categoryChip(category, title: category.rawValue) }
                    }
                }
                VStack(spacing: 9) {
                    ForEach(vm.filteredProducts.filter { selectedCategory == nil || $0.category == selectedCategory }) { product in
                        let stock = branchID.map { vm.stock(for: product, branchID: $0) } ?? 0
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.name).font(.subheadline.weight(.semibold))
                                Text("\(product.unitPriceCents.moneyUSD) · \(stock) \(product.unitName) disponibles")
                                    .font(.caption).foregroundStyle(DLCTheme.muted)
                            }
                            Spacer()
                            Button { cart[product.id, default: 0] = max(0, cart[product.id, default: 0] - 1) }
                                label: { Image(systemName: "minus.circle").font(.title3) }
                                .disabled(cart[product.id, default: 0] == 0)
                            Text("\(cart[product.id, default: 0])").font(.subheadline.monospacedDigit().bold()).frame(minWidth: 22)
                            Button { cart[product.id, default: 0] += 1 }
                                label: { Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(DLCTheme.orange) }
                                .disabled(stock <= cart[product.id, default: 0])
                        }
                        .padding(12).background(DLCTheme.surface).clipShape(RoundedRectangle(cornerRadius: 13))
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("Total").font(.headline); Spacer(); Text(totalCents.moneyUSD).font(.title2.bold()) }
                    Picker("Pago", selection: $payment) { ForEach(PaymentMethod.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                    if payment == .cash {
                        TextField("Efectivo recibido · USD", text: $tendered).keyboardType(.decimalPad)
                            .padding(12).background(DLCTheme.background).clipShape(RoundedRectangle(cornerRadius: 11))
                        if let cashCents = parseCents(tendered), cashCents >= totalCents {
                            Text("Cambio: \((cashCents - totalCents).moneyUSD)").font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.green)
                        }
                    }
                    if !error.isEmpty { Text(error).font(.caption).foregroundStyle(DLCTheme.red) }
                    Button(action: checkout) {
                        Label("Cobrar \(totalCents.moneyUSD)", systemImage: "creditcard.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(totalCents <= 0 || branchID == nil)
                }
                .dlcCard()
            }
            .padding(18)
        }
        .navigationTitle("Punto de venta")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .sheet(item: $completedSale) { sale in NavigationStack { StoreSaleDetailView(vm: vm, sale: sale) } }
    }

    private func categoryChip(_ category: StoreCategory?, title: String) -> some View {
        Button { selectedCategory = category } label: {
            Text(title).font(.caption.weight(.semibold))
                .foregroundStyle(selectedCategory == category ? Color.white : DLCTheme.forest)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(selectedCategory == category ? DLCTheme.forest : DLCTheme.surface)
                .clipShape(Capsule())
        }.buttonStyle(.plain)
    }

    private func checkout() {
        guard let branchID else { error = "No hay una sucursal seleccionada."; return }
        let received = payment == .cash ? parseCents(tendered) ?? -1 : totalCents
        if let sale = vm.checkout(branchID: branchID, quantities: cart, payment: payment, tenderedCents: received) {
            error = ""
            cart.removeAll()
            tendered = ""
            completedSale = sale
        } else {
            error = vm.lastError
        }
    }
}

struct StoreSalesHistoryView: View {
    @ObservedObject var vm: OperationsViewModel
    @State private var range: HistoryRange = .last7Days
    @State private var query = ""
    @State private var selectedSale: StoreSale?

    private var sales: [StoreSale] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(range.dayCount - 1), to: Calendar.current.startOfDay(for: end)) ?? end
        return vm.sales(from: start, through: end, includeVoided: true).filter { sale in
            guard !query.isEmpty else { return true }
            return sale.folio.localizedCaseInsensitiveContains(query)
                || sale.paymentMethod.rawValue.localizedCaseInsensitiveContains(query)
                || sale.voidReason.localizedCaseInsensitiveContains(query)
                || sale.lines.contains(where: { $0.productName.localizedCaseInsensitiveContains(query) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                Picker("Periodo", selection: $range) { ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                searchField("Filtrar folio, producto o pago", text: $query)
                HStack {
                    Text("Tickets").font(.headline)
                    Spacer()
                    Text("\(sales.count) tickets · \(sales.filter { $0.status == .completed }.reduce(0) { $0 + $1.totalCents }.moneyUSD) vendidos")
                        .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.muted)
                }
                if sales.isEmpty {
                    ContentUnavailableView("Sin ventas", systemImage: "receipt", description: Text("No hay tickets para el periodo y filtro seleccionados."))
                        .padding(.top, 20)
                } else {
                    ForEach(sales) { sale in
                        Button { selectedSale = sale } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sale.folio).font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.forest)
                                    Text("\(sale.soldAt.formatted(date: .abbreviated, time: .shortened)) · \(sale.paymentMethod.rawValue) · \(sale.itemCount) artículos")
                                        .font(.caption).foregroundStyle(DLCTheme.muted)
                                    if sale.status == .voided {
                                        Text("ANULADA · \(sale.voidReason)")
                                            .font(.caption2.weight(.bold)).foregroundStyle(DLCTheme.red).lineLimit(2)
                                    }
                                }
                                Spacer()
                                Text(sale.totalCents.moneyUSD).font(.subheadline.bold())
                                    .foregroundStyle(sale.status == .completed ? DLCTheme.forest : DLCTheme.muted)
                            }
                        }.buttonStyle(.plain).dlcCard()
                    }
                }
            }.padding(18)
        }
        .navigationTitle("Historial de tienda")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .sheet(item: $selectedSale) { sale in NavigationStack { StoreSaleDetailView(vm: vm, sale: sale) } }
    }
}

private struct StoreSaleDetailView: View {
    @ObservedObject var vm: OperationsViewModel
    let sale: StoreSale
    @Environment(\.dismiss) private var dismiss
    @State private var showingVoidForm = false

    var body: some View {
        List {
            Section("Ticket \(sale.folio)") {
                LabeledContent("Fecha", value: sale.soldAt.formatted(date: .long, time: .shortened))
                LabeledContent("Sucursal", value: vm.repository.branch(withID: sale.branchID)?.name ?? "Sucursal archivada")
                LabeledContent("Pago", value: sale.paymentMethod.rawValue)
                LabeledContent("Estado", value: sale.status.rawValue)
                if sale.paymentMethod == .cash {
                    LabeledContent("Recibido", value: sale.tenderedCents.moneyUSD)
                    LabeledContent("Cambio", value: sale.changeCents.moneyUSD)
                }
            }
            Section("Detalle") {
                ForEach(sale.lines) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(line.productName).fontWeight(.semibold); Spacer(); Text(line.lineTotalCents.moneyUSD).fontWeight(.bold) }
                        Text("\(line.quantity) × \(line.unitPriceCents.moneyUSD) · costo \(line.unitCostCents.moneyUSD)")
                            .font(.caption).foregroundStyle(DLCTheme.muted)
                    }
                }
            }
            Section {
                LabeledContent("Total", value: sale.totalCents.moneyUSD).font(.headline)
            }
            if sale.status == .voided {
                Section("Anulación") {
                    Text(sale.voidReason).foregroundStyle(DLCTheme.red)
                    Text("La anulación repuso las unidades a sus lotes. La devolución del pago se registra fuera de esta demostración.")
                        .font(.caption).foregroundStyle(DLCTheme.muted)
                }
            } else if vm.actor.role == .branchManager {
                Section {
                    Button("Anular venta y reponer inventario", role: .destructive) {
                        showingVoidForm = true
                    }
                } footer: {
                    Text("La anulación conserva el ticket y registra una salida de retorno en el kardex.")
                }
            }
        }
        .navigationTitle("Detalle de venta")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingVoidForm) {
            NavigationStack {
                VoidStoreSaleView(vm: vm, sale: sale) { dismiss() }
            }
        }
    }
}

private struct VoidStoreSaleView: View {
    @ObservedObject var vm: OperationsViewModel
    let sale: StoreSale
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var error = ""

    var body: some View {
        Form {
            Section("Ticket \(sale.folio)") {
                Text("La aplicación marcará el ticket como anulado y repondrá los productos en los lotes de origen.")
                TextField("Motivo de anulación", text: $reason, axis: .vertical)
                    .lineLimit(3...6)
            }
            if !error.isEmpty { Section { Text(error).foregroundStyle(DLCTheme.red) } }
            Section {
                Button("Confirmar anulación", role: .destructive, action: save)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Anular venta")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
    }

    private func save() {
        if let message = vm.voidSale(sale, reason: reason) {
            error = message
            return
        }
        dismiss()
        onComplete()
    }
}

private func parseCents(_ value: String) -> Int? {
    guard let amount = Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
          amount.isFinite, amount >= 0, amount <= 500_000 else { return nil }
    return Int((amount * 100).rounded())
}

struct StaffManagementView: View {
    @ObservedObject var vm: OperationsViewModel
    @State private var showingSchedule = false
    @State private var addingMember = false
    @State private var editingMember: StaffMember?
    @State private var mode = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if vm.fixedBranchID == nil {
                    Picker("Sucursal", selection: $vm.selectedBranchID) {
                        Text("Toda la red").tag(UUID?.none)
                        ForEach(vm.activeBranches) { Text($0.name).tag(Optional($0.id)) }
                    }.pickerStyle(.menu).padding(11).background(DLCTheme.surface).clipShape(RoundedRectangle(cornerRadius: 11))
                }
                Picker("Sección", selection: $mode) {
                    Text("Personal").tag(0)
                    Text("Turnos").tag(1)
                }.pickerStyle(.segmented)

                if mode == 0 {
                    HStack {
                        Text("Colaboradores").font(.headline)
                        Spacer()
                        Text("\(vm.filteredStaff.count)").font(.caption).foregroundStyle(DLCTheme.muted)
                        Button { addingMember = true } label: { Image(systemName: "person.badge.plus").font(.title2).foregroundStyle(DLCTheme.orange) }
                            .accessibilityLabel("Agregar colaborador")
                    }
                    searchField("Buscar por nombre, código o cargo", text: $vm.searchText)
                    ForEach(vm.filteredStaff) { member in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(member.fullName).font(.headline)
                                    Text("\(member.employeeCode) · \(member.position)").font(.caption).foregroundStyle(DLCTheme.muted)
                                }
                                Spacer()
                                Text(member.status.rawValue).font(.caption.weight(.bold))
                                    .foregroundStyle(member.status == .active ? DLCTheme.green : DLCTheme.yellow)
                            }
                            HStack {
                                if vm.fixedBranchID == nil {
                                    Text(vm.repository.branch(withID: member.branchID)?.name ?? "Sucursal archivada")
                                }
                                if !member.phone.isEmpty { Label(member.phone, systemImage: "phone") }
                                Spacer()
                                Button("Editar") { editingMember = member }.font(.caption.weight(.semibold))
                            }.font(.caption2).foregroundStyle(DLCTheme.muted)
                            Menu {
                                ForEach(StaffStatus.allCases) { status in
                                    Button(status.rawValue) {
                                        _ = vm.setStaffStatus(member, status: status)
                                    }
                                }
                            } label: {
                                Label("Cambiar estado", systemImage: "person.crop.circle.badge.check")
                                    .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.orange)
                            }
                        }.dlcCard()
                    }
                    if vm.filteredStaff.isEmpty {
                        ContentUnavailableView("Sin colaboradores", systemImage: "person.2", description: Text("Agrega personal o cambia la búsqueda."))
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Turnos semanales").font(.headline)
                            Text("Una asignación por persona y día; editar retirando la anterior.")
                                .font(.caption).foregroundStyle(DLCTheme.muted)
                        }
                        Spacer()
                        Button { showingSchedule = true } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(DLCTheme.orange) }
                            .accessibilityLabel("Asignar turno")
                    }
                    ForEach(vm.repository.shiftAssignments.filter { assignment in
                        vm.scopedBranches.contains(where: { $0.id == assignment.branchID })
                    }.sorted { $0.weekday == $1.weekday ? $0.shift.rawValue < $1.shift.rawValue : $0.weekday < $1.weekday }) { assignment in
                        let member = vm.repository.staff.first(where: { $0.id == assignment.employeeID })
                        HStack(spacing: 10) {
                            Image(systemName: "calendar").foregroundStyle(DLCTheme.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(member?.fullName ?? "Colaborador").font(.subheadline.weight(.semibold))
                                Text("\(weekdayName(assignment.weekday)) · \(assignment.shift.rawValue) · \(assignment.shift.timeRange)")
                                    .font(.caption).foregroundStyle(DLCTheme.muted)
                                if vm.fixedBranchID == nil {
                                    Text(vm.repository.branch(withID: assignment.branchID)?.name ?? "")
                                        .font(.caption2).foregroundStyle(DLCTheme.muted)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) { _ = vm.removeShift(assignment) } label: { Image(systemName: "trash") }
                                .accessibilityLabel("Eliminar turno")
                        }.dlcCard()
                    }
                }
            }.padding(18)
        }
        .navigationTitle("Personal y turnos")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .sheet(isPresented: $addingMember) { NavigationStack { StaffFormView(vm: vm, member: nil) } }
        .sheet(item: $editingMember) { member in NavigationStack { StaffFormView(vm: vm, member: member) } }
        .sheet(isPresented: $showingSchedule) { NavigationStack { ShiftAssignmentFormView(vm: vm) } }
    }
}

private struct StaffFormView: View {
    @ObservedObject var vm: OperationsViewModel
    let member: StaffMember?
    @Environment(\.dismiss) private var dismiss
    @State private var branchID: UUID?
    @State private var code: String
    @State private var name: String
    @State private var position: String
    @State private var phone: String
    @State private var email: String
    @State private var hiredAt: Date
    @State private var status: StaffStatus
    @State private var error = ""

    init(vm: OperationsViewModel, member: StaffMember?) {
        self.vm = vm; self.member = member
        _branchID = State(initialValue: member?.branchID ?? vm.fixedBranchID ?? vm.activeBranches.first?.id)
        _code = State(initialValue: member?.employeeCode ?? "")
        _name = State(initialValue: member?.fullName ?? "")
        _position = State(initialValue: member?.position ?? "")
        _phone = State(initialValue: member?.phone ?? "")
        _email = State(initialValue: member?.email ?? "")
        _hiredAt = State(initialValue: member?.hiredAt ?? Date())
        _status = State(initialValue: member?.status ?? .active)
    }

    var body: some View {
        Form {
            if vm.fixedBranchID == nil {
                Section("Sucursal") {
                    Picker("Asignación", selection: $branchID) {
                        Text("Selecciona sucursal").tag(UUID?.none)
                        ForEach(vm.activeBranches) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            Section("Perfil") {
                TextField("Código de empleado", text: $code).textInputAutocapitalization(.characters)
                TextField("Nombre completo", text: $name)
                TextField("Cargo", text: $position)
                TextField("Teléfono", text: $phone).keyboardType(.phonePad)
                TextField("Correo (opcional)", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                DatePicker("Fecha de ingreso", selection: $hiredAt, displayedComponents: .date)
                if member != nil {
                    Picker("Estado", selection: $status) { ForEach(StaffStatus.allCases) { Text($0.rawValue).tag($0) } }
                }
            }
            if !error.isEmpty { Section { Text(error).foregroundStyle(DLCTheme.red) } }
            Section { Button(member == nil ? "Guardar colaborador" : "Guardar cambios", action: save).frame(maxWidth: .infinity, alignment: .center) }
        }
        .navigationTitle(member == nil ? "Nuevo colaborador" : "Editar colaborador")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
    }

    private func save() {
        guard let branchID else { error = "Selecciona una sucursal."; return }
        if var member {
            member.employeeCode = code; member.fullName = name; member.position = position
            member.phone = phone; member.email = email; member.hiredAt = hiredAt; member.status = status
            error = vm.saveStaff(member) ?? ""
        } else {
            error = vm.createStaff(branchID: branchID, code: code, name: name, position: position, phone: phone, email: email, hiredAt: hiredAt) ?? ""
        }
        if error.isEmpty { dismiss() }
    }
}

private struct ShiftAssignmentFormView: View {
    @ObservedObject var vm: OperationsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var branchID: UUID?
    @State private var employeeID: UUID?
    @State private var weekday = Calendar.current.component(.weekday, from: Date())
    @State private var shift: WorkShift = .morning
    @State private var error = ""

    init(vm: OperationsViewModel) {
        self.vm = vm
        _branchID = State(initialValue: vm.fixedBranchID ?? vm.selectedBranchID ?? vm.activeBranches.first?.id)
    }

    private var activeMembers: [StaffMember] {
        vm.repository.staff.filter { $0.status == .active && $0.branchID == branchID }
    }

    var body: some View {
        Form {
            if vm.fixedBranchID == nil {
                Section("Sucursal") {
                    Picker("Sucursal", selection: $branchID) {
                        Text("Selecciona sucursal").tag(UUID?.none)
                        ForEach(vm.activeBranches) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .onChange(of: branchID) { _, _ in employeeID = activeMembers.first?.id }
                }
            }
            Section("Asignación") {
                Picker("Colaborador", selection: $employeeID) {
                    Text("Selecciona colaborador").tag(UUID?.none)
                    ForEach(activeMembers) { Text($0.fullName).tag(Optional($0.id)) }
                }
                Picker("Día", selection: $weekday) {
                    ForEach(1...7, id: \.self) { day in Text(weekdayName(day)).tag(day) }
                }
                Picker("Turno", selection: $shift) {
                    ForEach(WorkShift.allCases) { Text("\($0.rawValue) · \($0.timeRange)").tag($0) }
                }
            }
            if !error.isEmpty { Section { Text(error).foregroundStyle(DLCTheme.red) } }
            Section { Button("Guardar turno", action: save).frame(maxWidth: .infinity, alignment: .center) }
        }
        .navigationTitle("Asignar turno")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
        .onAppear { if employeeID == nil { employeeID = activeMembers.first?.id } }
    }

    private func save() {
        guard let branchID, let employeeID else { error = "Selecciona sucursal y colaborador."; return }
        error = vm.assignShift(branchID: branchID, employeeID: employeeID, weekday: weekday, shift: shift) ?? ""
        if error.isEmpty { dismiss() }
    }
}

private func weekdayName(_ value: Int) -> String {
    switch value {
    case 1: "Domingo"
    case 2: "Lunes"
    case 3: "Martes"
    case 4: "Miércoles"
    case 5: "Jueves"
    case 6: "Viernes"
    case 7: "Sábado"
    default: "Día"
    }
}

struct EquipmentMaintenanceView: View {
    @ObservedObject var vm: OperationsViewModel
    @State private var newEquipment = false
    @State private var selectedAsset: StationEquipment?
    @State private var editingAsset: StationEquipment?
    @State private var selectedOrder: MaintenanceOrder?
    @State private var showingStatusAlert = false
    @State private var statusMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if vm.fixedBranchID == nil {
                    Picker("Sucursal", selection: $vm.selectedBranchID) {
                        Text("Toda la red").tag(UUID?.none)
                        ForEach(vm.activeBranches) { Text($0.name).tag(Optional($0.id)) }
                    }.pickerStyle(.menu).padding(11).background(DLCTheme.surface).clipShape(RoundedRectangle(cornerRadius: 11))
                }
                searchField("Buscar activo u orden", text: $vm.searchText)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Activos de estación").font(.headline)
                        Text("Se conservan las seis bombas y los tanques base.").font(.caption).foregroundStyle(DLCTheme.muted)
                    }
                    Spacer()
                    Button { newEquipment = true } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(DLCTheme.orange) }
                        .accessibilityLabel("Agregar activo")
                }
                ForEach(vm.filteredEquipment) { asset in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(asset.name).font(.headline)
                                Text("\(asset.assetCode) · \(asset.category.rawValue)")
                                    .font(.caption).foregroundStyle(DLCTheme.muted)
                            }
                            Spacer()
                            Text(asset.status.rawValue).font(.caption.weight(.bold))
                                .foregroundStyle(asset.status == .operational ? DLCTheme.green : DLCTheme.red)
                        }
                        HStack {
                            if vm.fixedBranchID == nil { Text(vm.repository.branch(withID: asset.branchID)?.name ?? "") }
                            Spacer()
                            Button("Editar") { editingAsset = asset }
                                .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.forest)
                            Button("Orden de trabajo") { selectedAsset = asset }
                                .font(.caption.weight(.semibold)).foregroundStyle(DLCTheme.orange)
                            Menu("Estado") {
                                ForEach(EquipmentStatus.allCases) { status in
                                    Button(status.rawValue) {
                                        if let message = vm.setEquipmentStatus(asset, status: status) {
                                            statusMessage = message
                                            showingStatusAlert = true
                                        }
                                    }
                                }
                            }.font(.caption)
                        }.font(.caption2).foregroundStyle(DLCTheme.muted)
                    }.dlcCard()
                }
                HStack {
                    Text("Mantenimiento").font(.headline)
                    Spacer()
                    Text("\(vm.filteredMaintenanceOrders.count) órdenes").font(.caption).foregroundStyle(DLCTheme.muted)
                }
                ForEach(vm.filteredMaintenanceOrders) { order in
                    Button { selectedOrder = order } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(order.title).font(.subheadline.weight(.semibold)).foregroundStyle(DLCTheme.forest)
                                Spacer()
                                Text(order.priority.rawValue).font(.caption.weight(.bold))
                                    .foregroundStyle(order.priority == .urgent || order.priority == .high ? DLCTheme.red : DLCTheme.yellow)
                            }
                            Text("\(vm.repository.equipment.first(where: { $0.id == order.equipmentID })?.name ?? "Activo") · \(order.status.rawValue)")
                                .font(.caption).foregroundStyle(DLCTheme.muted)
                            Text(order.openedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2).foregroundStyle(DLCTheme.muted)
                        }
                    }.buttonStyle(.plain).dlcCard()
                }
            }.padding(18)
        }
        .navigationTitle("Activos y mantenimiento")
        .navigationBarTitleDisplayMode(.inline)
        .dlcScreen()
        .sheet(isPresented: $newEquipment) { NavigationStack { EquipmentFormView(vm: vm) } }
        .sheet(item: $selectedAsset) { asset in NavigationStack { MaintenanceOrderFormView(vm: vm, asset: asset) } }
        .sheet(item: $editingAsset) { asset in NavigationStack { EquipmentDetailsFormView(vm: vm, asset: asset) } }
        .sheet(item: $selectedOrder) { order in NavigationStack { MaintenanceOrderEditView(vm: vm, order: order) } }
        .alert("No se pudo actualizar el activo", isPresented: $showingStatusAlert) {
            Button("Cerrar", role: .cancel) { }
        } message: {
            Text(statusMessage)
        }
    }
}

private struct EquipmentFormView: View {
    @ObservedObject var vm: OperationsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var branchID: UUID?
    @State private var code = ""
    @State private var name = ""
    @State private var serial = ""
    @State private var category: EquipmentCategory = .refrigeration
    @State private var error = ""

    init(vm: OperationsViewModel) {
        self.vm = vm
        _branchID = State(initialValue: vm.fixedBranchID ?? vm.selectedBranchID ?? vm.activeBranches.first?.id)
    }

    var body: some View {
        Form {
            if vm.fixedBranchID == nil {
                Section("Sucursal") {
                    Picker("Sucursal", selection: $branchID) {
                        Text("Selecciona sucursal").tag(UUID?.none)
                        ForEach(vm.activeBranches) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            Section("Activo") {
                TextField("Código", text: $code).textInputAutocapitalization(.characters)
                TextField("Nombre", text: $name)
                TextField("Número de serie", text: $serial)
                Picker("Categoría", selection: $category) {
                    ForEach(EquipmentCategory.allCases.filter { $0 != .pump && $0 != .tank }) { Text($0.rawValue).tag($0) }
                }
            }
            if !error.isEmpty { Section { Text(error).foregroundStyle(DLCTheme.red) } }
            Section { Button("Guardar activo", action: save).frame(maxWidth: .infinity, alignment: .center) }
        }
        .navigationTitle("Nuevo activo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
    }

    private func save() {
        guard let branchID else { error = "Selecciona una sucursal."; return }
        error = vm.createEquipment(branchID: branchID, code: code, name: name, category: category, serial: serial) ?? ""
        if error.isEmpty { dismiss() }
    }
}

private struct EquipmentDetailsFormView: View {
    @ObservedObject var vm: OperationsViewModel
    let asset: StationEquipment
    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var name: String
    @State private var serial: String
    @State private var error = ""

    init(vm: OperationsViewModel, asset: StationEquipment) {
        self.vm = vm
        self.asset = asset
        _code = State(initialValue: asset.assetCode)
        _name = State(initialValue: asset.name)
        _serial = State(initialValue: asset.serialNumber)
    }

    var body: some View {
        Form {
            Section("Ficha técnica") {
                TextField("Código de activo", text: $code).textInputAutocapitalization(.characters)
                TextField("Nombre", text: $name)
                TextField("Número de serie", text: $serial)
                LabeledContent("Categoría", value: asset.category.rawValue)
                LabeledContent("Estado", value: asset.status.rawValue)
            }
            if !error.isEmpty { Section { Text(error).foregroundStyle(DLCTheme.red) } }
            Section {
                Button("Guardar cambios", action: save).frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Editar activo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
    }

    private func save() {
        error = vm.saveEquipment(asset, assetCode: code, name: name, serialNumber: serial) ?? ""
        if error.isEmpty { dismiss() }
    }
}

private struct MaintenanceOrderFormView: View {
    @ObservedObject var vm: OperationsViewModel
    let asset: StationEquipment
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var priority: MaintenancePriority = .normal
    @State private var provider = ""
    @State private var error = ""

    var body: some View {
        Form {
            Section("Activo") {
                LabeledContent("Nombre", value: asset.name)
                LabeledContent("Código", value: asset.assetCode)
            }
            Section("Orden de trabajo") {
                TextField("Título", text: $title)
                TextField("Descripción del problema", text: $description, axis: .vertical).lineLimit(3...6)
                Picker("Prioridad", selection: $priority) { ForEach(MaintenancePriority.allCases) { Text($0.rawValue).tag($0) } }
                TextField("Técnico o proveedor (opcional)", text: $provider)
            }
            if !error.isEmpty { Section { Text(error).foregroundStyle(DLCTheme.red) } }
            Section { Button("Abrir orden", action: save).frame(maxWidth: .infinity, alignment: .center) }
        }
        .navigationTitle("Nueva orden")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
    }

    private func save() {
        error = vm.openMaintenance(branchID: asset.branchID, equipmentID: asset.id, title: title, description: description, priority: priority, provider: provider) ?? ""
        if error.isEmpty { dismiss() }
    }
}

private struct MaintenanceOrderEditView: View {
    @ObservedObject var vm: OperationsViewModel
    let order: MaintenanceOrder
    @Environment(\.dismiss) private var dismiss
    @State private var status: MaintenanceStatus
    @State private var provider: String
    @State private var cost: String
    @State private var error = ""

    init(vm: OperationsViewModel, order: MaintenanceOrder) {
        self.vm = vm; self.order = order
        _status = State(initialValue: order.status)
        _provider = State(initialValue: order.providerName)
        _cost = State(initialValue: order.costCents.moneyPlain)
    }

    var body: some View {
        Form {
            Section(order.title) {
                Text(order.description)
                LabeledContent("Prioridad", value: order.priority.rawValue)
            }
            Section("Seguimiento") {
                Picker("Estado", selection: $status) { ForEach(MaintenanceStatus.allCases) { Text($0.rawValue).tag($0) } }
                TextField("Técnico/proveedor", text: $provider)
                TextField("Costo · USD", text: $cost).keyboardType(.decimalPad)
            }
            if !error.isEmpty { Section { Text(error).foregroundStyle(DLCTheme.red) } }
            Section { Button("Guardar orden", action: save).frame(maxWidth: .infinity, alignment: .center) }
        }
        .navigationTitle("Orden de trabajo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } } }
    }

    private func save() {
        guard let cents = parseCents(cost) else { error = "Ingresa un costo válido."; return }
        error = vm.updateMaintenance(order, status: status, provider: provider, costCents: cents) ?? ""
        if error.isEmpty { dismiss() }
    }
}

struct EditBranchView: View {
    @ObservedObject var vm: GeneralManagerViewModel
    let branch: Branch
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var code: String
    @State private var city: String
    @State private var department: String
    @State private var address: String
    @State private var capacities: [FuelType: String]
    @State private var error = ""

    init(vm: GeneralManagerViewModel, branch: Branch) {
        self.vm = vm; self.branch = branch
        _name = State(initialValue: branch.name)
        _code = State(initialValue: branch.code)
        _city = State(initialValue: branch.city)
        _department = State(initialValue: branch.department)
        _address = State(initialValue: branch.address)
        _capacities = State(initialValue: Dictionary(uniqueKeysWithValues: branch.tanks.map { ($0.type, String(format: "%.0f", $0.capacityLiters)) }))
    }

    var body: some View {
        Form {
            Section("Sucursal") {
                TextField("Nombre", text: $name)
                TextField("Código único", text: $code).textInputAutocapitalization(.characters)
                TextField("Ciudad", text: $city)
                TextField("Departamento", text: $department)
                TextField("Dirección", text: $address)
            }
            Section("Capacidad de tanques · litros") {
                ForEach(FuelType.allCases) { fuel in
                    HStack {
                        Text(fuel.rawValue)
                        Spacer()
                        TextField("Litros", text: binding(for: fuel))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 120)
                    }
                }
                Text("No se permite reducir la capacidad por debajo del inventario actual.")
                    .font(.caption).foregroundStyle(DLCTheme.muted)
            }
            if !error.isEmpty { Section { Text(error).foregroundStyle(DLCTheme.red) } }
            Section { Button("Guardar sucursal", action: save).frame(maxWidth: .infinity, alignment: .center) }
        }
        .navigationTitle("Editar sucursal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
    }

    private func binding(for fuel: FuelType) -> Binding<String> {
        Binding(get: { capacities[fuel] ?? "" }, set: { capacities[fuel] = $0 })
    }

    private func save() {
        var parsed: [FuelType: Double] = [:]
        for fuel in FuelType.allCases {
            guard let value = Double((capacities[fuel] ?? "").replacingOccurrences(of: ",", with: ".")),
                  value.isFinite, value > 0 else {
                error = "Ingresa una capacidad válida para \(fuel.rawValue)."
                return
            }
            parsed[fuel] = value
        }
        error = vm.updateBranch(id: branch.id, name: name, code: code, city: city, department: department, address: address, capacities: parsed) ?? ""
        if error.isEmpty { dismiss() }
    }
}
