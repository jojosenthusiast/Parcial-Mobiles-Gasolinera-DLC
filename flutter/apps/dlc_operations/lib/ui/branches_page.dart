import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../branch_status.dart';
import '../country_catalog.dart';
import '../format.dart';
import '../haptics.dart';
import '../labels.dart';
import '../main.dart' show OperationsController;
import 'branch_wizard.dart';
import 'kit.dart';
import 'motion.dart';

/// Opens the guided "Alta de sucursal" stepper (new branch or resume).
Future<void> openBranchWizard(
  BuildContext context,
  OperationsController controller, {
  String? branchId,
}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => BranchWizardPage(
      api: controller.api,
      branchId: branchId,
      existingCodes: [for (final b in controller.branches) b.code],
      onChanged: controller.refresh,
    ),
  ),
);

/// Sucursales: operating branches and the ones still in preparation.
class BranchesPage extends StatefulWidget {
  const BranchesPage({
    required this.controller,
    required this.onView,
    super.key,
  });
  final OperationsController controller;

  /// Called to look at an operating branch (the shell narrows the scope).
  final ValueChanged<BranchSummary> onView;

  @override
  State<BranchesPage> createState() => _BranchesPageState();
}

class _BranchesPageState extends State<BranchesPage> {
  String? _country;

  OperationsController get _c => widget.controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) {
      final c = context.dlc;
      final all = _c.branches;
      final countries = countryOptions(all);
      final visible = filterBranchesByCountry(all, _country);
      final preparing = [for (final b in visible) if (b.isInPreparation) b];
      final others = [for (final b in visible) if (!b.isInPreparation) b];
      final canManage = _c.canManageBranches;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Sucursales'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _c.refresh,
              icon: const Icon(CupertinoIcons.refresh),
            ),
          ],
        ),
        floatingActionButton: canManage
            ? FloatingActionButton.extended(
                onPressed: () => openBranchWizard(context, _c),
                icon: const Icon(CupertinoIcons.plus),
                label: const Text('Nueva sucursal'),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: _c.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
            children: [
              if (countries.length > 1) ...[
                SelectField<String>(
                  label: 'País',
                  valueLabel: _country == null
                      ? kAllCountriesLabel
                      : countryName(_country),
                  icon: CupertinoIcons.globe,
                  onTap: () async {
                    const allKey = '*';
                    final picked = await showSelectSheet<String>(
                      context,
                      title: 'País',
                      selected: _country ?? allKey,
                      options: [
                        const SelectOption(allKey, kAllCountriesLabel),
                        for (final co in countries)
                          SelectOption(
                            co.countryCode,
                            countryName(co.countryCode),
                            detail: '${co.branchCount} sucursales',
                          ),
                      ],
                    );
                    if (picked != null) {
                      Haptics.selection();
                      setState(() => _country = picked == allKey ? null : picked);
                    }
                  },
                ),
                const SizedBox(height: 14),
              ],
              if (all.isEmpty)
                EmptyState(
                  icon: CupertinoIcons.bag,
                  title: 'Aún no hay sucursales',
                  message: canManage
                      ? 'Crea la primera con el asistente: te guía paso a paso.'
                      : 'La cuenta no tiene sucursales asignadas.',
                  actionLabel: canManage ? 'Nueva sucursal' : null,
                  onAction: canManage
                      ? () => openBranchWizard(context, _c)
                      : null,
                ),
              if (preparing.isNotEmpty) ...[
                SectionHeader(
                  title: 'En preparación',
                  icon: CupertinoIcons.hammer,
                  trailing: '${preparing.length}',
                ),
                for (final (i, b) in preparing.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Entrance(
                      index: i,
                      child: _BranchTile(
                        branch: b,
                        actionLabel: canManage ? 'Completar preparación' : null,
                        actionIcon: CupertinoIcons.chevron_right,
                        onAction: canManage
                            ? () => openBranchWizard(context, _c, branchId: b.id)
                            : null,
                        onTap: canManage
                            ? () => openBranchWizard(context, _c, branchId: b.id)
                            : () => widget.onView(b),
                      ),
                    ),
                  ),
              ],
              if (others.isNotEmpty) ...[
                SectionHeader(
                  title: 'Sucursales',
                  icon: CupertinoIcons.bag,
                  trailing: '${others.length}',
                ),
                for (final (i, b) in others.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Entrance(
                      index: i,
                      child: _BranchTile(
                        branch: b,
                        onTap: () => widget.onView(b),
                      ),
                    ),
                  ),
              ],
              if (_c.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ErrorState(
                    message: _c.error!,
                    details: _c.errorDetails,
                    onRetry: _c.refresh,
                  ),
                ),
              if (all.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Moneda de cada sucursal según su país: ${{for (final b in all) currencyForCountry(b.countryCode)}.join(', ')}.',
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _BranchTile extends StatelessWidget {
  const _BranchTile({
    required this.branch,
    required this.onTap,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });
  final BranchSummary branch;
  final VoidCallback onTap;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.dlc;
    return DlcCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      branch.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${branch.code} · ${countryName(branch.countryCode)} · ${zoneLabel(branch.zone)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Flexible(child: StatusBadge(branch.status)),
              const Spacer(),
              if (actionLabel != null)
                TextButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionIcon ?? CupertinoIcons.chevron_right, size: 14),
                  label: Text(actionLabel!),
                )
              else
                Icon(CupertinoIcons.chevron_right, size: 16, color: c.muted),
            ],
          ),
        ],
      ),
    );
  }
}
