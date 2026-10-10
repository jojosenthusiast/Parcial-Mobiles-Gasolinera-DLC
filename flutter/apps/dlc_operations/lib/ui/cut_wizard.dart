import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../cut_logic.dart';
import '../cut_window.dart';
import '../format.dart';
import '../haptics.dart';
import '../live_form.dart';
import '../main.dart' show CutDetailPage, OperationsController, listOf, mapOf, stateLabel;
import '../procurement_screen.dart';
import '../purchase_prefill.dart';
import '../tank_levels.dart';
import '../validators.dart';
import 'form_sheet.dart';
import 'kit.dart';
import 'sheets.dart';

/// Guided branch cut (DESIGN rubric): choose the cut, capture the pump
/// readings, register fuel receipts and losses, then review the summary and
/// close. Each checkpoint saves on the server, so leaving never loses work.
class CutWizardPage extends StatefulWidget {
  const CutWizardPage({
    required this.controller,
    this.initialCut,
    this.date,
    super.key,
  });
  final OperationsController controller;
  final Map<String, dynamic>? initialCut;
  final DateTime? date;
  @override
  State<CutWizardPage> createState() => _CutWizardPageState();
}

class _PostedMovement {
  const _PostedMovement(this.tankLabel, this.liters, this.detail);
  final String tankLabel, liters, detail;
}

class _CutWizardPageState extends State<CutWizardPage> {
  CutStep _step = CutStep.choose;
  List<Map<String, dynamic>> _cuts = const [];
  Map<String, dynamic>? _cut;
  Map<String, dynamic> _assets = const {},
      _progress = const {},
      _reconciliation = const {};
  bool _loading = true, _working = false;
  String? _error;

  final Map<String, TextEditingController> _readings = {};
  final Map<String, String> _cellErrors = {};
  final Map<String, String> _pendingAttach = {};
  final List<_PostedMovement> _receipts = [], _losses = [];

  OperationsController get c => widget.controller;
  String get _branchId => c.branch!.id;
  String get _cutId => '${_cut?['id'] ?? ''}';
  String? get _status => _cut?['status']?.toString();
  int get _version => int.tryParse('${_cut?['version'] ?? 1}') ?? 1;
  DateTime get _date => widget.date ?? DateTime.now();

  MeterGrid get _grid => buildMeterGrid(
    listOf(_assets['nozzles']).map(mapOf),
  );
  List<TankOutlook> get _tanks =>
      tankOutlooks(listOf(_assets['tanks']).map(mapOf));

  @override
  void initState() {
    super.initState();
    _loadCuts();
  }

  @override
  void dispose() {
    for (final t in _readings.values) {
      t.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String id) =>
      _readings.putIfAbsent(id, () => TextEditingController());

  Future<void> _loadCuts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _cuts = await c.api.dailyCuts(_branchId, _date);
      final initial = widget.initialCut;
      if (initial != null && _cut == null) {
        _cut = _cuts.where((x) => x['id'] == initial['id']).firstOrNull ?? initial;
        await _reload();
        _step = cutPastCapture(_status) ? CutStep.summary : CutStep.readings;
      } else if (_cut != null) {
        _cut = _cuts.where((x) => x['id'] == _cut!['id']).firstOrNull ?? _cut;
      }
    } on DlcApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reload() async {
    final results = await Future.wait<Map<String, dynamic>>([
      c.api.cutAssets(_branchId, _cutId),
      c.api.cutProgress(_branchId, _cutId),
    ]);
    _assets = results[0];
    _progress = results[1];
    final updated = mapOf(_assets['cut']);
    if (updated.isNotEmpty) _cut = {...?_cut, ...updated};
    if (cutPastCapture(_status)) {
      try {
        _reconciliation = await c.api.cutReconciliation(_branchId, _cutId);
      } on DlcApiException {
        _reconciliation = const {};
      }
    } else {
      _reconciliation = const {};
    }
  }

  Future<void> _guard(Future<void> Function() action, {String? success}) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
      Haptics.success();
      if (success != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      }
    } on DlcApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _select(Map<String, dynamic> cut) => _guard(() async {
    _cut = cut;
    _cellErrors.clear();
    _pendingAttach.clear();
    await _reload();
  });

  Future<void> _generate() => _guard(() async {
    _cuts = await c.api.generateDailyCuts(_branchId, _date);
  });

  Future<void> _openCut() => _guard(() async {
    await c.api.openCut(_branchId, _cutId, _version);
    await _reload();
  }, success: 'Corte abierto.');

  // ---- readings -----------------------------------------------------------

  Map<String, String> get _typed => {
    for (final e in _readings.entries) e.key: e.value.text,
  };

  Future<bool> _saveReadings() async {
    final grid = _grid;
    final ready = readyToSave(grid, _typed);
    if (ready.isEmpty) return true;
    var allOk = true;
    await _guard(() async {
      for (final cell in ready) {
        try {
          var readingId = _pendingAttach[cell.nozzleId];
          if (readingId == null) {
            final reading = await c.api.captureReading(
              _branchId,
              cell.nozzleId,
              _readings[cell.nozzleId]!.text.trim().replaceAll(',', '.'),
              cell.meterVersion,
            );
            readingId = '${reading['id'] ?? ''}';
            if (readingId.isEmpty) {
              throw const DlcApiException(
                'La lectura se guardó pero falta su identificador. Actualiza el corte.',
              );
            }
            _pendingAttach[cell.nozzleId] = readingId;
          }
          final fresh = await c.api.cutAssets(_branchId, _cutId);
          final version = int.tryParse('${mapOf(fresh['cut'])['version'] ?? _version}') ?? _version;
          await c.api.attachCutMeter(_branchId, _cutId, cell.nozzleId, readingId, version);
          _pendingAttach.remove(cell.nozzleId);
          _cellErrors.remove(cell.nozzleId);
        } on DlcApiException catch (e) {
          allOk = false;
          _cellErrors[cell.nozzleId] = meterServerMessage(e.message);
        }
      }
      await _reload();
    });
    if (!allOk && mounted) {
      setState(() => _error = 'Algunas lecturas no se guardaron. Revisa los mensajes en cada manguera.');
    }
    return allOk;
  }

  // ---- movements ----------------------------------------------------------

  Future<void> _addMovement({required bool loss}) async {
    final tanks = _tanks;
    if (tanks.isEmpty) return;
    final result = await showFormSheet<_PostedMovement>(
      context,
      builder: (ctx, scroll) => _MovementSheet(
        api: c.api,
        branchId: _branchId,
        tanks: tanks,
        loss: loss,
        scroll: scroll,
      ),
    );
    if (result == null) return;
    setState(() => (loss ? _losses : _receipts).add(result));
    await _guard(_reload);
  }

  // ---- summary ------------------------------------------------------------

  Future<void> _measure(TankOutlook tank) async {
    final saved = await showFormSheet<bool>(
      context,
      initialSize: .75,
      builder: (ctx, scroll) => _TankMeasureSheet(
        tank: tank,
        scroll: scroll,
        onSave: (l, w, t) async {
          final fresh = await c.api.cutAssets(_branchId, _cutId);
          final version = int.tryParse('${mapOf(fresh['cut'])['version'] ?? _version}') ?? _version;
          await c.api.captureTankMeasure(_branchId, _cutId, tank.tankId, version, l, w, t);
        },
      ),
    );
    if (saved == true) await _guard(_reload, success: 'Medición registrada.');
  }

  Future<void> _prepare() => _guard(() async {
    final fresh = await c.api.cutAssets(_branchId, _cutId);
    final version = int.tryParse('${mapOf(fresh['cut'])['version'] ?? _version}') ?? _version;
    await c.api.prepareCut(_branchId, _cutId, version);
    await _reload();
  }, success: 'Conciliación preparada.');

  Future<void> _close() async {
    final ok = await showConfirmSheet(
      context,
      title: 'Cerrar corte',
      message:
          'El cierre es definitivo y queda auditado. Confirma que revisaste ventas, recepciones, pérdidas y niveles de tanque.',
      confirmLabel: 'Cerrar corte',
      icon: CupertinoIcons.lock,
    );
    if (!ok) return;
    await _guard(() async {
      await c.api.closeCut(_branchId, _cutId, _version);
      await _reload();
    }, success: 'Corte cerrado y auditado.');
  }

  void _requestPurchase(TankOutlook t) {
    final api = c.api;
    final branch = c.branch!;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProcurementScreen(
          api: api,
          branchId: branch.id,
          permissions: c.permissions,
          currency: currencyForCountry(branch.countryCode),
          prefill: PurchasePrefill(
            fuelProductId: t.fuelProductId,
            tankId: t.tankId,
            tankCode: t.code,
            fuelName: t.fuelName,
            suggestedLiters: suggestedPurchaseLiters(t.capacityLiters, t.measuredLiters),
          ),
        ),
      ),
    );
  }

  // ---- navigation ---------------------------------------------------------

  bool get _canLeaveChoose =>
      _cut != null && (cutAcceptsCapture(_status) || cutPastCapture(_status));

  Future<void> _next() async {
    if (_step == CutStep.readings && cutAcceptsCapture(_status)) {
      if (invalidTyped(_grid, _typed).isNotEmpty) return;
      final ok = await _saveReadings();
      if (!ok || !mounted) return;
    }
    final i = _step.index;
    if (i < CutStep.values.length - 1) {
      setState(() => _step = CutStep.values[i + 1]);
    }
  }

  void _back() {
    final i = _step.index;
    if (i > 0) setState(() => _step = CutStep.values[i - 1]);
  }

  bool get _nextEnabled {
    if (_working || _loading) return false;
    return switch (_step) {
      CutStep.choose => _canLeaveChoose,
      CutStep.readings => invalidTyped(_grid, _typed).isEmpty,
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    final last = _step == CutStep.summary;
    final jumpChoose = _step == CutStep.choose;
    return Scaffold(
      appBar: AppBar(title: const Text('Corte guiado')),
      body: SafeArea(
        child: Column(
          children: [
            _StepHeader(step: _step),
            if (_working || _loading) const LinearProgressIndicator(minHeight: 3),
            Expanded(
              child: ListView(
                key: ValueKey(_step),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ErrorState(
                        message: _error!,
                        onRetry: _cut == null ? _loadCuts : () => _guard(_reload),
                      ),
                    ),
                  ..._stepBody(context),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    if (!jumpChoose)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _working ? null : _back,
                          icon: const Icon(CupertinoIcons.chevron_left, size: 16),
                          label: const Text('Atrás'),
                        ),
                      ),
                    if (!jumpChoose && !last) const SizedBox(width: 12),
                    if (!last)
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          key: const Key('cut-next'),
                          onPressed: _nextEnabled ? _next : null,
                          icon: const Icon(CupertinoIcons.chevron_right, size: 16),
                          label: Text(
                            _step == CutStep.readings ? 'Guardar y seguir' : 'Siguiente',
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

  List<Widget> _stepBody(BuildContext context) => switch (_step) {
    CutStep.choose => _chooseBody(context),
    CutStep.readings => _readingsBody(context),
    CutStep.receipts => _movementsBody(context, loss: false),
    CutStep.losses => _movementsBody(context, loss: true),
    CutStep.summary => _summaryBody(context),
  };

  // ---- step 0 -------------------------------------------------------------

  List<Widget> _chooseBody(BuildContext context) {
    final colors = context.dlc;
    final canCapture = c.can('cut.capture');
    return [
      Text(
        'Cada día hay dos cortes. Elige el que vas a trabajar.',
        style: TextStyle(color: colors.muted),
      ),
      const SizedBox(height: 12),
      if (!_loading && _cuts.isEmpty && _error == null) ...[
        EmptyState(
          icon: CupertinoIcons.doc_text,
          title: 'Aún no hay cortes para hoy',
          message: 'Genera los dos cortes del día. El servidor define las ventanas horarias.',
          actionLabel: canCapture ? 'Generar los dos cortes' : null,
          actionIcon: CupertinoIcons.sparkles,
          onAction: canCapture && !_working ? _generate : null,
        ),
      ],
      for (final cut in _cuts) ...[
        _CutChoice(
          cut: cut,
          selected: _cut?['id'] == cut['id'],
          onTap: _working ? null : () => _select(cut),
        ),
        const SizedBox(height: 10),
      ],
      if (_cut != null && cutNeedsOpening(_status)) ...[
        DlcCard(
          weight: CardWeight.quiet,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Este corte aún no está abierto.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Al abrirlo se congela el equipo esperado (bombas y tanques).',
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: canCapture && !_working ? _openCut : null,
                icon: const Icon(CupertinoIcons.lock_open, size: 18),
                label: const Text('Abrir corte'),
              ),
              if (!canCapture)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Tu rol no puede abrir cortes.',
                    style: TextStyle(color: colors.muted, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }

  // ---- step 1 -------------------------------------------------------------

  List<Widget> _readingsBody(BuildContext context) {
    final colors = context.dlc;
    final grid = _grid;
    final editable = cutAcceptsCapture(_status) && c.can('cut.capture');
    if (grid.cells.isEmpty) {
      return const [
        EmptyState(
          icon: CupertinoIcons.gauge,
          title: 'Sin mangueras en este corte',
          message: 'El corte no tiene equipo esperado. Revisa la infraestructura de la sucursal.',
        ),
      ];
    }
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              '${grid.capturedCount} de ${grid.total} lecturas registradas',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (grid.pendingCount == 0)
            const ToneChip(label: 'Completo', tone: DlcStatus.optimal),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        editable
            ? 'Escribe el totalizador acumulado de cada manguera. Debe ser igual o mayor al anterior.'
            : 'Solo lectura: el corte no admite capturas con tu rol o estado.',
        style: TextStyle(color: colors.muted, fontSize: 13),
      ),
      const SizedBox(height: 10),
      for (final pump in grid.dispensers) ...[
        DlcCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bomba $pump', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final cell in grid.forDispenser(pump)) _meterRow(context, cell, editable),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _meterRow(BuildContext context, MeterCell cell, bool editable) {
    final colors = context.dlc;
    final error = _cellErrors[cell.nozzleId];
    if (cell.captured) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(CupertinoIcons.checkmark_circle_fill, color: colors.optimal, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${cell.fuelLabel} · manguera ${cell.nozzleCode}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text('Registrada', style: TextStyle(color: colors.optimal, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    final ctrl = _ctrl(cell.nozzleId);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LiveTextField(
            key: ValueKey('reading-${cell.nozzleId}'),
            controller: ctrl,
            label: '${cell.fuelLabel} · manguera ${cell.nozzleCode}',
            hint: cell.initial == null ? 'Totalizador' : 'Anterior ${groupDigits(cell.initial!, decimals: 1)}',
            helper: cell.initial == null ? null : 'Lectura anterior: ${cell.initial}',
            keyboardType: LiveTextField.decimal(),
            validator: (v) => (v ?? '').trim().isEmpty ? null : validateMeterReading(v, cell.initial),
            onChanged: editable ? () => setState(() => _cellErrors.remove(cell.nozzleId)) : null,
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(CupertinoIcons.exclamationmark_circle, size: 16, color: colors.critical),
                  const SizedBox(width: 6),
                  Expanded(child: Text(error, style: TextStyle(color: colors.critical, fontSize: 13))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---- steps 2 and 3 ------------------------------------------------------

  List<Widget> _movementsBody(BuildContext context, {required bool loss}) {
    final colors = context.dlc;
    final posted = loss ? _losses : _receipts;
    final totals = fuelTotalsFromProgress(_progress);
    final allowed = loss ? c.can('inventory.adjust.request') : c.can('inventory.receive');
    final canAdd = cutAcceptsCapture(_status) && allowed;
    final hasAny = totals.any((t) => (loss ? t.lossLiters : t.receiptsLiters) > 0);
    return [
      Text(
        loss
            ? 'Registra mermas, derrames o diferencias con su causa. Si no hubo pérdidas, sigue al resumen.'
            : 'Registra el combustible que llegó durante la ventana: proveedor, folio y litros. Si no hubo entregas, sigue.',
        style: TextStyle(color: colors.muted),
      ),
      const SizedBox(height: 12),
      if (hasAny)
        DlcCard(
          weight: CardWeight.quiet,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loss ? 'Pérdidas en la ventana' : 'Recepciones en la ventana',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              for (final t in totals)
                if ((loss ? t.lossLiters : t.receiptsLiters) > 0)
                  Text('${t.name}: ${groupDigits(loss ? t.lossLiters : t.receiptsLiters, decimals: 1)} L'),
            ],
          ),
        ),
      if (posted.isNotEmpty) ...[
        SectionHeader(title: 'Registradas ahora', trailing: '${posted.length}'),
        for (final p in posted)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DlcCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(CupertinoIcons.checkmark_circle_fill, color: colors.optimal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p.tankLabel} · ${p.liters} L', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(p.detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.muted, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      const SizedBox(height: 8),
      if (canAdd)
        FilledButton.icon(
          key: Key(loss ? 'add-loss' : 'add-receipt'),
          onPressed: _working ? null : () => _addMovement(loss: loss),
          icon: Icon(loss ? CupertinoIcons.drop_triangle : CupertinoIcons.cube_box, size: 18),
          label: Text(loss ? 'Registrar pérdida' : 'Registrar recepción'),
        )
      else
        DlcCard(
          weight: CardWeight.quiet,
          child: Text(
            !cutAcceptsCapture(_status)
                ? 'El corte ya no admite movimientos.'
                : 'Sin permiso: tu rol no puede registrar ${loss ? 'pérdidas' : 'recepciones'}.',
            style: TextStyle(color: colors.muted),
          ),
        ),
    ];
  }

  // ---- step 4 -------------------------------------------------------------

  List<Widget> _summaryBody(BuildContext context) {
    final colors = context.dlc;
    final totals = fuelTotalsFromProgress(_progress);
    final tanks = _tanks;
    final readiness = cutReadiness(_grid, tanks);
    final status = _status;
    final closed = status == 'closed';
    final canCapture = cutAcceptsCapture(status) && c.can('cut.capture');
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              '${cutName(_cut?['slot'])} ${cutWindowLabel(_cut ?? const {})}'.trim(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ToneChip(
            label: stateLabel('${status ?? 'pending'}'),
            tone: closed ? DlcStatus.optimal : DlcStatus.info,
          ),
        ],
      ),
      SectionHeader(title: 'Ventas, recepciones y pérdidas', icon: CupertinoIcons.chart_bar),
      if (totals.isEmpty)
        const EmptyState(
          icon: CupertinoIcons.drop,
          title: 'Sin movimientos',
          message: 'Todavía no hay ventas ni movimientos en esta ventana.',
        ),
      for (final t in totals)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DlcCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text('Ventas ${groupDigits(t.soldGallons, decimals: 1)} gal'),
                    Text('Recepciones ${groupDigits(t.receiptsLiters, decimals: 1)} L'),
                    Text('Pérdidas ${groupDigits(t.lossLiters, decimals: 1)} L'),
                  ],
                ),
                Text(
                  '(${groupDigits(t.soldLiters, decimals: 1)} L vendidos)',
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      SectionHeader(title: 'Nivel de tanques al cierre', icon: CupertinoIcons.drop),
      for (final t in tanks) _tankRow(context, t, canCapture),
      if (!closed) ...[
        const SizedBox(height: 12),
        if (!readiness.ready && cutAcceptsCapture(status))
          DlcCard(
            color: colors.warningContainer,
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(CupertinoIcons.exclamationmark_triangle, color: colors.warning, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Falta: ${readiness.missing.join(' y ')}.')),
              ],
            ),
          ),
        if (cutAcceptsCapture(status))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: FilledButton.icon(
              key: const Key('cut-prepare'),
              onPressed: _working || !readiness.ready || !c.can('cut.submit') ? null : _prepare,
              icon: const Icon(CupertinoIcons.checkmark_rectangle, size: 18),
              label: const Text('Preparar conciliación'),
            ),
          ),
        if (status == 'prepared' || status == 'inReview') ...[
          const SizedBox(height: 10),
          if (status == 'inReview')
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Hay diferencias por revisar. Abre la conciliación para aprobarlas.'),
            ),
          FilledButton.icon(
            key: const Key('cut-close'),
            onPressed: _working || status != 'prepared' || !c.can('cut.close') ? null : _close,
            icon: const Icon(CupertinoIcons.lock, size: 18),
            label: const Text('Cerrar corte'),
          ),
        ],
      ],
      if (closed)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: ToneChip(label: 'Corte cerrado y auditado', tone: DlcStatus.optimal),
        ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _cut == null
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CutDetailPage(controller: c, initial: _cut!),
                ),
              ).then((_) => _guard(_reload)),
        icon: const Icon(CupertinoIcons.doc_text_search, size: 18),
        label: const Text('Ver conciliación detallada'),
      ),
    ];
  }

  Widget _tankRow(BuildContext context, TankOutlook t, bool canCapture) {
    final colors = context.dlc;
    final percent = t.percent;
    final status = t.status;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DlcCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${t.code} · ${t.fuelName}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (status != null)
                  ToneChip(label: tankStatusText(status), tone: status)
                else
                  const ToneChip(label: 'Sin medición', tone: DlcStatus.warning),
              ],
            ),
            const SizedBox(height: 8),
            if (percent != null) ...[
              LinearProgressIndicator(
                value: percent / 100,
                minHeight: 8,
                borderRadius: BorderRadius.circular(6),
                color: colors.foreground(status!),
                backgroundColor: colors.surfaceAlt,
              ),
              const SizedBox(height: 6),
              Text(
                '${groupDigits(percent, decimals: 0)} % · ${groupDigits(t.measuredLiters!, decimals: 0)} de ${groupDigits(t.capacityLiters ?? 0, decimals: 0)} L',
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
            ],
            if (t.replenishment != Replenishment.none)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: DlcCard(
                  weight: CardWeight.quiet,
                  color: t.replenishment == Replenishment.urgent
                      ? colors.criticalContainer
                      : colors.warningContainer,
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.replenishment == Replenishment.urgent
                            ? 'Reabastecer ya: nivel crítico.'
                            : 'Planea reabastecer: nivel medio.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (c.can('purchase.create'))
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: Key('buy-${t.tankId}'),
                            onPressed: () => _requestPurchase(t),
                            icon: const Icon(CupertinoIcons.cart_badge_plus, size: 16),
                            label: const Text('Solicitar compra'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (canCapture)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _working ? null : () => _measure(t),
                  icon: const Icon(CupertinoIcons.pencil, size: 16),
                  label: Text(t.measured ? 'Corregir medición' : 'Registrar medición'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});
  final CutStep step;
  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Semantics(
        container: true,
        label: 'Paso ${step.index + 1} de ${CutStep.values.length}: ${step.label}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final s in CutStep.values) ...[
                  Expanded(
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: s.index <= step.index ? colors.brand : colors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  if (s != CutStep.values.last) const SizedBox(width: 4),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Paso ${step.index + 1} de ${CutStep.values.length}',
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
            Text(
              step.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _CutChoice extends StatelessWidget {
  const _CutChoice({required this.cut, required this.selected, required this.onTap});
  final Map<String, dynamic> cut;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    final status = '${cut['status'] ?? 'pending'}';
    final closed = status == 'closed';
    final window = cutWindowLabel(cut);
    return Semantics(
      selected: selected,
      button: true,
      child: DlcCard(
        onTap: onTap,
        color: selected ? colors.brandContainer : null,
        child: Row(
          children: [
            Icon(
              selected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
              color: selected ? colors.brand : colors.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Corte ${cutName(cut['slot']).toLowerCase()}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    window.isEmpty ? 'Ventana por definir' : 'Ventana $window',
                    style: TextStyle(color: colors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ToneChip(
              label: stateLabel(status),
              tone: closed ? DlcStatus.optimal : DlcStatus.info,
            ),
          ],
        ),
      ),
    );
  }
}

/// Receipt / loss form. Calls the API itself so server errors show inside the
/// sheet; pops the posted movement on success.
class _MovementSheet extends StatefulWidget {
  const _MovementSheet({
    required this.api,
    required this.branchId,
    required this.tanks,
    required this.loss,
    required this.scroll,
  });
  final EmployeeSession api;
  final String branchId;
  final List<TankOutlook> tanks;
  final bool loss;
  final ScrollController scroll;
  @override
  State<_MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends State<_MovementSheet> {
  late TankOutlook _tank = widget.tanks.first;
  String _cause = 'evaporation';
  final _supplier = TextEditingController(),
      _folio = TextEditingController(),
      _liters = TextEditingController(),
      _explain = TextEditingController();
  late final String _commandId = widget.api.newCommandId();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _supplier.dispose();
    _folio.dispose();
    _liters.dispose();
    _explain.dispose();
    super.dispose();
  }

  String? _litersError(String? v) => widget.loss
      ? validateLossLiters(v, _tank.measuredLiters ?? _tank.capacityLiters)
      : validateReceiptLiters(v, freeCapacity(_tank.capacityLiters, _tank.measuredLiters));

  bool get _valid {
    if (_litersError(_liters.text) != null) return false;
    if (widget.loss) return validateLossExplanation(_explain.text) == null;
    return validateSupplier(_supplier.text) == null && validateFolio(_folio.text) == null;
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final liters = _liters.text.trim().replaceAll(',', '.');
      if (widget.loss) {
        await widget.api.recordFuelLoss(
          widget.branchId,
          _tank.tankId,
          liters: liters,
          reasonCode: _cause,
          explanation: _explain.text,
          commandId: _commandId,
        );
      } else {
        await widget.api.recordFuelReceipt(
          widget.branchId,
          _tank.tankId,
          liters: liters,
          folio: _folio.text,
          supplier: _supplier.text,
          commandId: _commandId,
        );
      }
      Haptics.success();
      if (!mounted) return;
      Navigator.pop(
        context,
        _PostedMovement(
          '${_tank.code} · ${_tank.fuelName}',
          liters,
          widget.loss
              ? '${kLossCauses[_cause]}: ${_explain.text.trim()}'
              : '${_supplier.text.trim()} · folio ${_folio.text.trim()}',
        ),
      );
    } on DlcApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    return FormSheetLayout(
      title: widget.loss ? 'Registrar pérdida' : 'Registrar recepción',
      icon: widget.loss ? CupertinoIcons.drop_triangle : CupertinoIcons.cube_box,
      scrollController: widget.scroll,
      submitLabel: widget.loss ? 'Registrar pérdida' : 'Registrar recepción',
      busy: _busy,
      onSubmit: _valid ? _submit : null,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ErrorState(message: _error!),
          ),
        SelectField<String>(
          label: 'Tanque',
          valueLabel: '${_tank.code} · ${_tank.fuelName}',
          onTap: () async {
            final id = await showSelectSheet<String>(
              context,
              title: 'Tanque',
              selected: _tank.tankId,
              options: [
                for (final t in widget.tanks)
                  SelectOption(t.tankId, '${t.code} · ${t.fuelName}'),
              ],
            );
            if (id != null) {
              setState(() => _tank = widget.tanks.firstWhere((t) => t.tankId == id));
            }
          },
        ),
        const SizedBox(height: 12),
        if (widget.loss) ...[
          SelectField<String>(
            label: 'Causa',
            valueLabel: kLossCauses[_cause] ?? _cause,
            onTap: () async {
              final v = await showSelectSheet<String>(
                context,
                title: 'Causa de la pérdida',
                selected: _cause,
                options: [
                  for (final e in kLossCauses.entries) SelectOption(e.key, e.value),
                ],
              );
              if (v != null) setState(() => _cause = v);
            },
          ),
          const SizedBox(height: 12),
        ] else ...[
          LiveTextField(
            controller: _supplier,
            label: 'Proveedor',
            validator: validateSupplier,
            onChanged: () => setState(() {}),
          ),
          LiveTextField(
            controller: _folio,
            label: 'Folio del documento',
            validator: validateFolio,
            onChanged: () => setState(() {}),
          ),
        ],
        LiveTextField(
          controller: _liters,
          label: widget.loss ? 'Litros perdidos' : 'Litros recibidos',
          keyboardType: LiveTextField.decimal(),
          validator: _litersError,
          onChanged: () => setState(() {}),
        ),
        if (widget.loss)
          LiveTextField(
            controller: _explain,
            label: 'Explicación',
            hint: 'Qué pasó y cómo se detectó',
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            validator: validateLossExplanation,
            onChanged: () => setState(() {}),
          ),
        Text(
          widget.loss
              ? 'La pérdida descuenta el saldo del tanque y queda auditada.'
              : 'La recepción suma al saldo del tanque y queda ligada al folio.',
          style: TextStyle(color: colors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _TankMeasureSheet extends StatefulWidget {
  const _TankMeasureSheet({required this.tank, required this.scroll, required this.onSave});
  final TankOutlook tank;
  final ScrollController scroll;
  final Future<void> Function(String liters, String water, String temp) onSave;
  @override
  State<_TankMeasureSheet> createState() => _TankMeasureSheetState();
}

class _TankMeasureSheetState extends State<_TankMeasureSheet> {
  late final _liters = TextEditingController(
    text: widget.tank.measuredLiters == null ? '' : '${widget.tank.measuredLiters}',
  );
  final _water = TextEditingController(), _temp = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _liters.dispose();
    _water.dispose();
    _temp.dispose();
    super.dispose();
  }

  String? _litersError(String? v) => tankMeasureLiters(v, widget.tank.capacityLiters);
  String? _waterError(String? v) => optionalNumber(v, field: 'El agua', maxDecimals: 3);
  String? _tempError(String? v) =>
      optionalNumber(v, field: 'La temperatura', signed: true, maxDecimals: 3);

  bool get _valid => allValid([
    _litersError(_liters.text),
    _waterError(_water.text),
    _tempError(_temp.text),
  ]);

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(
        _liters.text.trim().replaceAll(',', '.'),
        _water.text.trim().replaceAll(',', '.'),
        _temp.text.trim().replaceAll(',', '.'),
      );
      if (mounted) Navigator.pop(context, true);
    } on DlcApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FormSheetLayout(
    title: 'Medir ${widget.tank.code}',
    subtitle: widget.tank.fuelName,
    icon: CupertinoIcons.drop,
    scrollController: widget.scroll,
    submitLabel: 'Guardar medición',
    busy: _busy,
    onSubmit: _valid ? _save : null,
    children: [
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ErrorState(message: _error!),
        ),
      LiveTextField(
        controller: _liters,
        label: 'Combustible observado (L)',
        keyboardType: LiveTextField.decimal(),
        validator: _litersError,
        onChanged: () => setState(() {}),
      ),
      LiveTextField(
        controller: _water,
        label: 'Agua (L, opcional)',
        keyboardType: LiveTextField.decimal(),
        validator: _waterError,
        onChanged: () => setState(() {}),
      ),
      LiveTextField(
        controller: _temp,
        label: 'Temperatura °C (opcional)',
        keyboardType: LiveTextField.decimal(signed: true),
        validator: _tempError,
        onChanged: () => setState(() {}),
      ),
    ],
  );
}
