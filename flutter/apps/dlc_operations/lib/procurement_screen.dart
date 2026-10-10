import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'contamination_screen.dart';
import 'format.dart';
import 'haptics.dart';
import 'labels.dart';
import 'live_form.dart';
import 'purchase_prefill.dart';
import 'ui/form_sheet.dart';
import 'ui/kit.dart';
import 'ui/sheets.dart';
import 'validators.dart';

/// Fuel purchases: suppliers, purchase orders and the receipt into a tank.
/// [prefill] opens the new-order sheet with fuel, tank and a suggested volume
/// (used by the "Solicitar compra" action of low-tank alerts).
class ProcurementScreen extends StatefulWidget {
  const ProcurementScreen({
    required this.api,
    required this.branchId,
    required this.permissions,
    this.currency = 'USD',
    this.prefill,
    super.key,
  });
  final EmployeeSession api;
  final String branchId;
  final Set<String> permissions;

  /// ISO 4217 code of the branch (from `currencyForCountry`).
  final String currency;
  final PurchasePrefill? prefill;
  @override
  State<ProcurementScreen> createState() => _ProcurementScreenState();
}

class _ProcurementScreenState extends State<ProcurementScreen> {
  List<Map<String, dynamic>> _suppliers = const [],
      _orders = const [],
      _offers = const [],
      _tanks = const [];
  bool _loading = true, _prefillHandled = false;
  String? _error, _userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _error = null;
    try {
      final x = await Future.wait<dynamic>([
        widget.api.suppliers(branchId: widget.branchId),
        widget.api.purchaseOrders(widget.branchId),
        widget.api.branchConfiguration(widget.branchId),
        widget.api.currentIdentity(),
      ]);
      _suppliers = x[0] as List<Map<String, dynamic>>;
      _orders = x[1] as List<Map<String, dynamic>>;
      final config = x[2] as Map<String, dynamic>;
      _userId = (x[3] as EmployeeIdentity).id;
      _offers = _maps(config['fuelOffers'])
          .where((r) => r['status'] == 'active')
          .toList();
      _tanks = _maps(config['tanks']);
    } on DlcApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _maybeOpenPrefill();
  }

  void _maybeOpenPrefill() {
    final p = widget.prefill;
    if (_prefillHandled || p == null || p.isEmpty || !mounted || _error != null) {
      return;
    }
    _prefillHandled = true;
    if (!widget.permissions.contains('purchase.create')) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _createOrder(prefill: p);
    });
  }

  List<Map<String, dynamic>> _tanksFor(String product) => _tanks
      .where((t) => _str(t['fuelProductId']) == product && t['status'] == 'active')
      .toList();

  Future<void> _createSupplier() async {
    if (_offers.isEmpty) {
      _message('Activa un combustible en la sucursal primero.');
      return;
    }
    final data = await showFormSheet<({String name, String product})>(
      context,
      initialSize: .7,
      builder: (ctx, scroll) => _SupplierForm(offers: _offers, scroll: scroll),
    );
    if (data == null) return;
    await _mutate(
      () => widget.api.createSupplier(
        legalName: data.name,
        fuelProductId: data.product,
      ),
    );
  }

  Future<void> _createOrder({PurchasePrefill? prefill}) async {
    if (_suppliers.isEmpty) {
      _message('Registra un proveedor con oferta activa primero.');
      return;
    }
    if (_offers.isEmpty || _tanks.isEmpty) {
      _message('Configura combustible activo y tanque compatible antes de crear una orden.');
      return;
    }
    final data =
        await showFormSheet<
          ({String supplier, String product, String tank, String qty, String price})
        >(
          context,
          builder: (ctx, scroll) => _OrderForm(
            suppliers: _suppliers,
            offers: _offers,
            tanks: _tanks,
            currency: widget.currency,
            prefill: prefill,
            scroll: scroll,
          ),
        );
    if (data == null) return;
    final number = 'DLC-${DateTime.now().toUtc().millisecondsSinceEpoch}';
    await _mutate(
      () => widget.api.createPurchaseOrder(
        widget.branchId,
        supplierId: data.supplier,
        orderNumber: number,
        fuelProductId: data.product,
        quantity: data.qty,
        unitPrice: data.price,
        tankId: data.tank,
      ),
    );
  }

  Future<void> _mutate(Future<dynamic> Function() fn) async {
    setState(() => _loading = true);
    _error = null;
    try {
      await fn();
      Haptics.success();
      await _load();
    } on DlcApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => _error = e.message);
      await _load();
    }
  }

  Future<void> _command(Map<String, dynamic> order, String action) async {
    String? reason;
    if (action == 'reject') {
      reason = await showReasonSheet(
        context,
        title: 'Rechazar orden',
        message: 'El motivo queda en el historial de la orden.',
        fieldLabel: 'Motivo de rechazo',
        confirmLabel: 'Rechazar',
        destructive: true,
      );
      if (reason == null) return;
    }
    await _mutate(
      () => widget.api.purchaseOrderCommand(
        widget.branchId,
        _str(order['id']),
        action,
        _int(order['version']),
        reason: reason,
      ),
    );
  }

  Future<void> _receive(Map<String, dynamic> order) async {
    final lines = _maps(order['lines']);
    if (lines.isEmpty) {
      _message('La orden no tiene líneas para recibir.');
      return;
    }
    final line = lines.first;
    final product = _str(line['fuelProductId']);
    final matching = _tanksFor(product);
    if (matching.isEmpty) {
      _message('No hay tanque activo para recibir este combustible.');
      return;
    }
    final data = await showFormSheet<
        ({String tank, String qty, String delivery, String doc, String cost})>(
      context,
      builder: (ctx, scroll) => _ReceiveForm(
        ordered: _str(line['quantityOrdered']),
        tanks: matching,
        initialTank: _str(line['tankId']),
        currency: widget.currency,
        scroll: scroll,
      ),
    );
    if (data == null) return;
    await _mutate(
      () => widget.api.receivePurchaseOrder(
        widget.branchId,
        _str(order['id']),
        lineId: _str(line['id']),
        tankId: data.tank,
        quantity: data.qty,
        supplierDeliveryReference: data.delivery,
        documentReference: data.doc,
        totalCostUsd: data.cost,
      ),
    );
  }

  void _message(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compras de combustible'),
        actions: [
          if (widget.permissions.contains('purchase.create'))
            IconButton(
              onPressed: _loading ? null : _createSupplier,
              tooltip: 'Nuevo proveedor',
              icon: const Icon(CupertinoIcons.person_add),
            ),
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Actualizar',
            icon: const Icon(CupertinoIcons.refresh),
          ),
        ],
      ),
      floatingActionButton: widget.permissions.contains('purchase.create')
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : () => _createOrder(),
              icon: const Icon(CupertinoIcons.cart_badge_plus),
              label: const Text('Nueva orden'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ErrorState(message: _error!, onRetry: _load),
                    ),
                  if (_orders.isEmpty && _error == null)
                    const EmptyState(
                      icon: CupertinoIcons.cart,
                      title: 'Aún no hay órdenes de compra',
                      message:
                          'Crea una orden cuando un tanque esté bajo o el proveedor confirme una entrega.',
                    ),
                  for (final o in _orders) _orderCard(context, o, colors),
                ],
              ),
            ),
    );
  }

  Widget _orderCard(BuildContext context, Map<String, dynamic> o, DlcColors colors) {
    final status = _str(o['status']);
    final perms = widget.permissions;
    final actions = <Widget>[];
    if (status == 'draft' && perms.contains('purchase.create')) {
      actions.add(TextButton(
        onPressed: () => _command(o, 'submit'),
        child: const Text('Enviar a aprobación'),
      ));
    }
    if (status == 'pending_approval' &&
        perms.contains('purchase.approve') &&
        _str(o['createdBy']) != _userId) {
      actions.add(TextButton(
        onPressed: () => _command(o, 'approve'),
        child: const Text('Aprobar'),
      ));
      actions.add(TextButton(
        onPressed: () => _command(o, 'reject'),
        child: const Text('Rechazar'),
      ));
    }
    if (status == 'pending_approval' && _str(o['createdBy']) == _userId) {
      actions.add(Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Requiere aprobación de otra persona',
          style: TextStyle(fontSize: 12, color: colors.warning),
        ),
      ));
    }
    if (status == 'approved' && perms.contains('purchase.create')) {
      actions.add(TextButton(
        onPressed: () => _command(o, 'mark-ordered'),
        child: const Text('Marcar enviada'),
      ));
    }
    final receivable = (status == 'ordered' || status == 'partially_received') &&
        perms.contains('purchase.receive');
    if (receivable) {
      actions.add(TextButton(
        onPressed: () => _receive(o),
        child: const Text('Registrar recepción'),
      ));
      actions.add(TextButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ContaminationScreen(
              api: widget.api,
              branchId: widget.branchId,
              order: o,
              tanks: _tanks,
              permissions: widget.permissions,
            ),
          ),
        ).then((_) => _load()),
        child: const Text('Descarga con incidencia'),
      ));
    }
    final lines = _maps(o['lines']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DlcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_str(o['orderNumber'])} · ${_str(o['supplierName'])}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(status),
              ],
            ),
            for (final l in lines)
              Text(
                '${_str(l['quantityOrdered'])} ${unitLabel(l['unit'])} · ${moneyRaw(l['agreedUnitPriceUsd'], currency: widget.currency, decimals: 4)}',
              ),
            if (actions.isNotEmpty)
              Wrap(alignment: WrapAlignment.end, children: actions),
          ],
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> _maps(dynamic v) => ((v as List<dynamic>?) ?? const [])
    .whereType<Map<String, dynamic>>()
    .map((r) => Map<String, dynamic>.from(r))
    .toList();

String _str(dynamic v) => v?.toString() ?? '';
int _int(dynamic v) => int.tryParse('$v') ?? 1;

class _SupplierForm extends StatefulWidget {
  const _SupplierForm({required this.offers, required this.scroll});
  final List<Map<String, dynamic>> offers;
  final ScrollController scroll;
  @override
  State<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends State<_SupplierForm> {
  final _name = TextEditingController();
  late String _product = _str(widget.offers.first['fuelProductId']);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _nameError(String? v) => minLengthText(v, 3, field: 'La razón social');

  @override
  Widget build(BuildContext context) {
    final offer = widget.offers.firstWhere(
      (o) => _str(o['fuelProductId']) == _product,
      orElse: () => widget.offers.first,
    );
    return FormSheetLayout(
      title: 'Nuevo proveedor',
      icon: CupertinoIcons.person_add,
      scrollController: widget.scroll,
      submitLabel: 'Guardar proveedor',
      onSubmit: _nameError(_name.text) == null
          ? () => Navigator.pop(context, (name: _name.text.trim(), product: _product))
          : null,
      children: [
        LiveTextField(
          controller: _name,
          label: 'Razón social',
          validator: _nameError,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 12),
        SelectField<String>(
          label: 'Combustible ofertado',
          valueLabel: _str(offer['fuelName'] ?? offer['fuelProductId']),
          onTap: () async {
            final v = await showSelectSheet<String>(
              context,
              title: 'Combustible ofertado',
              selected: _product,
              options: [
                for (final o in widget.offers)
                  SelectOption(
                    _str(o['fuelProductId']),
                    _str(o['fuelName'] ?? o['fuelProductId']),
                  ),
              ],
            );
            if (v != null) setState(() => _product = v);
          },
        ),
      ],
    );
  }
}

class _OrderForm extends StatefulWidget {
  const _OrderForm({
    required this.suppliers,
    required this.offers,
    required this.tanks,
    required this.currency,
    required this.scroll,
    this.prefill,
  });
  final List<Map<String, dynamic>> suppliers, offers, tanks;
  final String currency;
  final PurchasePrefill? prefill;
  final ScrollController scroll;
  @override
  State<_OrderForm> createState() => _OrderFormState();
}

class _OrderFormState extends State<_OrderForm> {
  late String _supplier = _str(widget.suppliers.first['id']);
  late String _product = _initialProduct();
  late String _tank = _initialTank();
  late final TextEditingController _qty = TextEditingController(
    text: widget.prefill?.suggestedText ?? '',
  );
  final _price = TextEditingController();

  String _initialProduct() {
    final wanted = widget.prefill?.fuelProductId ?? '';
    final offerIds = widget.offers.map((o) => _str(o['fuelProductId'])).toList();
    if (wanted.isNotEmpty && offerIds.contains(wanted)) return wanted;
    return offerIds.first;
  }

  List<Map<String, dynamic>> get _compatible => widget.tanks
      .where((t) => _str(t['fuelProductId']) == _product && t['status'] == 'active')
      .toList();

  String _initialTank() {
    final wanted = widget.prefill?.tankId ?? '';
    final compatible = _compatible;
    if (wanted.isNotEmpty && compatible.any((t) => _str(t['id']) == wanted)) {
      return wanted;
    }
    return compatible.isEmpty ? '' : _str(compatible.first['id']);
  }

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  String? _qtyError(String? v) =>
      positiveNumber(v, field: 'La cantidad', maxDecimals: 3);
  String? _priceError(String? v) =>
      positiveNumber(v, field: 'El precio', maxDecimals: 4);

  bool get _valid =>
      _tank.isNotEmpty && _qtyError(_qty.text) == null && _priceError(_price.text) == null;

  String _tankLabel(Map<String, dynamic> t) => '${_str(t['code'])} · ${_str(t['name'])}';

  @override
  Widget build(BuildContext context) {
    final supplier = widget.suppliers.firstWhere(
      (s) => _str(s['id']) == _supplier,
      orElse: () => widget.suppliers.first,
    );
    final offer = widget.offers.firstWhere(
      (o) => _str(o['fuelProductId']) == _product,
    );
    final tanks = _compatible;
    final tank = tanks.where((t) => _str(t['id']) == _tank).firstOrNull;
    return FormSheetLayout(
      title: 'Nueva orden de combustible',
      subtitle: widget.prefill?.tankCode == null
          ? null
          : 'Sugerida por el tanque ${widget.prefill!.tankCode}',
      icon: CupertinoIcons.cart_badge_plus,
      scrollController: widget.scroll,
      submitLabel: 'Crear borrador',
      onSubmit: _valid
          ? () => Navigator.pop(context, (
              supplier: _supplier,
              product: _product,
              tank: _tank,
              qty: _qty.text.trim(),
              price: _price.text.trim(),
            ))
          : null,
      children: [
        SelectField<String>(
          label: 'Proveedor',
          valueLabel: _str(supplier['legalName']),
          onTap: () async {
            final v = await showSelectSheet<String>(
              context,
              title: 'Proveedor',
              selected: _supplier,
              options: [
                for (final s in widget.suppliers)
                  SelectOption(_str(s['id']), _str(s['legalName'])),
              ],
            );
            if (v != null) setState(() => _supplier = v);
          },
        ),
        const SizedBox(height: 12),
        SelectField<String>(
          label: 'Combustible',
          valueLabel: _str(offer['fuelName'] ?? offer['fuelProductId']),
          onTap: () async {
            final v = await showSelectSheet<String>(
              context,
              title: 'Combustible',
              selected: _product,
              options: [
                for (final o in widget.offers)
                  SelectOption(
                    _str(o['fuelProductId']),
                    _str(o['fuelName'] ?? o['fuelProductId']),
                  ),
              ],
            );
            if (v != null) {
              setState(() {
                _product = v;
                _tank = _initialTankFor(v);
              });
            }
          },
        ),
        const SizedBox(height: 12),
        SelectField<String>(
          label: 'Tanque destino',
          valueLabel: tank == null ? 'Sin tanque compatible' : _tankLabel(tank),
          enabled: tanks.isNotEmpty,
          onTap: () async {
            final v = await showSelectSheet<String>(
              context,
              title: 'Tanque destino',
              selected: _tank,
              options: [
                for (final t in tanks) SelectOption(_str(t['id']), _tankLabel(t)),
              ],
            );
            if (v != null) setState(() => _tank = v);
          },
        ),
        const SizedBox(height: 12),
        LiveTextField(
          controller: _qty,
          keyboardType: LiveTextField.decimal(),
          label: 'Cantidad (L)',
          validator: _qtyError,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 4),
        LiveTextField(
          controller: _price,
          keyboardType: LiveTextField.decimal(),
          label: 'Precio acordado ${currencySymbol(widget.currency)} por litro',
          validator: _priceError,
          onChanged: () => setState(() {}),
        ),
      ],
    );
  }

  String _initialTankFor(String product) {
    final compatible = widget.tanks
        .where((t) => _str(t['fuelProductId']) == product && t['status'] == 'active')
        .toList();
    return compatible.isEmpty ? '' : _str(compatible.first['id']);
  }
}

class _ReceiveForm extends StatefulWidget {
  const _ReceiveForm({
    required this.ordered,
    required this.tanks,
    required this.initialTank,
    required this.currency,
    required this.scroll,
  });
  final String ordered, initialTank, currency;
  final List<Map<String, dynamic>> tanks;
  final ScrollController scroll;
  @override
  State<_ReceiveForm> createState() => _ReceiveFormState();
}

class _ReceiveFormState extends State<_ReceiveForm> {
  late String _tank = widget.initialTank.isNotEmpty &&
          widget.tanks.any((t) => _str(t['id']) == widget.initialTank)
      ? widget.initialTank
      : _str(widget.tanks.first['id']);
  final _qty = TextEditingController(),
      _cost = TextEditingController(),
      _delivery = TextEditingController(),
      _doc = TextEditingController();

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    _delivery.dispose();
    _doc.dispose();
    super.dispose();
  }

  double? get _ordered => double.tryParse(widget.ordered);
  String? _qtyError(String? v) => notAbove(
    v,
    _ordered,
    field: 'La cantidad aceptada',
    limitName: 'lo ordenado',
    maxDecimals: 3,
  );
  String? _costError(String? v) =>
      positiveNumber(v, field: 'El costo total', allowZero: true, maxDecimals: 4);
  String? _refError(String? v) => minLengthText(v, 3, field: 'La referencia');
  String? _docError(String? v) => minLengthText(v, 3, field: 'El documento');

  bool get _valid => allValid([
    _qtyError(_qty.text),
    _costError(_cost.text),
    _refError(_delivery.text),
    _docError(_doc.text),
  ]);

  @override
  Widget build(BuildContext context) {
    final tank = widget.tanks.firstWhere((t) => _str(t['id']) == _tank);
    String label(Map<String, dynamic> t) => '${_str(t['code'])} · ${_str(t['name'])}';
    return FormSheetLayout(
      title: 'Recibir ${widget.ordered} L',
      icon: CupertinoIcons.cube_box,
      scrollController: widget.scroll,
      submitLabel: 'Registrar recepción',
      onSubmit: _valid
          ? () => Navigator.pop(context, (
              tank: _tank,
              qty: _qty.text.trim(),
              delivery: _delivery.text.trim(),
              doc: _doc.text.trim(),
              cost: _cost.text.trim(),
            ))
          : null,
      children: [
        SelectField<String>(
          label: 'Tanque de recepción',
          valueLabel: label(tank),
          onTap: () async {
            final v = await showSelectSheet<String>(
              context,
              title: 'Tanque de recepción',
              selected: _tank,
              options: [
                for (final t in widget.tanks) SelectOption(_str(t['id']), label(t)),
              ],
            );
            if (v != null) setState(() => _tank = v);
          },
        ),
        const SizedBox(height: 12),
        LiveTextField(
          controller: _qty,
          keyboardType: LiveTextField.decimal(),
          label: 'Cantidad aceptada (L)',
          validator: _qtyError,
          onChanged: () => setState(() {}),
        ),
        LiveTextField(
          controller: _cost,
          keyboardType: LiveTextField.decimal(),
          label: 'Costo total ${currencySymbol(widget.currency)}',
          validator: _costError,
          onChanged: () => setState(() {}),
        ),
        LiveTextField(
          controller: _delivery,
          label: 'Referencia de entrega del proveedor',
          validator: _refError,
          onChanged: () => setState(() {}),
        ),
        LiveTextField(
          controller: _doc,
          label: 'Documento de recepción',
          validator: _docError,
          onChanged: () => setState(() {}),
        ),
      ],
    );
  }
}
