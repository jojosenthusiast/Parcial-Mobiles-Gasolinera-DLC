import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'package:dlc_api/dlc_api.dart' show BranchSummary;

import '../app_theme.dart';
import '../branch_status.dart';
import '../charts.dart';
import '../cut_window.dart';
import '../format.dart';
import '../labels.dart';
import '../main.dart' show OperationsController;
import '../preferences.dart';
import '../tank_levels.dart';
import 'data_widgets.dart';
import 'kit.dart';
import 'motion.dart';
import 'util.dart';

/// Derives alert items from the dashboard payload: server alerts plus any
/// critical tank (30 % rule) the server did not already mention.
List<AlertItem> dashboardAlerts(Map<String, dynamic> data, {String? branchName}) {
  final items = <AlertItem>[
    for (final a in asMaps(data['alerts']))
      AlertItem(
        title: asText(a['title'], 'Alerta'),
        detail: asText(a['detail']),
        severity: asText(a['severity'], 'warning'),
        branchName: branchName,
      ),
  ];
  for (final t in asMaps(asMap(data['inventory'])['tanks'])) {
    final pct = tankPercent(t);
    if (pct == null || pct > kTankCriticalMaxPercent) continue;
    final code = asText(t['code']);
    final mentioned = items.any(
      (i) => code.isNotEmpty && '${i.title} ${i.detail}'.contains(code),
    );
    if (mentioned) continue;
    items.add(
      AlertItem(
        title:
            'Tanque ${asText(t['fuelName'], 'de combustible')}${code.isEmpty ? '' : ' $code'} en nivel crítico',
        detail: '${pct.toStringAsFixed(0)} % de su capacidad',
        severity: 'critical',
        branchName: branchName,
      ),
    );
  }
  return items;
}

/// Total of the closed-cut sales of today, or null when not reported.
double? todaySales(List<Map<String, dynamic>> cuts) {
  double? total;
  for (final cut in cuts) {
    final v = parseAmount(cut['closedSalesUsd']);
    if (v != null) total = (total ?? 0) + v;
  }
  return total;
}

/// Resumen of ONE branch: alerts, one hero figure, three secondary figures,
/// tank gauges, sales by cut and today's cuts.
class BranchSummaryView extends StatelessWidget {
  const BranchSummaryView({
    required this.controller,
    required this.onOpenCuts,
    required this.onOpenPumps,
    required this.onOpenInventory,
    super.key,
  });
  final OperationsController controller;
  final VoidCallback onOpenCuts, onOpenPumps, onOpenInventory;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final prefs = context.prefs;
    final branch = controller.branch;
    final data = controller.dashboard;
    if (data.isEmpty && controller.loadingBranch) {
      return const SingleChildScrollView(child: PageSkeleton());
    }
    final currency = branchCurrency(branch);
    final cuts = asMaps(data['cuts']);
    final inv = asMap(data['inventory']);
    final tanks = asMaps(inv['tanks']);
    final incidents = asList(data['openIncidents']);
    final sales = todaySales(cuts);
    final closed = cuts.where((x) => x['status'] == 'closed').length;
    final expectedCuts = cuts.isEmpty ? 2 : cuts.length;
    final totalLiters = parseAmount(inv['totalLiters']);
    final updated = clockOf(data['lastSourceAt']);
    final hasData = data.isNotEmpty;

    var i = 0;
    Widget step(Widget w) => Entrance(index: i++, child: w);

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        key: const PageStorageKey('summary'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          if (controller.error != null) ...[
            ErrorState(
              message: controller.error!,
              details: controller.errorDetails,
              onRetry: controller.refresh,
              staleSince: hasData ? updated : null,
            ),
            const SizedBox(height: 12),
          ],
          if (!hasData && !controller.loadingBranch)
            EmptyState(
              icon: CupertinoIcons.wifi_exclamationmark,
              title: 'No se cargó el resumen',
              message:
                  'Actualiza para consultar los datos vigentes de esta sucursal.',
              actionLabel: 'Actualizar',
              actionIcon: CupertinoIcons.refresh,
              onAction: controller.refresh,
            ),
          if (hasData) ...[
            step(AlertStrip(items: dashboardAlerts(data))),
            const SizedBox(height: 12),
            step(
              sales != null
                  ? HeroKpi(
                      label: 'Ventas de hoy',
                      value: sales,
                      format: (v) => prefs.money(v, currency: currency),
                      caption:
                          '$closed de $expectedCuts cortes cerrados${branch == null ? '' : ' · ${branch.name}'}',
                      icon: CupertinoIcons.money_dollar_circle,
                    )
                  : HeroKpi(
                      label: 'Combustible en tanques',
                      value: litersToUnit(totalLiters ?? 0, prefs.unit),
                      format: (v) =>
                          '${groupDigits(v, decimals: 0)} ${prefs.unit.symbol}',
                      caption: totalLiters == null
                          ? 'Dato incompleto'
                          : '${tanks.length} tanques${branch == null ? '' : ' · ${branch.name}'}',
                      icon: CupertinoIcons.drop,
                    ),
            ),
            const SizedBox(height: 10),
            step(
              MiniKpiRow(
                tiles: [
                  MiniKpi(
                    icon: CupertinoIcons.checkmark_rectangle,
                    value: '$closed/$expectedCuts',
                    label: 'Cortes cerrados',
                    tone: closed >= expectedCuts
                        ? DlcStatus.optimal
                        : DlcStatus.warning,
                  ),
                  MiniKpi(
                    icon: CupertinoIcons.drop,
                    value: totalLiters == null
                        ? '--'
                        : prefs.volumeCard(totalLiters),
                    label: 'En tanques',
                    tone: DlcStatus.info,
                  ),
                  MiniKpi(
                    icon: CupertinoIcons.exclamationmark_triangle,
                    value: '${incidents.length}',
                    label: incidents.length == 1
                        ? 'Incidencia abierta'
                        : 'Incidencias abiertas',
                    tone: incidents.isEmpty
                        ? DlcStatus.optimal
                        : DlcStatus.critical,
                  ),
                ],
              ),
            ),
            SectionHeader(
              title: 'Tanques',
              icon: CupertinoIcons.drop,
              trailing: tanks.isEmpty ? null : '${tanks.length}',
            ),
            if (tanks.isEmpty)
              EmptyState(
                icon: CupertinoIcons.drop,
                title: 'Sin tanques configurados',
                message: 'Cuando la sucursal registre sus tanques aparecerán aquí.',
              )
            else
              ResponsiveWrap(
                children: [
                  for (final t in tanks) TankCard(tank: t, prefs: prefs),
                ],
              ),
            if (tanks.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpenInventory,
                  icon: const Icon(CupertinoIcons.chevron_right, size: 14),
                  label: const Text('Ver inventario'),
                ),
              ),
            if (cuts.any((x) => parseAmount(x['closedSalesUsd']) != null)) ...[
              const SectionHeader(
                title: 'Ventas por corte',
                icon: CupertinoIcons.chart_bar,
              ),
              DlcCard(
                child: TrendBarChart(
                  title: 'Ventas por corte de hoy ($currency)',
                  points: [
                    for (final cut in cuts)
                      if (parseAmount(cut['closedSalesUsd']) != null)
                        TrendPoint(
                          cutName(cut['slot']),
                          parseAmount(cut['closedSalesUsd'])!,
                        ),
                  ],
                  format: (v) => prefs.money(v, currency: currency),
                  color: c.brand,
                ),
              ),
            ],
            SectionHeader(
              title: 'Cortes de hoy',
              icon: CupertinoIcons.doc_text,
              trailing: '$closed/$expectedCuts',
            ),
            if (cuts.isEmpty)
              EmptyState(
                icon: CupertinoIcons.doc_text,
                title: 'Sin cortes para la fecha operativa',
                message: 'Los cortes del día se generan en las ventanas de 06:00 y 14:00.',
                actionLabel: 'Abrir cortes',
                actionIcon: CupertinoIcons.chevron_right,
                onAction: onOpenCuts,
              )
            else ...[
              for (final cut in cuts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CutTile(cut: cut, onTap: onOpenCuts),
                ),
            ],
            const SizedBox(height: 6),
            DlcCard(
              weight: CardWeight.quiet,
              onTap: onOpenPumps,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(CupertinoIcons.gauge, color: c.muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${controller.pumps.length} bombas registradas',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_right, size: 16, color: c.muted),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              [
                if (updated != null) 'Actualizado a las $updated',
                if (data['operationalDate'] != null)
                  'Día operativo ${data['operationalDate']}',
              ].join(' · '),
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _CutTile extends StatelessWidget {
  const _CutTile({required this.cut, required this.onTap});
  final Map<String, dynamic> cut;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final status = asText(cut['status'], 'pending');
    final spec = statusSpec(status);
    final window = cutWindowLabel(cut);
    return DlcCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(spec.icon, color: c.foreground(spec.tone)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [cutName(cut['slot']), window]
                      .where((p) => p.isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${cut['registeredDispensers'] ?? 0} de ${cut['expectedDispensers'] ?? '--'} bombas',
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: StatusBadge(status, compact: true)),
        ],
      ),
    );
  }
}

/// Landing when nothing operates yet: explains it, offers the stepper and
/// lists the branches that are still being prepared.
class NoActiveBranchesView extends StatelessWidget {
  const NoActiveBranchesView({
    required this.branches,
    required this.canManage,
    required this.onOpenWizard,
    required this.onSelect,
    super.key,
  });
  final List<BranchSummary> branches;
  final bool canManage;
  final VoidCallback onOpenWizard;
  final ValueChanged<BranchSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        NoActiveBranchesPanel(
          canManage: canManage,
          onOpenOnboarding: onOpenWizard,
        ),
        if (branches.isNotEmpty)
          SectionHeader(
            title: 'Sucursales en preparación',
            icon: CupertinoIcons.hammer,
            trailing: '${branches.length}',
          ),
        for (final b in branches)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DlcCard(
              onTap: () => onSelect(b),
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
                          b.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: StatusBadge(b.status, compact: true),
                        ),
                      ],
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_right, size: 16, color: c.muted),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Used by the shell when the selected branch is not operating yet.
class BranchNotReadyView extends StatelessWidget {
  const BranchNotReadyView({
    required this.controller,
    required this.onOpenWizard,
    super.key,
  });
  final OperationsController controller;
  final VoidCallback onOpenWizard;
  @override
  Widget build(BuildContext context) {
    final branch = controller.branch;
    if (branch == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (controller.error != null)
          ErrorState(
            message: controller.error!,
            details: controller.errorDetails,
            onRetry: controller.refresh,
          ),
        BranchNotReadyPanel(
          branch: branch,
          canManage: controller.canManageBranches,
          onOpenOnboarding: onOpenWizard,
        ),
      ],
    );
  }
}
