import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../branch_status.dart';
import '../country_catalog.dart';
import '../haptics.dart';
import '../labels.dart';
import '../scope.dart';
import 'kit.dart';

/// Persistent "what am I looking at" bar (DESIGN.md section 5):
/// "Red > Pais > Sucursal" comboboxes plus a "Viendo: ..." chip. Fixed layout: the
/// crumbs share the width and ellipsize, they never wrap. Branch managers see
/// their branch locked.
class ScopeBar extends StatelessWidget {
  const ScopeBar({required this.controller, required this.branches, super.key});
  final ScopeController controller;
  final List<BranchSummary> branches;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = context.dlc;
      final scope = controller.state;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (controller.locked)
                _LockedRow(scope: scope, branches: branches)
              else
                Row(
                  children: [
                    _RedCrumb(
                      active: scope.isNetwork,
                      onTap: () {
                        Haptics.selection();
                        controller.update(ScopeState.network);
                      },
                    ),
                    const _Sep(),
                    Expanded(
                      flex: 5,
                      child: _Crumb(
                        key: const Key('scope-country'),
                        label: 'País',
                        value: countryChipLabel(scope),
                        icon: CupertinoIcons.globe,
                        onTap: () => _pickCountry(context),
                      ),
                    ),
                    const _Sep(),
                    Expanded(
                      flex: 6,
                      child: _Crumb(
                        key: const Key('scope-branch'),
                        label: 'Sucursal',
                        value: branchChipLabel(scope, branches),
                        icon: CupertinoIcons.bag,
                        onTap: () => _pickBranches(context),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              _ViewingChip(text: 'Viendo: ${viewingLabel(scope, branches)}'),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _pickCountry(BuildContext context) async {
    final countries = countryOptions(branches);
    final scope = controller.state;
    const all = '*';
    final picked = await showSelectSheet<String>(
      context,
      title: 'País',
      selected: scope.countryCode ?? all,
      options: [
        SelectOption(
          all,
          kAllCountriesLabel,
          detail: '${branches.length} sucursales',
          icon: CupertinoIcons.globe,
        ),
        for (final co in countries)
          SelectOption(
            co.countryCode,
            countryName(co.countryCode),
            detail: co.branchCount == 1
                ? '1 sucursal'
                : '${co.branchCount} sucursales',
          ),
      ],
    );
    if (picked == null) return;
    Haptics.selection();
    await controller.update(
      scope.withCountry(picked == all ? null : picked, branches),
    );
  }

  Future<void> _pickBranches(BuildContext context) async {
    final scope = controller.state;
    final candidates = filterBranchesByCountry(branches, scope.countryCode);
    final picked = await showMultiSelectSheet<String>(
      context,
      title: 'Sucursales',
      selected: scope.branchIds,
      allLabel: 'Todas',
      options: [
        for (final b in candidates)
          SelectOption(
            b.id,
            b.name,
            detail:
                '${countryName(b.countryCode)}${b.isActive ? '' : ' · ${statusLabel(b.status)}'}',
            icon: b.isActive ? CupertinoIcons.bag : CupertinoIcons.hammer,
          ),
      ],
    );
    if (picked == null) return;
    Haptics.selection();
    await controller.update(scope.withBranches(picked));
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: ExcludeSemantics(
      child: Icon(
        CupertinoIcons.chevron_right,
        size: 12,
        color: context.dlc.muted,
      ),
    ),
  );
}

class _RedCrumb extends StatelessWidget {
  const _RedCrumb({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return Semantics(
      button: true,
      selected: active,
      label: 'Toda la red',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(
            child: Text(
              'Red',
              maxLines: 1,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: active ? c.brand : c.muted,
                decoration: active ? TextDecoration.underline : null,
                decorationColor: c.brand,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    super.key,
  });
  final String label, value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return Semantics(
      button: true,
      label: '$label: $value',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.borderStrong),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: c.muted,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(CupertinoIcons.chevron_down, size: 13, color: c.ink),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewingChip extends StatelessWidget {
  const _ViewingChip({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.brandContainer,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.eye, size: 13, color: c.brand),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? c.ink
                        : c.brand,
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

class _LockedRow extends StatelessWidget {
  const _LockedRow({required this.scope, required this.branches});
  final ScopeState scope;
  final List<BranchSummary> branches;
  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    final inScope = scope.resolve(branches);
    final name = inScope.length == 1
        ? inScope.first.name
        : '${inScope.length} sucursales';
    return Semantics(
      label: 'Sucursal fija: $name',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Tu acceso está limitado a tu sucursal',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(CupertinoIcons.lock, size: 16, color: c.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    'Fija',
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
