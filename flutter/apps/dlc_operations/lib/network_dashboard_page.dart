import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'branch_status.dart';
import 'charts.dart';
import 'country_catalog.dart';
import 'haptics.dart';
import 'main.dart' show EmptyPanel, ErrorBox, MetricCard, SectionTitle;
import 'network_metrics.dart';

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

/// Consolidated dashboard for the network, filterable by country and branch.
class NetworkDashboardPage extends StatefulWidget {
  const NetworkDashboardPage({
    required this.api,
    required List<BranchSummary> branches,
    this.onOpenBranch,
    this.onOpenOnboarding,
    super.key,
  }) : _allBranches = branches;
  final EmployeeSession api;
  final List<BranchSummary> _allBranches;
  final ValueChanged<BranchSummary>? onOpenBranch;

  /// Call to action of the empty state (General Manager only); `null` hides it.
  final VoidCallback? onOpenOnboarding;

  /// Only ACTIVE branches feed the consolidated metrics.
  List<BranchSummary> get branches => activeBranches(_allBranches);

  @override
  State<NetworkDashboardPage> createState() => _NetworkDashboardPageState();
}

class _NetworkDashboardPageState extends State<NetworkDashboardPage> {
  int _days = 7;
  String? _country;
  String? _branchId;
  NetworkDashboardData _data = NetworkDashboardData.empty;
  List<NetworkCountry> _serverCountries = const [];
  bool _loading = true;
  String? _error, _errorDetails;
  int _request = 0;

  Map<String, String> get _countryByBranch => {
    for (final b in widget.branches) b.id: b.countryCode,
  };

  @override
  void initState() {
    super.initState();
    _load();
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
      _country = code;
      _branchId = reconcileBranchForCountry(_branchId, code, widget.branches);
    });
    _load();
  }

  void _setBranch(String? id) {
    Haptics.selection();
    setState(() => _branchId = id);
    _load();
  }

  void _setDays(int days) {
    if (days == _days) return;
    Haptics.selection();
    setState(() => _days = days);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    final rows = _data.visibleRows(countryCode: _country);
    final branchOptions = filterBranchesByCountry(widget.branches, _country);
    final countries = countryOptions(
      widget.branches,
      fromServer: _serverCountries,
    );
    final closed = _data.closedCutsOf(rows), expected = _data.expectedCutsOf(rows);
    final sales = _data.daily.fold(0.0, (s, p) => s + p.salesUsd);
    final liters = _data.daily.fold(0.0, (s, p) => s + p.soldLiters);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Red consolidada'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _noActive
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 1, label: Text('Hoy')),
                        ButtonSegment(value: 7, label: Text('7 días')),
                        ButtonSegment(value: 30, label: Text('30 días')),
                      ],
                      selected: {_days},
                      onSelectionChanged: (s) => _setDays(s.first),
                    ),
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
                      counts: {
                        for (final c in countries) c.countryCode: c.branchCount,
                      },
                      onChanged: _setCountry,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey('branch-$_branchId-$_country'),
                      initialValue: _branchId ?? '*',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sucursal',
                        prefixIcon: Icon(Icons.storefront_outlined),
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
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              ErrorBox(_error!, details: _errorDetails),
              const SizedBox(height: 12),
            ],
            if (_loading) const LinearProgressIndicator(minHeight: 3),
            if (!_loading && _error == null && rows.isEmpty)
              const EmptyPanel(
                icon: Icons.public_off_outlined,
                title: 'Sin sucursales para este filtro',
                message: 'Cambia el país, la sucursal o el período.',
              ),
            if (rows.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      label: 'Sucursales',
                      value: '${rows.length}',
                      detail: _country == null
                          ? 'en ${countries.length} país(es)'
                          : countryName(_country),
                      icon: Icons.storefront_outlined,
                      color: colors.brand,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricCard(
                      label: 'Cortes cerrados',
                      value: '$closed/$expected',
                      detail: expected == 0
                          ? 'sin cortes esperados'
                          : '${(closed / expected * 100).toStringAsFixed(0)} % de cobertura',
                      icon: Icons.fact_check_outlined,
                      color: expected > 0 && closed >= expected
                          ? colors.optimal
                          : colors.warning,
                    ),
                  ),
                ],
              ),
              if (_data.canSales) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        label: 'Ventas',
                        value: formatUsd(sales),
                        detail: 'últimos $_days día(s)',
                        icon: Icons.payments_outlined,
                        color: colors.optimal,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricCard(
                        label: 'Litros vendidos',
                        value: formatLiters(liters),
                        detail: 'cortes cerrados',
                        icon: Icons.local_gas_station_outlined,
                        color: colors.info,
                      ),
                    ),
                  ],
                ),
              ],
              if (_data.canInventory) ...[
                const SizedBox(height: 16),
                const SectionTitle(title: 'Nivel de combustible'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: TankLevelBars(levels: _data.fuelLevelsOf(rows)),
                  ),
                ),
              ],
              if (_data.canSales && _data.daily.isNotEmpty) ...[
                const SizedBox(height: 16),
                const SectionTitle(title: 'Tendencia de ventas'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        TrendBarChart(
                          title: 'Ventas por día (USD)',
                          points: [
                            for (final p in _data.daily)
                              TrendPoint(shortDay(p.date), p.salesUsd),
                          ],
                          format: formatUsd,
                          color: colors.brand,
                        ),
                        const Divider(height: 24),
                        TrendBarChart(
                          title: 'Consumo por día (litros)',
                          points: [
                            for (final p in _data.daily)
                              TrendPoint(shortDay(p.date), p.soldLiters),
                          ],
                          format: formatLiters,
                          color: colors.info,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SectionTitle(title: 'Sucursales', trailing: '${rows.length}'),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
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
        ),
      ),
    );
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
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(
          row.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${row.code} · ${countryName(row.countryCode)} · cortes ${row.closedCuts}/${row.expectedCuts}',
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(status.icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      inventoryRiskText(row.inventoryRisk),
                      style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      ),
    );
  }
}
