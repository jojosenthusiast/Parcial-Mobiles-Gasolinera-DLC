import 'point_refunds_screen.dart';
import 'customer_qr_scanner_screen.dart';
import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class CashScreen extends StatefulWidget {
  const CashScreen({
    required this.api,
    required this.branchId,
    required this.permissions,
    super.key,
  });
  final EmployeeSession api;
  final String branchId;
  final Set<String> permissions;
  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  List<Map<String, dynamic>> _registers = const [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _error = null;
    try {
      _registers = await widget.api.cashRegisters(widget.branchId);
    } on DlcApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createRegister() async {
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crear caja'),
        content: TextField(
          controller: c,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Código'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    c.dispose();
    if (code == null || code.isEmpty) return;
    await _mutate(() => widget.api.createCashRegister(widget.branchId, code));
  }

  Future<void> _open(Map<String, dynamic> register) async {
    final c = TextEditingController(text: '0');
    final amount = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Abrir caja ${_str(register['code'])}'),
        content: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Fondo inicial USD'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Abrir turno'),
          ),
        ],
      ),
    );
    c.dispose();
    if (amount == null) return;
    await _mutate(
      () => widget.api.openCashSession(
        widget.branchId,
        _str(register['id']),
        amount,
      ),
    );
  }

  Future<void> _detail(Map<String, dynamic> register) async {
    final id = _str(register['openSessionId']);
    if (id.isEmpty) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => _CashSessionPage(
          api: widget.api,
          branchId: widget.branchId,
          sessionId: id,
          registerCode: _str(register['code']),
          permissions: widget.permissions,
        ),
      ),
    );
    if (mounted && result == true) await _load();
  }

  Future<void> _mutate(Future<dynamic> Function() fn) async {
    setState(() => _loading = true);
    try {
      await fn();
      await _load();
    } on DlcApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Cajas y turnos'),
      actions: [
        if (widget.permissions.contains('payment.read') &&
            widget.permissions.contains('sale.read'))
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => PointRefundsScreen(
                  api: widget.api,
                  branchId: widget.branchId,
                  permissions: widget.permissions,
                ),
              ),
            ),
            tooltip: 'Devoluciones de puntos',
            icon: const Icon(Icons.currency_exchange),
          ),
        if (widget.permissions.contains('cash.register.manage'))
          IconButton(
            onPressed: _loading ? null : _createRegister,
            tooltip: 'Crear caja',
            icon: const Icon(Icons.add_box_outlined),
          ),
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Card(
                    color: const Color(0xffffeae5),
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(_error!),
                    ),
                  ),
                if (_registers.isEmpty)
                  const Card(
                    child: ListTile(title: Text('No hay cajas registradas.')),
                  ),
                ..._registers.map((r) {
                  final open = _str(r['openSessionId']).isNotEmpty;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        open
                            ? Icons.point_of_sale
                            : Icons.point_of_sale_outlined,
                        color: open ? Colors.green : Colors.grey,
                      ),
                      title: Text(
                        'Caja ${_str(r['code'])}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        open
                            ? 'Turno abierto · ${_str(r['cashierId'])}'
                            : 'Sin turno abierto',
                      ),
                      trailing: open
                          ? const Icon(Icons.chevron_right)
                          : widget.permissions.contains('cash.open')
                          ? TextButton(
                              onPressed: () => _open(r),
                              child: const Text('Abrir turno'),
                            )
                          : null,
                      onTap: open ? () => _detail(r) : null,
                    ),
                  );
                }),
              ],
            ),
          ),
  );
}

class _CashSessionPage extends StatefulWidget {
  const _CashSessionPage({
    required this.api,
    required this.branchId,
    required this.sessionId,
    required this.registerCode,
    required this.permissions,
  });
  final EmployeeSession api;
  final String branchId, sessionId, registerCode;
  final Set<String> permissions;
  @override
  State<_CashSessionPage> createState() => _CashSessionPageState();
}

class _CashSessionPageState extends State<_CashSessionPage> {
  Map<String, dynamic> _session = const {};
  List<Map<String, dynamic>> _movements = const [];
  bool _loading = true;
  String? _error;
  bool get _closed => _session['closureId'] != null;
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
        widget.api.cashSession(widget.branchId, widget.sessionId),
        widget.api.cashMovements(widget.branchId, widget.sessionId),
      ]);
      _session = x[0] as Map<String, dynamic>;
      _movements = x[1] as List<Map<String, dynamic>>;
    } on DlcApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _movement() async {
    String kind = 'cash_in';
    final amount = TextEditingController(), reason = TextEditingController();
    final value = await showDialog<(String, String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Movimiento de caja'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(
                    value: 'cash_in',
                    child: Text('Entrada de efectivo'),
                  ),
                  DropdownMenuItem(value: 'withdrawal', child: Text('Retiro')),
                  DropdownMenuItem(
                    value: 'deposit',
                    child: Text('Depósito bancario'),
                  ),
                ],
                onChanged: (v) => setState(() => kind = v ?? kind),
              ),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Monto USD'),
              ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Motivo'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (
                kind,
                amount.text.trim(),
                reason.text.trim(),
              )),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    reason.dispose();
    if (value == null) return;
    await _mutate(
      () => widget.api.cashMovement(
        widget.branchId,
        widget.sessionId,
        value.$1,
        value.$2,
        value.$3,
      ),
    );
  }

  Future<void> _close() async {
    final cash = TextEditingController(),
        card = TextEditingController(),
        reason = TextEditingController();
    final value = await showDialog<(String, String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar y cuadrar caja'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Efectivo esperado: USD ${_str(_session['expectedCashUsd'])}',
              ),
              TextField(
                controller: cash,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Efectivo contado USD',
                ),
              ),
              TextField(
                controller: card,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Tarjeta liquidada USD',
                ),
              ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Nota de diferencias (si aplica)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, (
              cash.text.trim(),
              card.text.trim(),
              reason.text.trim(),
            )),
            child: const Text('Cerrar turno'),
          ),
        ],
      ),
    );
    cash.dispose();
    card.dispose();
    reason.dispose();
    if (value == null) return;
    await _mutate(
      () => widget.api.closeCashSession(
        widget.branchId,
        widget.sessionId,
        value.$1,
        value.$2,
        value.$3,
      ),
    );
    if (mounted && !_loading && !_closed) Navigator.pop(context, true);
  }

  Future<void> _mutate(Future<dynamic> Function() fn) async {
    setState(() => _loading = true);
    try {
      await fn();
      await _load();
    } on DlcApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Caja ${widget.registerCode}')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Card(
                    color: const Color(0xffffeae5),
                    child: ListTile(title: Text(_error!)),
                  ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: Text(_closed ? 'Turno cerrado' : 'Turno abierto'),
                    subtitle: Text(
                      'Fondo inicial USD ${_str(_session['openingUsd'])}\nEfectivo esperado USD ${_str(_session['expectedCashUsd'])}',
                    ),
                  ),
                ),
                if (!_closed &&
                    widget.permissions.containsAll({
                      'sale.create',
                      'pos.catalog.read',
                      'payment.collect',
                    }))
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: FilledButton.icon(
                      onPressed: () => _checkout(),
                      icon: const Icon(Icons.shopping_cart_checkout),
                      label: const Text('Nueva venta POS'),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Movimientos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_movements.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text('No hay movimientos manuales.'),
                    ),
                  ),
                ..._movements.map(
                  (m) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(
                        '${_str(m['kind'])} · USD ${_str(m['amountUsd'] ?? m['deltaUsd'])}',
                      ),
                      subtitle: Text(_str(m['reason'])),
                    ),
                  ),
                ),
                if (!_closed && widget.permissions.contains('cash.move'))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: _movement,
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Registrar movimiento'),
                    ),
                  ),
                if (!_closed && widget.permissions.contains('cash.close'))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton.icon(
                      onPressed: _close,
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Cerrar y cuadrar turno'),
                    ),
                  ),
                if (_closed)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.verified_outlined),
                      title: Text('El turno ya se cerró'),
                      subtitle: Text(
                        'La revisión de variaciones queda disponible según tus permisos.',
                      ),
                    ),
                  ),
              ],
            ),
          ),
  );
  Future<void> _checkout() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => _PosCheckoutScreen(
          api: widget.api,
          branchId: widget.branchId,
          sessionId: widget.sessionId,
        ),
      ),
    );
    if (mounted && result == true) await _load();
  }
}

class _PosCheckoutScreen extends StatefulWidget {
  const _PosCheckoutScreen({
    required this.api,
    required this.branchId,
    required this.sessionId,
  });
  final EmployeeSession api;
  final String branchId, sessionId;
  @override
  State<_PosCheckoutScreen> createState() => _PosCheckoutScreenState();
}

class _PosCheckoutScreenState extends State<_PosCheckoutScreen> {
  List<Map<String, dynamic>> _catalog = const [];
  final Map<String, int> _cart = {};
  final TextEditingController _customerCode = TextEditingController();
  Map<String, dynamic>? _sale;
  String? _pendingAttempt, _error, _notice;
  String _selectedStoreCategory = '';
  List<String> get _storeCategories =>
      _catalog
          .map((product) => _str(product['category']))
          .where((category) => category.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  bool _loading = true,
      _busy = false,
      _paymentSending = false,
      _resolutionSending = false,
      _alreadyPaid = false,
      _customerLinked = false,
      _tenderStatusUnknown = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _customerCode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _tenderStatusUnknown = false;
    _alreadyPaid = false;
    _pendingAttempt = null;
    _paymentSending = false;
    _resolutionSending = false;
    try {
      _catalog = await widget.api.posCatalog(widget.branchId);
      final pending = await widget.api.pendingPosSale(widget.branchId);
      if (pending != null) {
        final rawItems = pending['items'];
        if (rawItems is List) {
          _cart.clear();
          for (final item in rawItems.whereType<Map>()) {
            final id = _str(item['productId']);
            _cart[id] = int.tryParse(_str(item['quantity'])) ?? 1;
          }
        }
        if (pending['sale'] is Map)
          _sale = Map<String, dynamic>.from(pending['sale'] as Map);
        _customerCode.text = _str(pending['customerCode']);
        _customerLinked = pending['customerLinked'] == true;
        if (pending['payment'] is Map) {
          final payment = Map<String, dynamic>.from(pending['payment'] as Map);
          if (payment['status'] == 'unknown')
            _pendingAttempt = _str(payment['attemptId']);
          _paymentSending = payment['status'] == 'sending';
          _alreadyPaid = false;
          if (payment['status'] == 'paid' && _sale != null) {
            _tenderStatusUnknown = true;
            _sale = await widget.api.saleDetail(
              widget.branchId,
              _str(_sale!['id']),
            );
            _tenderStatusUnknown = false;
            _alreadyPaid = _str(_sale?['status']) == 'paid';
            if (_alreadyPaid)
              _error =
                  'La venta ya está pagada. Cierra esta pantalla para volver a caja.';
          }
        }
        if (pending['resolution'] is Map)
          _resolutionSending =
              (pending['resolution'] as Map)['status'] == 'sending';
      }
    } on DlcApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanCustomerQr() async {
    if (_busy) return;
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const CustomerQrScannerScreen(),
      ),
    );
    if (!mounted || code == null) return;
    setState(() {
      _customerCode.text = code;
      _error = null;
      _notice =
          'QR leído. Vincula el Cliente antes de solicitar pagos con puntos.';
    });
  }

  Widget _customerCodeField({required String helperText}) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: TextField(
          controller: _customerCode,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Código QR de Cliente (opcional)',
            helperText: helperText,
            prefixIcon: const Icon(Icons.qr_code_2),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: IconButton.filledTonal(
          onPressed: _busy ? null : _scanCustomerQr,
          tooltip: 'Escanear QR del Cliente',
          icon: const Icon(Icons.qr_code_scanner),
        ),
      ),
    ],
  );

  Future<void> _createSale() async {
    if (_busy || _cart.isEmpty) return;
    setState(() => _busy = true);
    _error = null;
    try {
      final items = _cart.entries
          .map((e) {
            final product = _catalog.firstWhere((x) => _str(x['id']) == e.key);
            return <String, String>{
              'productId': e.key,
              'offerVersionId': _str(product['offerVersionId']),
              'quantity': e.value.toString(),
            };
          })
          .toList(growable: false);
      _sale = await widget.api.createPosSale(
        widget.branchId,
        items,
        customerCode: _customerCode.text,
      );
      if (_str(_sale?['id']).isEmpty)
        throw const DlcApiException(
          'La venta se creó sin devolver su identificador.',
        );
      if (_customerCode.text.trim().isNotEmpty) {
        await widget.api.linkCustomerToSale(
          widget.branchId,
          _str(_sale!['id']),
          _customerCode.text,
        );
        _customerLinked = true;
      }
    } on DlcApiException catch (e) {
      _error =
          '${e.message}${e.correlationId == null ? '' : ' · Ref. ${e.correlationId}'}';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkCustomer() async {
    if (_busy || _customerCode.text.trim().isEmpty || _sale == null) return;
    setState(() => _busy = true);
    try {
      await widget.api.linkCustomerToSale(
        widget.branchId,
        _str(_sale!['id']),
        _customerCode.text,
      );
      _customerLinked = true;
    } on DlcApiException catch (e) {
      _error =
          '${e.message}${e.correlationId == null ? '' : ' · Ref. ${e.correlationId}'}';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestPoints() async {
    final sale = _sale;
    if (sale == null || _busy || !_customerLinked) return;
    final points = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Solicitar pago con puntos'),
        content: TextField(
          controller: points,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Puntos que desea usar',
            helperText:
                'El Cliente deberá revisar y confirmar el importe en su app.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, points.text.trim()),
            child: const Text('Enviar solicitud'),
          ),
        ],
      ),
    );
    points.dispose();
    if (raw == null) return;
    final count = int.tryParse(raw);
    if (count == null || count < 1) {
      setState(
        () => _error = 'Escribe una cantidad entera positiva de puntos.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final quote = await widget.api.requestPointPaymentQuote(
        widget.branchId,
        _str(sale['id']),
        widget.sessionId,
        count,
      );
      _notice =
          'Solicitud enviada: ${quote['points'] ?? count} puntos por USD ${quote['amountUsd'] ?? '—'}. El Cliente debe confirmarla en su app; luego actualiza el saldo antes de cobrar el remanente.';
    } on DlcApiException catch (e) {
      _error =
          '${e.message}${e.correlationId == null ? '' : ' · Ref. ${e.correlationId}'}';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _checkSaleStatus() async {
    final sale = _sale;
    if (sale == null) return false;
    _tenderStatusUnknown = true;
    _sale = await widget.api.saleDetail(widget.branchId, _str(sale['id']));
    _tenderStatusUnknown = false;
    _alreadyPaid = _str(_sale?['status']) == 'paid';
    if (!_alreadyPaid)
      _notice =
          'Saldo pendiente actualizado: USD ${_sale?['outstandingUsd'] ?? '—'}. Puede cobrar ese remanente.';
    return _alreadyPaid;
  }

  Future<void> _refreshSale() async {
    if (_sale == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (await _checkSaleStatus()) {
        await _finishSale();
      }
    } on DlcApiException catch (e) {
      _error =
          '${e.message}${e.correlationId == null ? '' : ' · Ref. ${e.correlationId}'}';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishSale() async {
    await widget.api.completePosSale(widget.branchId);
    if (mounted)
      setState(() {
        _alreadyPaid = true;
        _notice = 'Venta pagada. Puedes compartir el comprobante interno.';
      });
  }

  Future<void> _shareReceipt() async {
    final saleId = _str(_sale?['id']);
    if (saleId.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await widget.api.saleReceiptPdf(widget.branchId, saleId);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              name: 'comprobante-$saleId.pdf',
              mimeType: 'application/pdf',
            ),
          ],
          subject: 'Comprobante interno - NO FISCAL',
        ),
      );
    } on DlcApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _collect() async {
    final sale = _sale;
    if (sale == null || _busy) return;
    String method = 'cash', outcome = 'confirmed';
    final amount = TextEditingController(
      text: _str(sale['outstandingUsd'] ?? sale['totalUsd']),
    );
    final evidence = TextEditingController();
    final choice = await showDialog<(String, String, String, String)?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Registrar cobro'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(labelText: 'Método'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                    DropdownMenuItem(
                      value: 'card',
                      child: Text('Tarjeta · terminal manual'),
                    ),
                  ],
                  onChanged: (v) => setDialog(() => method = v ?? method),
                ),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Monto recibido USD',
                  ),
                ),
                if (method == 'card') ...[
                  DropdownButtonFormField<String>(
                    initialValue: outcome,
                    decoration: const InputDecoration(
                      labelText: 'Resultado del terminal',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'confirmed',
                        child: Text('Aprobado'),
                      ),
                      DropdownMenuItem(
                        value: 'declined',
                        child: Text('Rechazado'),
                      ),
                      DropdownMenuItem(
                        value: 'unknown',
                        child: Text('Resultado incierto'),
                      ),
                    ],
                    onChanged: (v) => setDialog(() => outcome = v ?? outcome),
                  ),
                  TextField(
                    controller: evidence,
                    decoration: InputDecoration(
                      labelText: outcome == 'unknown'
                          ? 'Referencia (si se conoce)'
                          : 'Referencia del terminal',
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'La app registra el resultado informado por el cajero. No procesa tarjetas ni se conecta al terminal.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (
                method,
                method == 'cash' ? 'confirmed' : outcome,
                amount.text.trim(),
                evidence.text.trim(),
              )),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    evidence.dispose();
    if (choice == null) return;
    setState(() => _busy = true);
    _error = null;
    try {
      final response = await widget.api.collectPayment(
        widget.branchId,
        saleId: _str(sale['id']),
        sessionId: widget.sessionId,
        method: choice.$1,
        amountUsd: choice.$3,
        outcome: choice.$2,
        evidenceReference: choice.$4,
      );
      if (choice.$2 == 'unknown') {
        _pendingAttempt = _str(response['id']);
        if (_pendingAttempt!.isEmpty)
          throw const DlcApiException(
            'El cobro quedó incierto sin identificador para resolverlo.',
          );
      } else if (choice.$2 == 'confirmed') {
        if (await _checkSaleStatus()) {
          await _finishSale();
        }
      } else {
        _error =
            'El terminal registró un rechazo. Puedes revisar la venta e intentar otro método.';
      }
    } on DlcApiException catch (e) {
      _error =
          '${e.message}${e.correlationId == null ? '' : ' · Ref. ${e.correlationId}'}';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve() async {
    final attempt = _pendingAttempt;
    if (attempt == null || _busy) return;
    String result = 'confirmed';
    final evidence = TextEditingController();
    final choice = await showDialog<(String, String)?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Conciliar cobro incierto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Consulta el terminal y el comprobante antes de elegir el resultado.',
              ),
              DropdownButtonFormField<String>(
                initialValue: result,
                decoration: const InputDecoration(
                  labelText: 'Resultado comprobado',
                ),
                items: const [
                  DropdownMenuItem(value: 'confirmed', child: Text('Aprobado')),
                  DropdownMenuItem(value: 'declined', child: Text('Rechazado')),
                ],
                onChanged: (v) => setDialog(() => result = v ?? result),
              ),
              TextField(
                controller: evidence,
                decoration: const InputDecoration(
                  labelText: 'Referencia documental',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, (result, evidence.text.trim())),
              child: const Text('Resolver'),
            ),
          ],
        ),
      ),
    );
    evidence.dispose();
    if (choice == null) return;
    if (choice.$2.trim().isEmpty) {
      setState(() => _error = 'Debes anotar la referencia del comprobante.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.resolvePayment(
        widget.branchId,
        attempt,
        choice.$1,
        choice.$2,
      );
      if (choice.$1 == 'confirmed' && await _checkSaleStatus()) {
        await _finishSale();
      } else {
        setState(() => _pendingAttempt = null);
      }
    } on DlcApiException catch (e) {
      _error =
          '${e.message}${e.correlationId == null ? '' : ' · Ref. ${e.correlationId}'}';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryPayment() async {
    setState(() => _busy = true);
    try {
      final result = await widget.api.retryPendingPayment(widget.branchId);
      final pending = await widget.api.pendingPosSale(widget.branchId);
      final payment = pending?['payment'] is Map
          ? Map<String, dynamic>.from(pending!['payment'] as Map)
          : const <String, dynamic>{};
      if (payment['status'] == 'unknown') _pendingAttempt = _str(result['id']);
      if (payment['status'] == 'paid') {
        if (await _checkSaleStatus()) {
          await _finishSale();
        } else {
          _paymentSending = false;
        }
      } else {
        _paymentSending = false;
      }
    } on DlcApiException catch (e) {
      _error =
          '${e.message}${e.correlationId == null ? '' : ' · Ref. ${e.correlationId}'}';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryResolution() async {
    setState(() => _busy = true);
    try {
      await widget.api.retryPendingResolution(widget.branchId);
      final pending = await widget.api.pendingPosSale(widget.branchId);
      final resolution = pending?['resolution'] is Map
          ? Map<String, dynamic>.from(pending!['resolution'] as Map)
          : const <String, dynamic>{};
      if (resolution['status'] == 'confirmed' && await _checkSaleStatus()) {
        await _finishSale();
      } else {
        _resolutionSending = false;
        _pendingAttempt = null;
      }
    } on DlcApiException catch (e) {
      _error =
          '${e.message}${e.correlationId == null ? '' : ' · Ref. ${e.correlationId}'}';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Venta POS')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Card(
                    color: const Color(0xffffeae5),
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(_error!),
                    ),
                  ),
                if (_notice != null)
                  Card(
                    color: const Color(0xffe6f3e8),
                    child: ListTile(
                      leading: const Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                      ),
                      title: Text(_notice!),
                    ),
                  ),
                if (_sale == null) ...[
                  _cardTitle('Productos disponibles'),
                  if (_storeCategories.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: _selectedStoreCategory,
                      decoration: const InputDecoration(
                        labelText: 'Filtrar por categoría',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Todas las categorías'),
                        ),
                        ..._storeCategories.map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _selectedStoreCategory = value ?? ''),
                    ),
                  if (_catalog.isEmpty)
                    const Card(
                      child: ListTile(
                        title: Text('No hay productos activos en el catálogo.'),
                      ),
                    ),
                  ..._catalog
                      .where(
                        (p) =>
                            p['active'] == true &&
                            p['inAssortment'] == true &&
                            (_selectedStoreCategory.isEmpty ||
                                _str(p['category']) == _selectedStoreCategory),
                      )
                      .map((p) {
                        final id = _str(p['id']);
                        final units =
                            int.tryParse(_str(p['availableUnits'])) ?? 0;
                        final service = _str(p['kind']) == 'service';
                        return Card(
                          child: ListTile(
                            title: Text(_str(p['description'])),
                            subtitle: Text(
                              '${_str(p['category'])} · USD ${_str(p['priceUsd'])}${service ? '' : ' · Disponibles: ${_str(p['availableUnits'])}'}',
                            ),
                            leading: Icon(
                              service
                                  ? Icons.build_outlined
                                  : Icons.inventory_2_outlined,
                            ),
                            trailing: IconButton(
                              onPressed: (!_busy && !service && units < 1)
                                  ? null
                                  : () => setState(
                                      () => _cart[id] = (_cart[id] ?? 0) + 1,
                                    ),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ),
                        );
                      }),
                  if (_cart.isNotEmpty) ...[
                    _cardTitle('Venta actual'),
                    ..._cart.entries.map((entry) {
                      final p = _catalog.firstWhere(
                        (x) => _str(x['id']) == entry.key,
                      );
                      return ListTile(
                        title: Text(_str(p['description'])),
                        subtitle: Text('Cantidad: ${entry.value}'),
                        trailing: IconButton(
                          onPressed: () => setState(
                            () => entry.value <= 1
                                ? _cart.remove(entry.key)
                                : _cart[entry.key] = entry.value - 1,
                          ),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      );
                    }),
                    _customerCodeField(
                      helperText:
                          'Escanea el QR de la app o introduce el código manualmente.',
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _createSale,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_busy ? 'Guardando…' : 'Crear venta'),
                    ),
                  ],
                ] else ...[
                  _cardTitle('Venta registrada'),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(
                        'USD ${_str(_sale!['totalUsd'])}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: SelectableText('Venta ${_str(_sale!['id'])}'),
                    ),
                  ),
                  if (!_customerLinked && !_alreadyPaid) ...[
                    _customerCodeField(
                      helperText:
                          'El QR solo identifica la cuenta; no autoriza canjes. También puedes introducir el código.',
                    ),
                    if (_customerCode.text.trim().isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _linkCustomer,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Vincular Cliente antes del cobro'),
                      ),
                  ],
                  if (_customerLinked) ...[
                    const ListTile(
                      leading: Icon(
                        Icons.verified_user_outlined,
                        color: Colors.green,
                      ),
                      title: Text('Cliente vinculado a esta venta'),
                    ),
                    if (!_alreadyPaid &&
                        !_paymentSending &&
                        !_resolutionSending)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _requestPoints,
                        icon: const Icon(Icons.stars_outlined),
                        label: const Text('Solicitar pago con puntos'),
                      ),
                    if (!_alreadyPaid)
                      Text(
                        'Saldo pendiente: USD ${_str(_sale!['outstandingUsd'] ?? _sale!['totalUsd'])}',
                      ),
                    if (!_alreadyPaid)
                      TextButton.icon(
                        onPressed: _busy ? null : _refreshSale,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Actualizar saldo de venta'),
                      ),
                  ],
                  if (_tenderStatusUnknown)
                    Card(
                      color: const Color(0xfffff2db),
                      child: ListTile(
                        leading: const Icon(Icons.sync_problem),
                        title: const Text(
                          'Verifica el saldo antes de otro cobro',
                        ),
                        subtitle: const Text(
                          'Hay un tender anterior confirmado localmente y falta consultar su estado.',
                        ),
                        trailing: TextButton(
                          onPressed: _busy ? null : _refreshSale,
                          child: const Text('Consultar'),
                        ),
                      ),
                    ),
                  if (_alreadyPaid) ...[
                    FilledButton.icon(
                      onPressed: _busy ? null : _shareReceipt,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Compartir comprobante PDF'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Volver a caja'),
                    ),
                  ],
                  if (_paymentSending)
                    FilledButton.icon(
                      onPressed: _busy ? null : _retryPayment,
                      icon: const Icon(Icons.sync),
                      label: const Text('Reintentar cobro anterior'),
                    ),
                  if (_resolutionSending)
                    FilledButton.icon(
                      onPressed: _busy ? null : _retryResolution,
                      icon: const Icon(Icons.sync),
                      label: const Text('Reintentar conciliación'),
                    ),
                  if (_pendingAttempt != null && !_resolutionSending)
                    Card(
                      color: const Color(0xfffff2db),
                      child: ListTile(
                        leading: const Icon(Icons.help_outline),
                        title: const Text('Cobro con resultado incierto'),
                        subtitle: Text('Intento ${_pendingAttempt!}'),
                        trailing: TextButton(
                          onPressed: _busy ? null : _resolve,
                          child: const Text('Conciliar'),
                        ),
                      ),
                    ),
                  if (_pendingAttempt == null &&
                      !_paymentSending &&
                      !_alreadyPaid &&
                      !_resolutionSending &&
                      !_tenderStatusUnknown)
                    FilledButton.icon(
                      onPressed: _busy ? null : _collect,
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Registrar cobro'),
                    ),
                  if (_busy) const Center(child: CircularProgressIndicator()),
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Si se pierde la conexión al crear la venta o registrar el cobro, vuelve a enviar el mismo comando guardado. El identificador persistido evita duplicarlo.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
              ],
            ),
          ),
  );
}

Widget _cardTitle(String title) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: Text(
    title,
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
  ),
);
String _str(dynamic v) => v?.toString() ?? '';
