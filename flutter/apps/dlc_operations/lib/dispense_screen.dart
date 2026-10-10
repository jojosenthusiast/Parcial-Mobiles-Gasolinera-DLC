import 'package:dlc_api/dlc_api.dart';
import 'app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;

import 'customer_qr_scanner_screen.dart';
import 'dispense_logic.dart';
import 'ui/kit.dart' show ToneChip;
import 'ui/sheets.dart';
import 'haptics.dart';
import 'live_form.dart';
import 'validators.dart';

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
        builder: (ctx, setDialog) => ValidatedFormDialog(
          title: 'Autorizar despacho',
          submitLabel: 'Autorizar',
          cancelLabel: 'Volver',
          onCancel: () => Navigator.pop(ctx),
          onSubmit: () => Navigator.pop(ctx, (mode, unit, c.text.trim())),
          isValid: () => positiveNumber(c.text, field: 'El valor') == null,
          contentBuilder: (ctx, changed) => Column(
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
                onChanged: (v) {
                  Haptics.selection();
                  setDialog(() => mode = v ?? mode);
                  changed();
                },
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
                  onChanged: (v) {
                    Haptics.selection();
                    setDialog(() => unit = v ?? unit);
                    changed();
                  },
                ),
              LiveTextField(
                controller: c,
                keyboardType: LiveTextField.decimal(),
                label: mode == 'amount'
                    ? 'Monto objetivo (USD)'
                    : unit == 'liter'
                    ? 'Volumen máximo (litros)'
                    : 'Volumen máximo (galones)',
                validator: (v) => positiveNumber(
                  v,
                  field: mode == 'amount' ? 'El monto' : 'El volumen',
                  maxDecimals: mode == 'amount' ? 2 : 3,
                ),
                onChanged: changed,
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
    final reserved = double.tryParse(
      _str(row['reservedLiters'] ?? row['reservedL']),
    );
    final started = double.tryParse(_str(row['startLiters'] ?? '')) ?? 0;
    String? finalReadingError(String? v) => finalNotBelowInitial(
      v,
      started,
      field: 'La lectura final',
    ) ?? (reserved != null && parseDecimal(v)! > reserved
        ? 'La lectura final no puede superar lo autorizado ($reserved L).'
        : null);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => ValidatedFormDialog(
        title: 'Registrar despacho completado',
        submitLabel: 'Completar',
        cancelLabel: 'Volver',
        onCancel: () => Navigator.pop(ctx),
        onSubmit: () =>
            Navigator.pop(ctx, (amount.text.trim(), document.text.trim())),
        isValid: () => finalReadingError(amount.text) == null,
        contentBuilder: (ctx, changed) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Autorizado hasta ${_str(row['reservedLiters'] ?? row['reservedL'])} L',
            ),
            LiveTextField(
              controller: amount,
              keyboardType: LiveTextField.decimal(),
              label: 'Lectura final validada (litros)',
              validator: finalReadingError,
              onChanged: changed,
            ),
            LiveTextField(
              controller: document,
              label: 'Documento/lectura (opcional)',
              maxLength: 120,
              validator: (v) => maxLengthText(v, 120, field: 'El documento'),
              onChanged: changed,
            ),
          ],
        ),
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
                icon: const Icon(CupertinoIcons.qrcode_viewfinder),
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

  Future<void> _recover(DispenseRecovery action) async {
    final row = _authorization;
    if (row == null) return;
    final copy = recoveryCopy(action);
    final id = _str(row['id']);
    final version = _int(row['version']);
    if (action == DispenseRecovery.reconcileNoFlow) {
      final evidence = await showReasonSheet(
        context,
        title: copy.title,
        message: copy.message,
        fieldLabel: 'Referencia de evidencia',
        confirmLabel: 'Siguiente',
        minLength: 3,
        maxLength: 120,
      );
      if (evidence == null || !mounted) return;
      final reason = await showReasonSheet(
        context,
        title: copy.title,
        message: 'Explica por qué se concluye que no hubo flujo.',
        fieldLabel: 'Motivo',
        confirmLabel: copy.confirm,
      );
      if (reason == null) return;
      await _mutate(() async {
        _authorization = await widget.api.reconcileDispenseNoFlow(
          widget.branchId,
          id,
          version,
          evidenceReference: evidence,
          reason: reason,
        );
      });
      return;
    }
    final reason = await showReasonSheet(
      context,
      title: copy.title,
      message: copy.message,
      fieldLabel: 'Motivo',
      confirmLabel: copy.confirm,
      destructive: copy.destructive,
      minLength: 5,
    );
    if (reason == null) return;
    await _mutate(() async {
      _authorization = action == DispenseRecovery.cancel
          ? await widget.api.cancelDispense(
              widget.branchId,
              id,
              version,
              reason: reason,
            )
          : await widget.api.markDispenseUnknown(
              widget.branchId,
              id,
              version,
              reason: reason,
            );
    });
  }

  Future<void> _mutate(Future<void> Function() fn) async {
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
            icon: const Icon(CupertinoIcons.refresh),
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
                      color: context.dlc.criticalContainer,
                      child: ListTile(
                        leading: const Icon(CupertinoIcons.exclamationmark_circle),
                        title: Text(_error!),
                      ),
                    ),
                  const Card(
                    child: ListTile(
                      leading: Icon(CupertinoIcons.info_circle),
                      title: Text('Captura manual'),
                      subtitle: Text(
                        'Aquí registras la autorización y el volumen que verificaste en el surtidor. La app no controla la bomba.',
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(CupertinoIcons.drop),
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
                          icon: const Icon(CupertinoIcons.lock_open),
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
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ToneChip(
                                label: dispenseStateInfo(status).label,
                                tone: dispenseStateInfo(status).tone,
                              ),
                            ),
                            if (dispenseStateInfo(status).hint.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(dispenseStateInfo(status).hint),
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
                                    'Registrar lectura final',
                                  ),
                                ),
                              ),
                            if (widget.permissions.contains('dispense.authorize'))
                              for (final action in recoveriesFor(status))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: OutlinedButton(
                                    key: Key('recover-${action.name}'),
                                    onPressed: () => _recover(action),
                                    child: Text(recoveryCopy(action).title),
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
