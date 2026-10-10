import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/material.dart';

import 'customer_qr_scanner_screen.dart';

class DispenseScreen extends StatefulWidget {
  const DispenseScreen({
    required this.api,
    required this.branchId,
    required this.nozzle,
    required this.permissions,
    super.key,
  });
  final EmployeeSession api;
  final String branchId;
  final Map<String, dynamic> nozzle;
  final Set<String> permissions;
  @override
  State<DispenseScreen> createState() => _DispenseScreenState();
}

class _DispenseScreenState extends State<DispenseScreen> {
  Map<String, dynamic>? _authorization;
  bool _loading = true;
  String? _error;
  String get _nozzleId => _str(widget.nozzle['id']);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _error = null;
    try {
      final rows = await widget.api.dispenseAuthorizations(widget.branchId);
      final matches = rows
          .where((r) => _str(r['nozzleId']) == _nozzleId)
          .toList();
      matches.sort(
        (a, b) => _str(b['createdAt']).compareTo(_str(a['createdAt'])),
      );
      _authorization = matches
          .where(
            (r) => [
              'authorized',
              'dispensing',
              'unknown',
              'posting',
            ].contains(_str(r['status'])),
          )
          .firstOrNull;
    } on DlcApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _authorize() async {
    final c = TextEditingController();
    String mode = 'volume', unit = 'liter';
    final value = await showDialog<(String, String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Autorizar despacho'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Definir por'),
                items: const [
                  DropdownMenuItem(value: 'volume', child: Text('Volumen')),
                  DropdownMenuItem(
                    value: 'amount',
                    child: Text('Dinero (USD)'),
                  ),
                ],
                onChanged: (v) => setDialog(() => mode = v ?? mode),
              ),
              if (mode == 'volume')
                DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'Unidad'),
                  items: const [
                    DropdownMenuItem(value: 'liter', child: Text('Litros')),
                    DropdownMenuItem(
                      value: 'gallon_us',
                      child: Text('Galones (EE. UU.)'),
                    ),
                  ],
                  onChanged: (v) => setDialog(() => unit = v ?? unit),
                ),
              TextField(
                controller: c,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: mode == 'amount'
                      ? 'Monto objetivo (USD)'
                      : unit == 'liter'
                      ? 'Volumen máximo (litros)'
                      : 'Volumen máximo (galones)',
                ),
              ),
              if (mode == 'amount')
                Text(
                  'Se calculará con el precio vigente del combustible: USD ' +
                      _str(
                        widget.nozzle['priceUsdPerUnit'] ??
                            'consultado al autorizar',
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
              onPressed: () => Navigator.pop(ctx, (mode, unit, c.text.trim())),
              child: const Text('Autorizar'),
            ),
          ],
        ),
      ),
    );
    c.dispose();
    if (value == null || value.$3.isEmpty) return;
    await _mutate(() async {
      _authorization = await widget.api.authorizeDispense(
        widget.branchId,
        _nozzleId,
        value.$3,
        mode: value.$1,
        volumeUnit: value.$2,
      );
    });
  }

  Future<void> _start() async {
    final row = _authorization;
    if (row == null) return;
    await _mutate(() async {
      _authorization = await widget.api.startDispense(
        widget.branchId,
        _str(row['id']),
        _int(row['version']),
        reason: 'Inicio manual confirmado por el operador',
      );
    });
  }

  Future<void> _complete() async {
    final row = _authorization;
    if (row == null) return;
    final amount = TextEditingController(
      text: _str(row['progressLiters'] ?? row['progressL']),
    );
    final document = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar despacho completado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Autorizado hasta ${_str(row['reservedLiters'] ?? row['reservedL'])} L',
            ),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Lectura final validada (litros)',
              ),
            ),
            TextField(
              controller: document,
              decoration: const InputDecoration(
                labelText: 'Documento/lectura (opcional)',
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
                Navigator.pop(ctx, (amount.text.trim(), document.text.trim())),
            child: const Text('Completar'),
          ),
        ],
      ),
    );
    amount.dispose();
    document.dispose();
    if (result == null || result.$1.isEmpty) return;
    await _mutate(() async {
      _authorization = await widget.api.completeDispense(
        widget.branchId,
        _str(row['id']),
        _int(row['version']),
        result.$1,
        documentReference: result.$2,
      );
      if (widget.permissions.contains('sale.create')) {
        final sale = await widget.api.createSaleFromDispatch(
          widget.branchId,
          _str(row['id']),
        );
        await _linkCustomer(sale);
      }
    });
  }

  Future<void> _postSale() async {
    final row = _authorization;
    if (row == null) return;
    await _mutate(() async {
      final sale = await widget.api.createSaleFromDispatch(
        widget.branchId,
        _str(row['id']),
      );
      await _linkCustomer(sale);
    });
  }

  Future<void> _linkCustomer(Map<String, dynamic> sale) async {
    final saleId = _str(sale['id']);
    if (saleId.isEmpty || !mounted) return;
    final code = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Vincular Cliente (opcional)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                keyboardType: TextInputType.text,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Código de Cliente',
                  helperText:
                      'Escanea el QR de la app o escribe el código. Identifica la cuenta; no autoriza canjes.',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final scanned = await Navigator.of(ctx).push<String>(
                    MaterialPageRoute<String>(
                      builder: (_) => const CustomerQrScannerScreen(),
                    ),
                  );
                  if (scanned != null && ctx.mounted) {
                    setDialog(() => code.text = scanned);
                  }
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Escanear QR'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Omitir'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, code.text.trim()),
              child: const Text('Vincular'),
            ),
          ],
        ),
      ),
    );
    code.dispose();
    if (value == null || value.trim().isEmpty || !mounted) return;
    await widget.api.linkCustomerToSale(widget.branchId, saleId, value.trim());
  }

  Future<void> _mutate(Future<void> Function() fn) async {
    setState(() => _loading = true);
    _error = null;
    try {
      await fn();
      await _load();
    } on DlcApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = _authorization;
    final status = _str(row?['status']);
    return Scaffold(
      appBar: AppBar(
        title: Text('Despacho · ${_str(widget.nozzle['code'])}'),
        actions: [
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
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Captura manual, sin control de hardware'),
                      subtitle: Text(
                        'Esta pantalla registra autorización y volumen verificado por el operador. No controla físicamente el surtidor ni sustituye una integración certificada.',
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.water_drop_outlined),
                      title: Text(
                        _str(
                          widget.nozzle['fuelName'] ??
                              widget.nozzle['productName'],
                        ),
                      ),
                      subtitle: Text(
                        '${_str(widget.nozzle['serviceMode'])} · precio ${_str(row?['priceUsdPerUnit'] ?? widget.nozzle['priceUsdPerUnit'] ?? 'consultado al autorizar')}',
                      ),
                    ),
                  ),
                  if (row == null)
                    if (widget.permissions.contains('dispense.authorize'))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: FilledButton.icon(
                          onPressed: _authorize,
                          icon: const Icon(Icons.lock_open_outlined),
                          label: const Text('Autorizar volumen'),
                        ),
                      ),
                  if (row != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Estado: $status',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Reserva: ${_str(row['reservedLiters'] ?? row['reservedL'])} L · avance: ${_str(row['progressLiters'] ?? row['progressL'])} L',
                            ),
                            if (status == 'authorized' &&
                                widget.permissions.contains(
                                  'dispense.authorize',
                                ))
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: FilledButton(
                                  onPressed: _start,
                                  child: const Text('Confirmar inicio físico'),
                                ),
                              ),
                            if (status == 'dispensing' &&
                                widget.permissions.contains(
                                  'dispense.authorize',
                                ))
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: FilledButton(
                                  onPressed: _complete,
                                  child: const Text(
                                    'Capturar lectura final y cerrar',
                                  ),
                                ),
                              ),
                            if (status == 'completed' &&
                                widget.permissions.contains('sale.create'))
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: OutlinedButton(
                                  onPressed: _postSale,
                                  child: const Text(
                                    'Asegurar registro de venta',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

String _str(dynamic v) => v?.toString() ?? '';
int _int(dynamic v) => int.tryParse('$v') ?? 1;
