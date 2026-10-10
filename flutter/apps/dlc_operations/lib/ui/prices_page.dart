import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../branch_status.dart';
import '../country_catalog.dart';
import '../format.dart';
import '../haptics.dart';
import '../labels.dart';
import '../live_form.dart';
import '../main.dart' show OperationsController;
import '../preferences.dart';
import '../validators.dart';
import 'form_sheet.dart';
import 'kit.dart';
import 'motion.dart';
import 'util.dart';

/// Variation between the price in force and the next scheduled one.
class PriceMove {
  const PriceMove(this.percent, this.effectiveAt);
  final double percent;
  final DateTime? effectiveAt;
}

/// Next scheduled price of the same product and mode, as a percentage change.
PriceMove? nextMove(
  Map<String, dynamic> current,
  List<Map<String, dynamic>> upcoming,
) {
  final now = parseAmount(current['priceUsdPerUnit']);
  if (now == null || now <= 0) return null;
  for (final u in upcoming) {
    if (u['fuelProductId'] == current['fuelProductId'] &&
        u['serviceMode'] == current['serviceMode']) {
      final next = parseAmount(u['priceUsdPerUnit']);
      if (next == null) return null;
      return PriceMove(
        (next - now) / now * 100,
        DateTime.tryParse(asText(u['effectiveAt']))?.toLocal(),
      );
    }
  }
  return null;
}

/// "Marcador": the price is the protagonist, in the fuel's colour.
class PriceMarker extends StatelessWidget {
  const PriceMarker({
    required this.price,
    required this.currency,
    this.move,
    super.key,
  });
  final Map<String, dynamic> price;
  final String currency;
  final PriceMove? move;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final prefs = context.prefs;
    final name = asText(price['productName'], 'Combustible');
    final family = DlcColors.fuelFamilyOf(null, name);
    final fuelColor = c.fuelText(family);
    final perLiter = parseAmount(price['priceUsdPerUnit']);
    final shown = perLiter == null
        ? null
        : unitPrice(perLiter, prefs.unit);
    final mode = serviceModeLabel(price['serviceMode']);
    final effective = DateTime.tryParse(asText(price['effectiveAt']))?.toLocal();
    final m = move;
    final arrowIcon = m == null || m.percent == 0
        ? CupertinoIcons.minus
        : m.percent > 0
        ? CupertinoIcons.arrow_up_right
        : CupertinoIcons.arrow_down_right;
    final moveText = m == null
        ? 'Sin cambios programados'
        : '${formatVariation(m.percent)}${m.effectiveAt == null ? '' : ' desde ${_day(m.effectiveAt!)}'}';
    return DlcCard(
      padding: const EdgeInsets.all(14),
      semanticLabel:
          '$name, $mode: ${shown == null ? 'sin precio' : prefs.money(shown, currency: currency)} por ${prefs.unit == VolumeUnit.gallons ? 'galón' : 'litro'}. $moveText',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: DlcColors.fuelFill(family),
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(width: 12, height: 12),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            Text(mode, style: TextStyle(color: c.muted, fontSize: 12)),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                shown == null ? '--' : prefs.money(shown, currency: currency),
                style: TextStyle(
                  fontSize: 32,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  color: fuelColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Text(
              'por ${prefs.unit == VolumeUnit.gallons ? 'galón' : 'litro'}',
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(arrowIcon, size: 16, color: c.ink),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    moveText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ),
              ],
            ),
            if (effective != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Vigente desde ${_day(effective)}',
                  style: TextStyle(color: c.muted, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _day(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// Price per the user's unit (per litre or per gallon).
double unitPrice(double pricePerLiter, VolumeUnit unit) =>
    unit == VolumeUnit.gallons ? pricePerLiter * kLitersPerGallon : pricePerLiter;

/// Precios: per branch, markers with variation; proposing opens a sheet.
class PricesView extends StatefulWidget {
  const PricesView({
    required this.controller,
    required this.branches,
    super.key,
  });
  final OperationsController controller;
  final List<BranchSummary> branches;
  @override
  State<PricesView> createState() => _PricesViewState();
}

class _PricesViewState extends State<PricesView> {
  int _tick = 0;

  Future<void> _refresh() async {
    setState(() => _tick++);
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Widget build(BuildContext context) {
    final branches = widget.branches;
    if (branches.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          EmptyState(
            icon: CupertinoIcons.tag,
            title: 'Sin sucursales en esta vista',
            message: 'Cambia el país o la sucursal en la barra de alcance.',
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          for (final (i, b) in branches.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Entrance(
                index: i,
                child: _BranchPrices(
                  key: ValueKey('${b.id}-$_tick'),
                  branch: b,
                  api: widget.controller.api,
                  showHeader: branches.length > 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BranchPrices extends StatefulWidget {
  const _BranchPrices({
    required this.branch,
    required this.api,
    required this.showHeader,
    super.key,
  });
  final BranchSummary branch;
  final EmployeeSession api;
  final bool showHeader;
  @override
  State<_BranchPrices> createState() => _BranchPricesState();
}

class _BranchPricesState extends State<_BranchPrices> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _current = const [], _upcoming = const [];
  List<Map<String, dynamic>> _offers = const [];
  Set<String> _permissions = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.branch.isActive) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = widget.branch.id;
      final values = await Future.wait<dynamic>([
        widget.api.fuelPrices(id),
        widget.api.capabilities(branchId: id),
        widget.api.branchConfiguration(id),
      ]);
      if (!mounted) return;
      final prices = values[0] as Map<String, dynamic>;
      final config = values[2] as Map<String, dynamic>;
      setState(() {
        _current = asMaps(prices['current']);
        _upcoming = asMaps(prices['upcoming']);
        _permissions = (values[1] as List<String>).toSet();
        _offers = [
          for (final o in asMaps(config['fuelOffers']))
            if (o['status'] == 'active') o,
        ];
      });
    } on DlcApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _propose() async {
    final done = await showPriceProposalSheet(
      context,
      api: widget.api,
      branch: widget.branch,
      offers: _offers,
    );
    if (done == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final b = widget.branch;
    final currency = branchCurrency(b);
    final canPropose = _permissions.contains('price.propose');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.showHeader ? b.name : 'Precios vigentes',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    widget.showHeader
                        ? '${countryName(b.countryCode)} · moneda $currency'
                        : '${b.name} · moneda $currency',
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (canPropose)
              FilledButton.icon(
                onPressed: _loading ? null : _propose,
                icon: const Icon(CupertinoIcons.plus, size: 16),
                label: const Text('Proponer'),
                style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (!b.isActive)
          const EmptyState(
            icon: CupertinoIcons.hammer,
            title: 'Sucursal en preparación',
            message: 'Los precios se programan durante el alta de la sucursal.',
          )
        else if (_loading && _current.isEmpty)
          const SkeletonPulse(
            child: Column(
              children: [
                SkeletonBox(height: 140, radius: 18),
                SizedBox(height: 10),
                SkeletonBox(height: 140, radius: 18),
              ],
            ),
          )
        else if (_error != null)
          ErrorState(message: _error!, onRetry: _load)
        else if (_current.isEmpty)
          EmptyState(
            icon: CupertinoIcons.tag,
            title: 'Sin precios vigentes',
            message:
                'Propón un precio por combustible; otra persona autorizada debe aprobarlo.',
            actionLabel: canPropose ? 'Proponer precio' : null,
            onAction: canPropose ? _propose : null,
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final cols = box.maxWidth >= 560 ? 2 : 1;
              final w = (box.maxWidth - 10 * (cols - 1)) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final p in _current)
                    SizedBox(
                      width: w,
                      child: PriceMarker(
                        price: p,
                        currency: currency,
                        move: nextMove(p, _upcoming),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// Bottom-sheet form to propose a fuel price (replaces the old dialog).
/// Returns true when the proposal was sent.
Future<bool?> showPriceProposalSheet(
  BuildContext context, {
  required EmployeeSession api,
  required BranchSummary branch,
  required List<Map<String, dynamic>> offers,
}) {
  if (offers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Activa primero al menos un combustible de la sucursal.'),
      ),
    );
    return Future.value(false);
  }
  return showFormSheet<bool>(
    context,
    builder: (context, scroll) =>
        _PriceSheet(api: api, branch: branch, offers: offers, scroll: scroll),
  );
}

class _PriceSheet extends StatefulWidget {
  const _PriceSheet({
    required this.api,
    required this.branch,
    required this.offers,
    required this.scroll,
  });
  final EmployeeSession api;
  final BranchSummary branch;
  final List<Map<String, dynamic>> offers;
  final ScrollController scroll;
  @override
  State<_PriceSheet> createState() => _PriceSheetState();
}

class _PriceSheetState extends State<_PriceSheet> {
  final _price = TextEditingController(), _reason = TextEditingController();
  late String _productId = asText(widget.offers.first['fuelProductId']);
  String _mode = 'full_service';
  bool _busy = false, _restored = false;
  String? _error;
  late final DraftBinder _draft;

  @override
  void initState() {
    super.initState();
    _draft = DraftBinder(
      store: SessionKeyValueStore(widget.api),
      key: 'price.${widget.branch.id}',
      fields: {'price': _price, 'reason': _reason},
      extra: () => {'product': _productId, 'mode': _mode},
    );
    _draft.restore().then((saved) {
      if (saved == null || !mounted) return;
      setState(() {
        _restored = true;
        final p = saved['product'];
        if (p != null &&
            widget.offers.any((o) => asText(o['fuelProductId']) == p)) {
          _productId = p;
        }
        _mode = saved['mode'] == 'self_service' ? 'self_service' : 'full_service';
      });
    });
  }

  @override
  void dispose() {
    _draft.dispose();
    _price.dispose();
    _reason.dispose();
    super.dispose();
  }

  String? _priceError(String? v) =>
      positiveNumber(v, field: 'El precio', maxDecimals: 4, max: 1000000);
  String? _reasonError(String? v) =>
      minLengthText(v, 10, field: 'El motivo') ??
      maxLengthText(v, 500, field: 'El motivo');

  bool get _valid =>
      _priceError(_price.text) == null && _reasonError(_reason.text) == null;

  String get _productName {
    final o = widget.offers.firstWhere(
      (o) => asText(o['fuelProductId']) == _productId,
      orElse: () => widget.offers.first,
    );
    return asText(o['fuelName'] ?? o['productName'], 'Combustible');
  }

  Future<void> _pickProduct() async {
    final picked = await showSelectSheet<String>(
      context,
      title: 'Combustible',
      selected: _productId,
      options: [
        for (final o in widget.offers)
          SelectOption(
            asText(o['fuelProductId']),
            asText(o['fuelName'] ?? o['productName'], 'Combustible'),
          ),
      ],
    );
    if (picked != null) {
      setState(() => _productId = picked);
      _draft.touch();
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.proposeFuelPrice(
        widget.branch.id,
        fuelProductId: _productId,
        serviceMode: _mode,
        price: _price.text.trim().replaceAll(',', '.'),
        effectiveAt: DateTime.now().add(const Duration(hours: 2)),
        reason: _reason.text,
      );
      await _draft.clear();
      Haptics.success();
      if (mounted) Navigator.pop(context, true);
    } on DlcApiException catch (e) {
      Haptics.error();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = branchCurrency(widget.branch);
    final c = context.dlc;
    return FormSheetLayout(
      title: 'Proponer precio',
      subtitle: '${widget.branch.name} · $currency por litro',
      icon: CupertinoIcons.tag,
      scrollController: widget.scroll,
      submitLabel: 'Enviar propuesta',
      busy: _busy,
      onSubmit: _valid ? _submit : null,
      children: [
        if (_restored) ...[
          DraftBanner(
            onDiscard: () async {
              await _draft.clear();
              _price.clear();
              _reason.clear();
              setState(() => _restored = false);
            },
          ),
          const SizedBox(height: 12),
        ],
        SelectField<String>(
          label: 'Combustible',
          valueLabel: _productName,
          icon: CupertinoIcons.drop,
          onTap: _pickProduct,
        ),
        const SizedBox(height: 14),
        const Text('Modalidad', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedFilter<String>(
          selected: _mode,
          options: const {
            'full_service': 'Servicio completo',
            'self_service': 'Autoservicio',
          },
          onChanged: (v) {
            setState(() => _mode = v);
            _draft.touch();
          },
        ),
        const SizedBox(height: 14),
        LiveTextField(
          controller: _price,
          label: 'Precio por litro ($currency)',
          helper: 'Hasta 4 decimales.',
          keyboardType: LiveTextField.decimal(),
          validator: _priceError,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 10),
        LiveTextField(
          controller: _reason,
          label: 'Motivo de la propuesta',
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          validator: _reasonError,
          onChanged: () => setState(() {}),
        ),
        Text(
          'La propuesta queda pendiente y otra persona autorizada debe aprobarla.',
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          ErrorState(message: _error!),
        ],
      ],
    );
  }
}
