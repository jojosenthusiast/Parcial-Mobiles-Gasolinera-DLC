import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../branch_status.dart';
import '../country_catalog.dart';
import '../format.dart';
import '../haptics.dart';
import '../labels.dart';
import '../main.dart' show OperationsController, PumpDetailPage;
import '../preferences.dart';
import '../tank_levels.dart';
import 'data_widgets.dart';
import 'kit.dart';
import 'motion.dart';
import 'util.dart';

/// One pump row: name, fuels it dispenses, status in words and icon.
class PumpRow extends StatelessWidget {
  const PumpRow({required this.pump, required this.onTap, super.key});
  final Map<String, dynamic> pump;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final status = asText(
      pump['physicalStatus'] ?? pump['status'],
      'unknown',
    );
    final spec = statusSpec(status);
    final fuels = asMaps(pump['nozzles'])
        .map((n) => asText(n['fuelName'] ?? n['productName']))
        .where((v) => v.isNotEmpty)
        .toSet()
        .join(' · ');
    return DlcCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.container(spec.tone),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(CupertinoIcons.gauge, color: c.foreground(spec.tone)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pumpTitle(pump),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (fuels.isNotEmpty)
                  Text(
                    fuels,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(status, compact: true),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(CupertinoIcons.chevron_right, size: 16, color: c.muted),
        ],
      ),
    );
  }
}

enum _EquipTab { pumps, tanks }

/// "Bombas y tanques". One branch: segmented Bombas | Tanques. Several
/// branches (general manager): grouped by branch, collapsible, each branch
/// loads its equipment when opened (master to detail).
class PumpsTanksView extends StatefulWidget {
  const PumpsTanksView({
    required this.controller,
    required this.branches,
    super.key,
  });
  final OperationsController controller;

  /// Branches in the current scope.
  final List<BranchSummary> branches;

  @override
  State<PumpsTanksView> createState() => _PumpsTanksViewState();
}

class _PumpsTanksViewState extends State<PumpsTanksView> {
  _EquipTab _tab = _EquipTab.pumps;
  int _refreshTick = 0;

  OperationsController get _c => widget.controller;

  Future<void> _refresh() async {
    if (widget.branches.length == 1) {
      await _c.refresh();
    } else {
      setState(() => _refreshTick++);
    }
  }

  Future<void> _openPump(BuildContext context, BranchSummary branch, Map<String, dynamic> pump) async {
    final id = asText(pump['id']);
    if (id.isEmpty) return;
    if (_c.branch?.id != branch.id) await _c.selectBranch(branch);
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            PumpDetailPage(controller: _c, pumpId: id, snapshot: pump),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final prefs = context.prefs;
    final branches = widget.branches;
    if (branches.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          EmptyState(
            icon: CupertinoIcons.gauge,
            title: 'Sin sucursales en esta vista',
            message: 'Cambia el país o la sucursal en la barra de alcance.',
          ),
        ],
      );
    }
    if (branches.length == 1) {
      final branch = branches.first;
      final tanks = asMaps(asMap(_c.dashboard['inventory'])['tanks']);
      final pumps = _c.pumps;
      final loading = _c.loadingBranch && pumps.isEmpty && tanks.isEmpty;
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            _BranchBanner(branch: branch, subtitle: '${pumps.length} bombas · ${tanks.length} tanques'),
            const SizedBox(height: 12),
            SegmentedFilter<_EquipTab>(
              semanticLabel: 'Equipo',
              selected: _tab,
              options: const {
                _EquipTab.pumps: 'Bombas',
                _EquipTab.tanks: 'Tanques',
              },
              onChanged: (t) => setState(() => _tab = t),
            ),
            const SizedBox(height: 12),
            if (_c.error != null) ...[
              ErrorState(
                message: _c.error!,
                details: _c.errorDetails,
                onRetry: _c.refresh,
              ),
              const SizedBox(height: 12),
            ],
            if (loading)
              const PageSkeleton(rows: 2)
            else if (_tab == _EquipTab.pumps)
              ..._pumpList(context, branch, pumps)
            else
              ..._tankList(tanks, prefs),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Text(
            '${branches.length} sucursales',
            style: TextStyle(color: c.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final (i, b) in branches.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Entrance(
                index: i,
                child: _BranchGroup(
                  key: ValueKey('${b.id}-$_refreshTick'),
                  branch: b,
                  api: _c.api,
                  initiallyOpen: branches.length <= 2,
                  onOpenPump: (pump) => _openPump(context, b, pump),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _pumpList(
    BuildContext context,
    BranchSummary branch,
    List<Map<String, dynamic>> pumps,
  ) {
    if (pumps.isEmpty) {
      return [
        const EmptyState(
          icon: CupertinoIcons.gauge,
          title: 'Sin bombas visibles',
          message: 'No hay dispensadores registrados en esta sucursal.',
        ),
      ];
    }
    return [
      for (final (i, p) in pumps.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Entrance(
            index: i,
            child: PumpRow(
              pump: p,
              onTap: asText(p['id']).isEmpty
                  ? null
                  : () => _openPump(context, branch, p),
            ),
          ),
        ),
    ];
  }

  List<Widget> _tankList(List<Map<String, dynamic>> tanks, DisplayPrefs prefs) {
    if (tanks.isEmpty) {
      return [
        const EmptyState(
          icon: CupertinoIcons.drop,
          title: 'Sin tanques configurados',
          message: 'Cuando la sucursal registre sus tanques aparecerán aquí.',
        ),
      ];
    }
    final sorted = [...tanks]
      ..sort(
        (a, b) => (tankPercent(a) ?? 101).compareTo(tankPercent(b) ?? 101),
      );
    return [
      ResponsiveWrap(
        children: [for (final t in sorted) TankCard(tank: t, prefs: prefs)],
      ),
    ];
  }
}

/// Prominent branch identity (name first), used as header and group title.
class _BranchBanner extends StatelessWidget {
  const _BranchBanner({required this.branch, this.subtitle});
  final BranchSummary branch;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return DlcCard(
      weight: CardWeight.quiet,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(CupertinoIcons.bag, color: c.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  branch.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  [
                    countryName(branch.countryCode),
                    ?subtitle,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchGroup extends StatefulWidget {
  const _BranchGroup({
    required this.branch,
    required this.api,
    required this.onOpenPump,
    this.initiallyOpen = false,
    super.key,
  });
  final BranchSummary branch;
  final EmployeeSession api;
  final bool initiallyOpen;
  final ValueChanged<Map<String, dynamic>> onOpenPump;
  @override
  State<_BranchGroup> createState() => _BranchGroupState();
}

class _BranchGroupState extends State<_BranchGroup> {
  late bool _open = widget.initiallyOpen;
  bool _loading = false, _loaded = false;
  String? _error;
  List<Map<String, dynamic>> _pumps = const [], _tanks = const [];

  @override
  void initState() {
    super.initState();
    if (_open) _load();
  }

  Future<void> _load() async {
    if (!widget.branch.isActive) {
      setState(() => _loaded = true);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.api.dispensers(widget.branch.id),
        widget.api.branchDashboard(widget.branch.id),
      ]);
      if (!mounted) return;
      setState(() {
        _pumps = results[0] as List<Map<String, dynamic>>;
        _tanks = asMaps(asMap((results[1] as Map<String, dynamic>)['inventory'])['tanks']);
        _loaded = true;
      });
    } on DlcApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle() {
    Haptics.selection();
    setState(() => _open = !_open);
    if (_open && !_loaded && !_loading) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final prefs = context.prefs;
    final b = widget.branch;
    final critical = _tanks
        .where((t) => (tankPercent(t) ?? 100) <= kTankCriticalMaxPercent)
        .length;
    final summary = !b.isActive
        ? statusLabel(b.status)
        : _loaded
        ? '${_pumps.length} bombas · ${_tanks.length} tanques'
        : 'Toca para ver bombas y tanques';
    return DlcCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            label: '${b.name}, ${countryName(b.countryCode)}. $summary',
            excludeSemantics: true,
            child: InkWell(
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.brandContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(CupertinoIcons.bag, color: c.brand),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${countryName(b.countryCode)} · $summary',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                          if (critical > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: ToneChip(
                                label: critical == 1
                                    ? '1 tanque crítico'
                                    : '$critical tanques críticos',
                                tone: DlcStatus.critical,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      _open
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_down,
                      size: 16,
                      color: c.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(),
                  const SizedBox(height: 8),
                  if (!b.isActive)
                    const EmptyState(
                      icon: CupertinoIcons.hammer,
                      title: 'Sucursal en preparación',
                      message:
                          'Sus bombas y tanques aparecen cuando la sucursal esté activa.',
                    )
                  else if (_loading && !_loaded)
                    const SkeletonPulse(
                      child: Column(
                        children: [
                          SkeletonBox(height: 64, radius: 14),
                          SizedBox(height: 8),
                          SkeletonBox(height: 64, radius: 14),
                        ],
                      ),
                    )
                  else if (_error != null)
                    ErrorState(message: _error!, onRetry: _load)
                  else ...[
                    if (_pumps.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('Sin bombas registradas.'),
                      ),
                    for (final p in _pumps)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: PumpRow(
                          pump: p,
                          onTap: asText(p['id']).isEmpty
                              ? null
                              : () => widget.onOpenPump(p),
                        ),
                      ),
                    if (_tanks.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ResponsiveWrap(
                        children: [
                          for (final t in _tanks)
                            TankCard(tank: t, prefs: prefs, branchName: b.name),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
