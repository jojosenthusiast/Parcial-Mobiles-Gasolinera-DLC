import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../cash_screen.dart';
import '../infrastructure_setup_screen.dart';
import '../loyalty_programs_screen.dart';
import '../main.dart'
    show CutsPage, IncidentsPage, OperationsController, ReportsPage;
import '../maintenance_screen.dart';
import '../operational_assets_screen.dart';
import '../procurement_screen.dart';
import '../promotions_screen.dart';
import '../staff_shifts_screen.dart';
import 'branches_page.dart';
import 'kit.dart';
import 'motion.dart';
import 'settings_page.dart';

class _MoreItem {
  const _MoreItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final void Function(BuildContext context) onTap;
}

class _MoreGroup {
  const _MoreGroup(this.title, this.icon, this.items);
  final String title;
  final IconData icon;
  final List<_MoreItem> items;
}

Future<void> _push(BuildContext context, Widget page) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

/// Grouped menu (DESIGN.md section 5): Operación, Comercial, Administración,
/// Más. Items that work on one branch appear when the scope is a single
/// branch and the user has the permission.
class MorePage extends StatelessWidget {
  const MorePage({
    required this.controller,
    required this.singleBranch,
    required this.onViewBranch,
    super.key,
  });
  final OperationsController controller;

  /// True when the scope is exactly one branch (branch screens are usable).
  final bool singleBranch;
  final ValueChanged<BranchSummary> onViewBranch;

  OperationsController get c => controller;

  List<_MoreGroup> _groups() {
    final branch = c.branch;
    final branchId = branch?.id;
    final perms = {...c.permissions, ...c.globalPermissions};
    bool can(String p) => singleBranch && branchId != null && c.can(p);
    final api = c.api;
    return [
      _MoreGroup('Operación', CupertinoIcons.gauge, [
        if (singleBranch && branchId != null)
          _MoreItem(
            icon: CupertinoIcons.doc_text,
            title: 'Cortes',
            subtitle: 'Matutino y vespertino: lecturas y cierre',
            onTap: (ctx) => _push(
              ctx,
              Scaffold(
                appBar: AppBar(title: const Text('Cortes')),
                body: SafeArea(child: CutsPage(controller: c)),
              ),
            ),
          ),
        if (can('incident.read'))
          _MoreItem(
            icon: CupertinoIcons.exclamationmark_triangle,
            title: 'Incidencias',
            subtitle: 'Reportar y dar seguimiento',
            onTap: (ctx) => _push(ctx, IncidentsPage(controller: c)),
          ),
        if (singleBranch && branchId != null)
          _MoreItem(
            icon: CupertinoIcons.chart_bar,
            title: 'Reportes',
            subtitle: 'Generar y exportar',
            onTap: (ctx) => _push(
              ctx,
              Scaffold(
                appBar: AppBar(title: const Text('Reportes')),
                body: SafeArea(child: ReportsPage(controller: c)),
              ),
            ),
          ),
      ]),
      _MoreGroup('Comercial', CupertinoIcons.tag, [
        if (can('purchase.read'))
          _MoreItem(
            icon: CupertinoIcons.cube_box,
            title: 'Compras de combustible',
            subtitle: 'Proveedores, órdenes y recepción a tanque',
            onTap: (ctx) => _push(
              ctx,
              ProcurementScreen(api: api, branchId: branchId!, permissions: c.permissions),
            ),
          ),
        if (singleBranch && branchId != null && (c.can('cash.read') || c.can('cash.open')))
          _MoreItem(
            icon: CupertinoIcons.creditcard,
            title: 'Caja y tienda',
            subtitle: 'Turnos, movimientos y arqueo',
            onTap: (ctx) => _push(
              ctx,
              CashScreen(api: api, branchId: branchId, permissions: c.permissions),
            ),
          ),
        if (perms.any(
          (p) =>
              p == 'promotion.read' ||
              p == 'promotion.manage' ||
              p == 'promotion.network.manage',
        ))
          _MoreItem(
            icon: CupertinoIcons.tag,
            title: 'Promociones y ofertas',
            subtitle: 'Reglas, calendario y revisión',
            onTap: (ctx) => _push(
              ctx,
              PromotionsScreen(
                api: api,
                branchId: branch?.id,
                branchTimeZone: branch?.timezone ?? 'America/El_Salvador',
                permissions: perms,
              ),
            ),
          ),
        if (c.globalPermissions.any((p) => p.startsWith('loyalty.program.')))
          _MoreItem(
            icon: CupertinoIcons.star,
            title: 'Programa de puntos',
            subtitle: 'Tasa central, versiones y aprobación',
            onTap: (ctx) => _push(
              ctx,
              LoyaltyProgramsScreen(api: api, permissions: c.globalPermissions),
            ),
          ),
      ]),
      _MoreGroup('Administración', CupertinoIcons.building_2_fill, [
        if (c.branches.isNotEmpty)
          _MoreItem(
            icon: CupertinoIcons.bag,
            title: 'Sucursales',
            subtitle: 'Lista, alta y preparación',
            onTap: (ctx) => _push(
              ctx,
              BranchesPage(
                controller: c,
                onView: (b) {
                  Navigator.of(ctx).pop();
                  onViewBranch(b);
                },
              ),
            ),
          ),
        if (c.canManageBranches)
          _MoreItem(
            icon: CupertinoIcons.plus_app,
            title: 'Alta de sucursal',
            subtitle: 'Asistente paso a paso',
            onTap: (ctx) => openBranchWizard(ctx, c),
          ),
        if (can('staff.read'))
          _MoreItem(
            icon: CupertinoIcons.person_2,
            title: 'Personal y turnos',
            subtitle: 'Equipo activo y agenda semanal',
            onTap: (ctx) => _push(
              ctx,
              StaffShiftsScreen(api: api, branchId: branchId!, permissions: c.permissions),
            ),
          ),
        if (can('infrastructure.read'))
          _MoreItem(
            icon: CupertinoIcons.slider_horizontal_3,
            title: 'Infraestructura',
            subtitle: 'Combustibles, tanques, bombas y saldos',
            onTap: (ctx) => _push(
              ctx,
              InfrastructureSetupScreen(api: api, branchId: branchId!, permissions: c.permissions),
            ),
          ),
      ]),
      _MoreGroup('Más', CupertinoIcons.ellipsis, [
        if (can('maintenance.plan'))
          _MoreItem(
            icon: CupertinoIcons.wrench,
            title: 'Mantenimiento',
            subtitle: 'Órdenes, tareas y verificación',
            onTap: (ctx) => _push(
              ctx,
              MaintenanceScreen(api: api, branchId: branchId!, permissions: c.permissions),
            ),
          ),
        if (can('operational_asset.read'))
          _MoreItem(
            icon: CupertinoIcons.hammer,
            title: 'Activos operativos',
            subtitle: 'Equipos, custodia y traslados',
            onTap: (ctx) => _push(
              ctx,
              OperationalAssetsScreen(
                api: api,
                branchId: branchId!,
                permissions: c.permissions,
                branches: c.branches,
              ),
            ),
          ),
        _MoreItem(
          icon: CupertinoIcons.gear,
          title: 'Configuración',
          subtitle: 'Tema, unidades y decimales',
          onTap: (ctx) => _push(
            ctx,
            SettingsPage(
              theme: c.themeController,
              prefs: c.prefs,
              identity: c.identity,
              onLogout: () {
                Navigator.of(ctx).popUntil((r) => r.isFirst);
                c.logout();
              },
            ),
          ),
        ),
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    final groups = _groups().where((g) => g.items.isNotEmpty).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        if (!singleBranch)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: DlcCard(
              weight: CardWeight.quiet,
              color: colors.infoContainer,
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(CupertinoIcons.info_circle, size: 18, color: colors.info),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Elige una sucursal en la barra de alcance para ver cortes, compras, caja y personal.',
                      style: TextStyle(color: colors.ink, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        for (final (gi, g) in groups.indexed) ...[
          SectionHeader(title: g.title, icon: g.icon),
          Entrance(
            index: gi,
            child: DlcCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, item) in g.items.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 60),
                    ListTile(
                      minTileHeight: 56,
                      leading: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.brandContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(item.icon, size: 20, color: colors.brand),
                        ),
                      ),
                      title: Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                        color: colors.muted,
                      ),
                      onTap: () => item.onTap(context),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
