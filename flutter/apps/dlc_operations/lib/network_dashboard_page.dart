import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;

import 'app_theme.dart';
import 'branch_status.dart';
import 'charts.dart';
import 'country_catalog.dart';
import 'format.dart';
import 'haptics.dart';
import 'network_metrics.dart';
import 'preferences.dart';
import 'scope.dart';
import 'ui/data_widgets.dart';
import 'ui/gauges.dart';
import 'ui/kit.dart';
import 'ui/motion.dart';

/// Status shown for the server's per-branch `inventoryRisk`.
DlcStatus inventoryRiskStatus(String risk) => switch (risk) {
  'normal' => DlcStatus.optimal,
  'warning' => DlcStatus.medium,
  'critical' => DlcStatus.critical,
  _ => DlcStatus.info,
};

String inventoryRiskText(String risk) => switch (risk) {
  'normal' => 'Inventario normal',
  'warning' => 'Inventario en aviso',
  'critical' => 'Inventario crítico',
  _ => 'Inventario sin datos',
};

String formatUsd(double v) => 'US\$ ${groupedNumber(v, decimals: 2)}';
String formatLiters(double v) => '${groupedNumber(v)} L';

/// "2026-10-08" -> "08/10"
String shortDay(String isoDate) {
  final parts = isoDate.split('-');
  return parts.length == 3 ? '${parts[2].substring(0, 2)}/${parts[1]}' : isoDate;
}

/// Sales of the branches in [rows] split by branch currency. Currencies are
/// never added together.
MoneyTotals salesByCurrency(Iterable<NetworkBranchRow> rows) {
  final totals = MoneyTotals();
  for (final r in rows) {
    totals.add(currencyForCountry(r.countryCode), r.salesUsd);
  }
  return totals;
}

/// Consolidated dashboard for the network.
///
/// Standalone (default) it keeps its own country / branch filters. With
/// [embedded] it lives inside the app shell: no app bar, no filters of its
/// own, everything comes from the persistent [scope].
class NetworkDashboardPage extends StatefulWidget {
  const NetworkDashboardPage({
    required this.api,
    required List<BranchSummary> branches,
    this.onOpenBranch,
    this.onOpenOnboarding,
    this.embedded = false,
    this.scope = ScopeState.network,
    super.key,
  }) : _allBranches = branches;
  final EmployeeSession api;
  final List<BranchSummary> _allBranches;
  final ValueChanged<BranchSummary>? onOpenBranch;

  /// Call to action of the empty state (General Manager only); `null` hides it.
  final VoidCallback? onOpenOnboarding;
  final bool embedded;
  final ScopeState scope;

  /// Only ACTIVE branches feed the consolidated metrics.
  List<BranchSummary> get branches => activeBranches(_allBranches);

  @override
  State<NetworkDashboardPage> createState() => _NetworkDashboardPageState();
}

class _NetworkDashboardPageState extends State<NetworkDashboardPage> {
  int _days = 7;
  String? _countryState;
  String? _branchState;
  NetworkDashboardData _data = NetworkDashboardData.empty;
  List<NetworkCountry> _serverCountries = const [];
  bool _loading = true;
  String? _error, _errorDetails;
  int _request = 0;
  DateTime? _loadedAt;

  String? get _country =>
      widget.embedded ? widget.scope.countryCode : _countryState;
  String? get _branchId => widget.embedded
      ? (widget.scope.branchIds.length == 1
            ? widget.scope.branchIds.first
            : null)
      : _branchState;

  Map<String, String> get _countryByBranch => {
    for (final b in widget.branches) b.id: b.countryCode,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NetworkDashboardPage old) {
    super.didUpdateWidget(old);
    if (!widget.embedded) return;
    final before = (
      old.scope.countryCode,
      old.scope.branchIds.length == 1 ? old.scope.branchIds.first : null,
    );
    final after = (
      widget.scope.countryCode,
      widget.scope.branchIds.length == 1 ? widget.scope.branchIds.first : null,
    );
    if (before != after) _load();
  }

  bool _noActive = false;

  Future<void> _load() async {
    if (widget.branches.isEmpty) {
      // Nothing is active yet: do not call the network endpoint at all.
      setState(() {
        _noActive = true;
        _loading = false;
        _error = null;
      });
      return;
    }
    final ticket = ++_request;
    setState(() {
      _noActive = false;
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.api.networkDashboard(
        days: _days,
        branchId: _branchId,
        countryCode: _country,
      );
      if (!mounted || ticket != _request) return;
      final data = NetworkDashboardData.parse(
        raw,
        countryByBranchId: _countryByBranch,
      );
      final hadCritical = _data.rows.any((r) => r.inventoryRisk == 'critical');
      setState(() {
        _data = data;
        _loadedAt = DateTime.now();
        if (_country == null && _branchId == null && data.countries.isNotEmpty) {
          _serverCountries = data.countries;
        }
      });
      if (!hadCritical && data.rows.any((r) => r.inventoryRisk == 'critical')) {
        Haptics.critical();
      }
    } on DlcApiException catch (e) {
      if (!mounted || ticket != _request) return;
      if (isBranchScopeError(e)) {
        // Race with activation: same friendly state, not the raw error.
        setState(() => _noActive = true);
        return;
      }
      setState(() {
        _error = e.message;
        _errorDetails = technicalDetails(e);
      });
      Haptics.error();
    } finally {
      if (mounted && ticket == _request) setState(() => _loading = false);
    }
  }

  void _setCountry(String? code) {
    Haptics.selection();
    setState(() {
      _countryState = code;
      _branchState = reconcileBranchForCountry(
        _branchState,
        code,
        widget.branches,
      );
    });
    _load();
  }

  void _setBranch(String? id) {
    Haptics.selection();
    setState(() => _branchState = id);
    _load();
  }

  void _setDays(int days) {
    if (days == _days) return;
    Haptics.selection();
    setState(() => _days = days);
    _load();
  }

  List<NetworkBranchRow> get _rows {
    var rows = _data.visibleRows(countryCode: _country);
    if (widget.embedded && widget.scope.branchIds.isNotEmpty) {
      rows = [
        for (final r in rows)
          if (widget.scope.branchIds.contains(r.id)) r,
      ];
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final body = _noActive
        ? ListView(
            padding: const EdgeInsets.all(16),
            children: [
              NoActiveBranchesPanel(
                canManage: widget.onOpenOnboarding != null,
                onOpenOnboarding: widget.onOpenOnboarding,
              ),
            ],
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: _loading && _data.rows.isEmpty && _error == null
                ? const SingleChildScrollView(
                    physics: AlwaysScrollableScrollPhysics(),
                    child: PageSkeleton(),
                  )
                : _content(context),
          );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Red consolidada'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Actualizar',
            icon: const Icon(CupertinoIcons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _filters(BuildContext context, List<NetworkCountry> countries) {
    final branchOptions = filterBranchesByCountry(widget.branches, _country);
    return DlcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _periodFilter(),
          const SizedBox(height: 12),
          CountryDropdown(
            value: _country,
            includeAll: true,
            codes: [
              for (final c in countries) c.countryCode,
              if (_country != null &&
                  !countries.any((c) => c.countryCode == _country))
                _country!,
            ],
            counts: {for (final c in countries) c.countryCode: c.branchCount},
            onChanged: _setCountry,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('branch-$_branchState-$_country'),
            initialValue: _branchState ?? '*',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Sucursal',
              prefixIcon: Icon(CupertinoIcons.bag),
            ),
            items: [
              const DropdownMenuItem(
                value: '*',
                child: Text(kAllBranchesLabel),
              ),
              for (final b in branchOptions)
                DropdownMenuItem(
                  value: b.id,
                  child: Text(
                    '${b.name} · ${b.countryCode}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => _setBranch(v == '*' ? null : v),
          ),
        ],
      ),
    );
  }

  Widget _periodFilter() => SegmentedFilter<int>(
    semanticLabel: 'Período',
    selected: _days,
    options: const {1: 'Hoy', 7: '7 días', 30: '30 días'},
    onChanged: _setDays,
  );

  Widget _content(BuildContext context) {
    final colors = context.dlc;
    final prefs = context.prefs;
    final rows = _rows;
    final countries = countryOptions(
      widget.branches,
      fromServer: _serverCountries,
    );
    final closed = _data.closedCutsOf(rows);
    final expected = _data.expectedCutsOf(rows);
    final liters = rows.fold(0.0, (s, r) => s + r.soldLiters);
    final salesTotals = salesByCurrency(rows);
    final singleCurrency = salesTotals.currencyCount <= 1;
    final currency = singleCurrency && !salesTotals.isEmpty
        ? salesTotals.entries.first.key
        : 'USD';
    final alerts = [
      for (final r in rows)
        if (r.inventoryRisk == 'critical' || r.inventoryRisk == 'warning')
          AlertItem(
            title: inventoryRiskText(r.inventoryRisk),
            detail: 'Cortes ${r.closedCuts}/${r.expectedCuts} · ${countryName(r.countryCode)}',
            severity: r.inventoryRisk,
            branchName: r.name,
          ),
    ];
    var i = 0;
    Widget step(Widget w) => Entrance(index: i++, child: w);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        if (!widget.embedded) ...[
          _filters(context, countries),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[
          ErrorState(
            message: _error!,
            details: _errorDetails,
            onRetry: _load,
            staleSince: _data.rows.isEmpty || _loadedAt == null
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
        if (!_loading && _error == null && rows.isEmpty)
          EmptyState(
            icon: CupertinoIcons.globe,
            title: 'Sin sucursales para este filtro',
            message: 'Cambia el país, la sucursal o el período.',
          ),
        if (rows.isNotEmpty) ...[
          step(AlertStrip(items: alerts)),
          const SizedBox(height: 12),
          if (widget.embedded) ...[
            step(_periodFilter()),
            const SizedBox(height: 12),
          ],
          if (_data.canSales)
            step(
              HeroKpi(
                label: 'Ventas · ${_days == 1 ? 'hoy' : 'últimos $_days días'}',
                value: salesTotals.isEmpty ? 0 : salesTotals.entries.first.value,
                format: (v) => prefs.money(
                  v,
                  currency: salesTotals.isEmpty ? 'USD' : salesTotals.entries.first.key,
                ),
                extra: salesTotals.currencyCount > 1
                    ? 'Más: ${MoneyTotals.fromEntries(salesTotals.entries.skip(1)).format(decimals: prefs.decimals)}'
                    : null,
                caption:
                    '${rows.length} ${rows.length == 1 ? 'sucursal' : 'sucursales'} · cortes cerrados',
                icon: CupertinoIcons.money_dollar_circle,
              ),
            )
          else
            step(
              HeroKpi(
                label: 'Sucursales en la vista',
                value: rows.length.toDouble(),
                format: (v) => v.toStringAsFixed(0),
                caption: 'Sin permiso para ver ventas',
                icon: CupertinoIcons.bag,
              ),
            ),
          const SizedBox(height: 10),
          step(
            MiniKpiRow(
              tiles: [
                MiniKpi(
                  icon: CupertinoIcons.bag,
                  value: '${rows.length}',
                  label: _country == null
                      ? 'Sucursales en ${countries.length} ${countries.length == 1 ? 'país' : 'países'}'
                      : 'Sucursales en ${countryName(_country)}',
                  tone: DlcStatus.info,
                ),
                MiniKpi(
                  icon: CupertinoIcons.checkmark_rectangle,
                  value: '$closed/$expected',
                  label: expected == 0
                      ? 'Sin cortes esperados'
                      : '${(closed / expected * 100).toStringAsFixed(0)} % de cortes cerrados',
                  tone: expected > 0 && closed >= expected
                      ? DlcStatus.optimal
                      : DlcStatus.warning,
                ),
                MiniKpi(
                  icon: CupertinoIcons.gauge,
                  value: prefs.volumeCard(liters),
                  label: 'Vendidos en cortes cerrados',
                  tone: DlcStatus.info,
                ),
              ],
            ),
          ),
          if (_data.canInventory) ...[
            const SectionHeader(
              title: 'Nivel de combustible',
              icon: CupertinoIcons.drop,
            ),
            DlcCard(child: TankLevelBars(levels: _data.fuelLevelsOf(rows))),
          ],
          if (_data.canSales && _data.daily.isNotEmpty) ...[
            const SectionHeader(
              title: 'Tendencia de ventas',
              icon: CupertinoIcons.chart_bar,
            ),
            DlcCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (singleCurrency) ...[
                    TrendBarChart(
                      title: 'Ventas por día ($currency)',
                      points: [
                        for (final p in _data.daily)
                          TrendPoint(shortDay(p.date), p.salesUsd),
                      ],
                      format: (v) => prefs.money(v, currency: currency),
                      color: colors.brand,
                    ),
                    const Divider(height: 24),
                  ] else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(CupertinoIcons.info_circle, size: 18, color: colors.info),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Las ventas están en monedas distintas y no se suman. Elige un país para ver las ventas por día.',
                            style: TextStyle(color: colors.muted, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                  ],
                  TrendBarChart(
                    title: 'Consumo por día (${prefs.unit.label.toLowerCase()})',
                    points: [
                      for (final p in _data.daily)
                        TrendPoint(
                          shortDay(p.date),
                          litersToUnit(p.soldLiters, prefs.unit),
                        ),
                    ],
                    format: (v) =>
                        '${groupDigits(v, decimals: 0)} ${prefs.unit.symbol}',
                    color: colors.info,
                  ),
                ],
              ),
            ),
          ],
          if (rows.length > 1 && _data.canSales) ...[
            SectionHeader(
              title: 'Comparación entre sucursales',
              icon: CupertinoIcons.chart_bar_square,
              trailing: singleCurrency ? currency : prefs.unit.symbol,
            ),
            DlcCard(
              child: HBarChart(
                title: 'Comparación entre sucursales',
                items: _comparison(rows, singleCurrency, prefs, colors),
              ),
            ),
          ],
          SectionHeader(
            title: 'Sucursales',
            icon: CupertinoIcons.bag,
            trailing: '${rows.length}',
          ),
          for (final (idx, row) in rows.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Entrance(
                index: idx,
                child: _NetworkBranchTile(
                  row: row,
                  onTap: widget.onOpenBranch == null
                      ? null
                      : () {
                          final match = widget.branches
                              .where((b) => b.id == row.id)
                              .firstOrNull;
                          if (match != null) widget.onOpenBranch!(match);
                        },
                ),
              ),
            ),
          if (_data.lastSourceAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Fuente: cortes cerrados e inventario vigente · ${_data.lastSourceAt}',
                style: TextStyle(color: colors.muted, fontSize: 11),
              ),
            ),
        ],
      ],
    );
  }

  List<BarItem> _comparison(
    List<NetworkBranchRow> rows,
    bool singleCurrency,
    DisplayPrefs prefs,
    DlcColors colors,
  ) {
    final sorted = [...rows]
      ..sort(
        (a, b) => singleCurrency
            ? b.salesUsd.compareTo(a.salesUsd)
            : b.soldLiters.compareTo(a.soldLiters),
      );
    return [
      for (final r in sorted)
        BarItem(
          label: r.name,
          value: singleCurrency ? r.salesUsd : r.soldLiters,
          display: singleCurrency
              ? prefs.money(r.salesUsd, currency: currencyForCountry(r.countryCode))
              : prefs.volumeCard(r.soldLiters),
          detail:
              '${countryName(r.countryCode)} · cortes ${r.closedCuts}/${r.expectedCuts}',
          color: r.inventoryRisk == 'critical' ? colors.critical : colors.brand,
        ),
    ];
  }
}

class _NetworkBranchTile extends StatelessWidget {
  const _NetworkBranchTile({required this.row, this.onTap});
  final NetworkBranchRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    final status = inventoryRiskStatus(row.inventoryRisk);
    final fg = colors.foreground(status);
    return DlcCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${row.code} · ${countryName(row.countryCode)} · cortes ${row.closedCuts}/${row.expectedCuts}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(status.icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        inventoryRiskText(row.inventoryRisk),
                        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(CupertinoIcons.chevron_right, size: 16, color: colors.muted),
        ],
      ),
    );
  }
}
