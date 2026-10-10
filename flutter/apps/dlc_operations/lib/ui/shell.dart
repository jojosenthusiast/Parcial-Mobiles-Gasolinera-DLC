import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../branch_status.dart';
import '../haptics.dart';
import '../main.dart' show CutsPage, OperationsController;
import '../network_dashboard_page.dart';
import '../scope.dart';
import 'branches_page.dart';
import 'inventory_page.dart';
import 'kit.dart';
import 'more_page.dart';
import 'prices_page.dart';
import 'pumps_tanks_page.dart';
import 'scope_bar.dart';
import 'settings_page.dart';
import 'summary_page.dart';

enum ShellTab { summary, pumps, inventory, prices, more }

extension on ShellTab {
  String get navLabel => switch (this) {
    ShellTab.summary => 'Resumen',
    ShellTab.pumps => 'Bombas',
    ShellTab.inventory => 'Inventario',
    ShellTab.prices => 'Precios',
    ShellTab.more => 'Más',
  };
  String get title => switch (this) {
    ShellTab.summary => 'Resumen',
    ShellTab.pumps => 'Bombas y tanques',
    ShellTab.inventory => 'Inventario',
    ShellTab.prices => 'Precios',
    ShellTab.more => 'Más',
  };
  IconData get icon => switch (this) {
    ShellTab.summary => CupertinoIcons.square_grid_2x2,
    ShellTab.pumps => CupertinoIcons.gauge,
    ShellTab.inventory => CupertinoIcons.drop,
    ShellTab.prices => CupertinoIcons.tag,
    ShellTab.more => CupertinoIcons.ellipsis,
  };
}

/// Signed-in shell: wordmark + profile on top, the persistent scope bar, the
/// current tab and a bottom navigation that never overflows at large text.
class AppShell extends StatefulWidget {
  const AppShell({required this.controller, super.key});
  final OperationsController controller;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  ShellTab _tab = ShellTab.summary;

  OperationsController get c => widget.controller;

  void _syncBranch(List<BranchSummary> scoped) {
    if (scoped.length != 1) return;
    final target = scoped.first;
    if (c.branch?.id == target.id || c.loadingBranch) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && c.branch?.id != target.id && !c.loadingBranch) {
        c.selectBranch(target);
      }
    });
  }

  void _viewBranch(BranchSummary b) {
    c.scope.update(ScopeState(branchIds: {b.id}));
    setState(() => _tab = ShellTab.summary);
  }

  void _openSettings() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SettingsPage(
        theme: c.themeController,
        prefs: c.prefs,
        identity: c.identity,
        onLogout: () {
          Navigator.of(context).popUntil((r) => r.isFirst);
          c.logout();
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, c.scope]),
    builder: (context, _) {
      final scoped = effectiveBranches(c.scope.state, c.branches);
      _syncBranch(scoped);
      final colors = context.dlc;
      final single = scoped.length == 1;
      return Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: const Align(
            alignment: Alignment.centerLeft,
            child: BrandWordmark(height: 30),
          ),
          actions: [
            IconButton(
              onPressed: c.refresh,
              tooltip: 'Actualizar',
              icon: const Icon(CupertinoIcons.refresh),
            ),
            _ProfileMenu(
              name: c.identity?.displayName ?? '',
              onSettings: _openSettings,
              onLogout: c.logout,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            ScopeBar(controller: c.scope, branches: c.branches),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Icon(_tab.icon, size: 18, color: colors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        _tab.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _body(context, scoped, single)),
          ],
        ),
        bottomNavigationBar: _NavBar(
          selected: _tab,
          onSelected: (t) {
            Haptics.selection();
            setState(() => _tab = t);
          },
        ),
      );
    },
  );

  Widget _body(BuildContext context, List<BranchSummary> scoped, bool single) {
    if (_tab == ShellTab.more) {
      return MorePage(
        controller: c,
        singleBranch: single && c.branch?.id == scoped.first.id,
        onViewBranch: _viewBranch,
      );
    }
    if (scoped.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EmptyState(
            icon: CupertinoIcons.bag,
            title: c.branches.isEmpty
                ? 'Sin sucursales visibles'
                : 'Sin sucursales en esta vista',
            message: c.branches.isEmpty
                ? 'La cuenta no tiene asignación activa o aún no hay sucursales.'
                : 'Cambia el país o la sucursal en la barra de alcance.',
            actionLabel: c.canManageBranches && c.branches.isEmpty
                ? 'Nueva sucursal'
                : null,
            onAction: c.canManageBranches && c.branches.isEmpty
                ? () => openBranchWizard(context, c)
                : null,
          ),
        ],
      );
    }
    switch (_tab) {
      case ShellTab.summary:
        if (c.scope.state.branchIds.isEmpty &&
            scoped.every((b) => !b.isActive)) {
          return NoActiveBranchesView(
            branches: scoped,
            canManage: c.canManageBranches,
            onOpenWizard: () => openBranchWizard(context, c),
            onSelect: _viewBranch,
          );
        }
        if (single) {
          final target = scoped.first;
          if (c.branch?.id != target.id) {
            return const SingleChildScrollView(child: PageSkeleton());
          }
          if (c.branchNotReady) {
            return BranchNotReadyView(
              controller: c,
              onOpenWizard: () =>
                  openBranchWizard(context, c, branchId: target.id),
            );
          }
          return BranchSummaryView(
            controller: c,
            onOpenCuts: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Cortes')),
                  body: SafeArea(child: CutsPage(controller: c)),
                ),
              ),
            ),
            onOpenPumps: () => setState(() => _tab = ShellTab.pumps),
            onOpenInventory: () => setState(() => _tab = ShellTab.inventory),
          );
        }
        return NetworkDashboardPage(
          api: c.api,
          branches: c.branches,
          embedded: true,
          scope: c.scope.state,
          onOpenOnboarding: c.canManageBranches
              ? () => openBranchWizard(context, c)
              : null,
          onOpenBranch: _viewBranch,
        );
      case ShellTab.pumps:
        return PumpsTanksView(controller: c, branches: scoped);
      case ShellTab.inventory:
        return InventoryView(
          controller: c,
          branches: activeBranches(scoped),
          scope: c.scope.state,
        );
      case ShellTab.prices:
        return PricesView(controller: c, branches: scoped);
      case ShellTab.more:
        return const SizedBox.shrink();
    }
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({
    required this.name,
    required this.onSettings,
    required this.onLogout,
  });
  final String name;
  final VoidCallback onSettings, onLogout;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return PopupMenuButton<String>(
      tooltip: 'Perfil',
      offset: const Offset(0, 44),
      onSelected: (v) => v == 'settings' ? onSettings() : onLogout(),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(CupertinoIcons.gear),
            title: Text('Configuración'),
          ),
        ),
        const PopupMenuItem(
          value: 'logout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(CupertinoIcons.square_arrow_left),
            title: Text('Cerrar sesión'),
          ),
        ),
      ],
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: CircleAvatar(
            radius: 16,
            backgroundColor: c.brandContainer,
            child: Text(
              initial,
              style: TextStyle(
                color: c.brand,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom navigation with fixed equal cells; labels shrink instead of
/// overflowing and the text scale is capped inside the bar.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.selected, required this.onSelected});
  final ShellTab selected;
  final ValueChanged<ShellTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.15,
          child: Row(
            children: [
              for (final t in ShellTab.values)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: t == selected,
                    label: t.navLabel,
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () => onSelected(t),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 60),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 6,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: t == selected
                                      ? c.brandContainer
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 4,
                                  ),
                                  child: Icon(
                                    t.icon,
                                    size: 22,
                                    color: t == selected
                                        ? (dark ? c.ink : c.brand)
                                        : c.muted,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  t.navLabel,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: t == selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: t == selected ? c.ink : c.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
