import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../charts.dart';
import '../format.dart';
import '../main.dart' show OperationsController;
import '../network_metrics.dart';
import '../preferences.dart';
import '../scope.dart';
import '../tank_levels.dart';
import 'data_widgets.dart';
import 'kit.dart';
import 'motion.dart';
import 'util.dart';

/// A tank flattened with the branch it belongs to.
@immutable
class InventoryTank {
  const InventoryTank({required this.branchName, required this.tank});
  final String branchName;
  final Map<String, dynamic> tank;
  double? get percent => tankPercent(tank);
}

/// Severity of a tank for the alert centre: 0 critical, 1 medium, 2 optimal,
/// 3 without measurement. Lower comes first.
int tankSeverity(double? percent) {
  if (percent == null) return 3;
  return switch (tankStatusForPercent(percent)) {
    DlcStatus.critical => 0,
    DlcStatus.medium => 1,
    _ => 2,
  };
}

/// Tanks sorted by severity, then by lowest level.
List<InventoryTank> sortBySeverity(Iterable<InventoryTank> tanks) {
  final list = tanks.toList();
  list.sort((a, b) {
    final bySeverity = tankSeverity(a.percent).compareTo(tankSeverity(b.percent));
    if (bySeverity != 0) return bySeverity;
    return (a.percent ?? 101).compareTo(b.percent ?? 101);
  });
  return list;
}

/// Inventory: alert centre sorted by severity + gauges of every tank.
class InventoryView extends StatefulWidget {
  const InventoryView({
    required this.controller,
    required this.branches,
    required this.scope,
    super.key,
  });
  final OperationsController controller;
  final List<BranchSummary> branches;
  final ScopeState scope;
  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  List<InventoryTank> _networkTanks = const [];
  bool _loading = false;
  String? _error;
  DateTime? _loadedAt;
  int _ticket = 0;

  bool get _single => widget.branches.length == 1;

  @override
  void initState() {
    super.initState();
    if (!_single) _load();
  }

  @override
  void didUpdateWidget(InventoryView old) {
    super.didUpdateWidget(old);
    final before = old.branches.map((b) => b.id).join(',');
    final after = widget.branches.map((b) => b.id).join(',');
    if (before != after && !_single) _load();
  }

  Future<void> _load() async {
    if (_single) return;
    final ticket = ++_ticket;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.controller.api.networkDashboard(
        days: 1,
        countryCode: widget.scope.countryCode,
      );
      if (!mounted || ticket != _ticket) return;
      final data = NetworkDashboardData.parse(
        raw,
        countryByBranchId: {
          for (final b in widget.branches) b.id: b.countryCode,
        },
      );
      final ids = widget.branches.map((b) => b.id).toSet();
      setState(() {
        _networkTanks = [
          for (final r in data.rows)
            if (ids.contains(r.id))
              for (final t in r.tanks)
                InventoryTank(branchName: r.name, tank: t),
        ];
        _loadedAt = DateTime.now();
      });
    } on DlcApiException catch (e) {
      if (mounted && ticket == _ticket) setState(() => _error = e.message);
    } finally {
      if (mounted && ticket == _ticket) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() => _single ? widget.controller.refresh() : _load();

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final prefs = context.prefs;
    if (widget.branches.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          EmptyState(
            icon: CupertinoIcons.cube_box,
            title: 'Sin sucursales en esta vista',
            message: 'Cambia el país o la sucursal en la barra de alcance.',
          ),
        ],
      );
    }
    final branch = widget.branches.first;
    final tanks = _single
        ? [
            for (final t in asMaps(
              asMap(widget.controller.dashboard['inventory'])['tanks'],
            ))
              InventoryTank(branchName: branch.name, tank: t),
          ]
        : _networkTanks;
    final loading = _single
        ? widget.controller.loadingBranch && tanks.isEmpty
        : _loading && tanks.isEmpty;
    if (loading) return const SingleChildScrollView(child: PageSkeleton());
    final error = _single ? widget.controller.error : _error;
    final sorted = sortBySeverity(tanks);
    final critical = sorted.where((t) => tankSeverity(t.percent) == 0).toList();
    final medium = sorted.where((t) => tankSeverity(t.percent) == 1).length;
    final optimal = sorted.where((t) => tankSeverity(t.percent) == 2).length;
    final totalLiters = tanks.fold<double>(
      0,
      (s, t) => s + (parseAmount(t.tank['onHandLiters']) ?? 0),
    );
    var i = 0;
    Widget step(Widget w) => Entrance(index: i++, child: w);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          if (error != null) ...[
            ErrorState(
              message: error,
              details: _single ? widget.controller.errorDetails : null,
              onRetry: _refresh,
              staleSince: tanks.isEmpty || _loadedAt == null
                  ? null
                  : formatClock(_loadedAt!),
            ),
            const SizedBox(height: 12),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          if (tanks.isEmpty && error == null)
            EmptyState(
              icon: CupertinoIcons.cube_box,
              title: 'Sin tanques en esta vista',
              message:
                  'Cuando las sucursales registren tanques verás aquí su nivel y las alertas.',
              actionLabel: 'Actualizar',
              actionIcon: CupertinoIcons.refresh,
              onAction: _refresh,
            )
          else if (tanks.isNotEmpty) ...[
            step(
              AlertStrip(
                items: [
                  for (final t in critical)
                    AlertItem(
                      title:
                          'Tanque ${asText(t.tank['fuelName'], 'de combustible')} ${asText(t.tank['code'])}'.trim(),
                      detail:
                          '${t.percent!.toStringAsFixed(0)} % · ${prefs.volumeCard(parseAmount(t.tank['onHandLiters']) ?? 0)} disponibles',
                      severity: 'critical',
                      branchName: _single ? null : t.branchName,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            step(
              HeroKpi(
                label: 'Combustible en tanques',
                value: litersToUnit(totalLiters, prefs.unit),
                format: (v) =>
                    '${groupDigits(v, decimals: 0)} ${prefs.unit.symbol}',
                caption:
                    '${tanks.length} ${tanks.length == 1 ? 'tanque' : 'tanques'}${_single ? ' · ${branch.name}' : ' · ${widget.branches.length} sucursales'}',
                icon: CupertinoIcons.drop,
              ),
            ),
            const SizedBox(height: 10),
            step(
              MiniKpiRow(
                tiles: [
                  MiniKpi(
                    icon: DlcStatus.critical.icon,
                    value: '${critical.length}',
                    label: 'Nivel crítico (30 % o menos)',
                    tone: critical.isEmpty ? DlcStatus.optimal : DlcStatus.critical,
                  ),
                  MiniKpi(
                    icon: DlcStatus.medium.icon,
                    value: '$medium',
                    label: 'Nivel medio (31 a 60 %)',
                    tone: medium == 0 ? DlcStatus.optimal : DlcStatus.medium,
                  ),
                  MiniKpi(
                    icon: DlcStatus.optimal.icon,
                    value: '$optimal',
                    label: 'Nivel óptimo (más de 60 %)',
                    tone: DlcStatus.optimal,
                  ),
                ],
              ),
            ),
            const SectionHeader(
              title: 'Por tipo de combustible',
              icon: CupertinoIcons.chart_bar,
            ),
            DlcCard(
              child: TankLevelBars(
                levels: fuelLevelsFromTanks([for (final t in tanks) t.tank]),
              ),
            ),
            SectionHeader(
              title: 'Centro de alertas',
              icon: CupertinoIcons.bell,
              trailing: 'Más urgentes primero',
            ),
            ..._grouped(context, sorted, prefs, c),
          ],
        ],
      ),
    );
  }

  List<Widget> _grouped(
    BuildContext context,
    List<InventoryTank> sorted,
    DisplayPrefs prefs,
    DlcColors c,
  ) {
    if (_single) {
      return [
        ResponsiveWrap(
          children: [
            for (final t in sorted) TankCard(tank: t.tank, prefs: prefs),
          ],
        ),
      ];
    }
    final byBranch = <String, List<InventoryTank>>{};
    for (final t in sorted) {
      byBranch.putIfAbsent(t.branchName, () => []).add(t);
    }
    // Branches ordered by their worst tank.
    final names = byBranch.keys.toList()
      ..sort(
        (a, b) => tankSeverity(byBranch[a]!.first.percent).compareTo(
          tankSeverity(byBranch[b]!.first.percent),
        ),
      );
    return [
      for (final name in names) ...[
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: Row(
            children: [
              Icon(CupertinoIcons.bag, size: 16, color: c.muted),
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
        ),
        ResponsiveWrap(
          children: [
            for (final t in byBranch[name]!)
              TankCard(tank: t.tank, prefs: prefs, branchName: name),
          ],
        ),
      ],
    ];
  }
}
