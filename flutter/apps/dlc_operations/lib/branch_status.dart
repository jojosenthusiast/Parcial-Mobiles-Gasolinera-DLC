import 'package:dlc_api/dlc_api.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Branch lifecycle helpers. Branches created through onboarding start as
/// `draft` and only `active` branches accept branch-scoped operational
/// endpoints (dashboard, metrics, finance, staff, inventory...).

const kBranchStatusLabels = <String, String>{
  'draft': 'Borrador',
  'configured': 'Configurada',
  'active': 'Activa',
  'suspended': 'Suspendida',
  'archived': 'Archivada',
};

String branchStatusLabel(String status) {
  final key = status.trim().toLowerCase();
  if (key.isEmpty) return 'Sin estado';
  return kBranchStatusLabels[key] ?? key.replaceAll('_', ' ');
}

extension BranchSummaryStatus on BranchSummary {
  bool get isActive => status == 'active';

  /// Still being prepared; an administrator can finish it with the wizard.
  bool get isInPreparation => status == 'draft' || status == 'configured';
}

List<BranchSummary> activeBranches(Iterable<BranchSummary> branches) => [
  for (final b in branches)
    if (b.isActive) b,
];

/// Picks the branch to open by default: the assigned one when it is active,
/// otherwise the only active branch in scope. Never returns a non-active
/// branch; `null` means "let the user choose" (or nothing is operating yet).
BranchSummary? pickDefaultBranch(
  Iterable<BranchSummary> branches, {
  Iterable<String> assignedIds = const [],
}) {
  final active = activeBranches(branches);
  final assigned = assignedIds.toSet();
  if (assigned.length == 1) {
    final own = active.where((b) => b.id == assigned.first).firstOrNull;
    if (own != null) return own;
  }
  return active.length == 1 ? active.first : null;
}

String _fold(String text) => text
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u');

/// The server answers 404 "Sucursal (activa) fuera de tu ámbito/red." when a
/// branch is not active (or not in scope) for a branch-scoped endpoint.
bool isBranchScopeError(Object error) =>
    error is DlcApiException &&
    error.statusCode == 404 &&
    RegExp(r'sucursal.*fuera de tu (ambito|red)').hasMatch(_fold(error.message));

String branchNotReadyMessage(String status) => switch (status) {
  'draft' =>
    'Esta sucursal está en preparación (borrador). Completa la preparación operativa y actívala para ver su operación.',
  'configured' =>
    'Esta sucursal ya está configurada, pero aún no está activa. Actívala para ver su operación.',
  'suspended' =>
    'Esta sucursal está suspendida; su operación no está disponible.',
  'archived' => 'Esta sucursal está archivada; su operación no está disponible.',
  _ =>
    'Esta sucursal todavía no está disponible para consultar su operación. Puede estar en preparación o fuera de tu alcance.',
};

/// Code / HTTP status / correlation id for the collapsed "Detalles técnicos".
String? technicalDetails(DlcApiException e) {
  final parts = <String>[
    if (e.code != null && e.code!.isNotEmpty) 'Código ${e.code}',
    if (e.statusCode != null) 'HTTP ${e.statusCode}',
    if (e.correlationId != null && e.correlationId!.isNotEmpty)
      'Ref. ${e.correlationId}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Small status pill for branch lists (non-active branches).
class BranchStatusChip extends StatelessWidget {
  const BranchStatusChip({required this.status, super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    final inPreparation = status == 'draft' || status == 'configured';
    final fg = inPreparation ? colors.warning : colors.critical;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: inPreparation ? colors.warningContainer : colors.criticalContainer,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        branchStatusLabel(status),
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}
/// In-context state shown instead of the raw error card when the selected
/// branch is not operating yet.
class BranchNotReadyPanel extends StatelessWidget {
  const BranchNotReadyPanel({
    required this.branch,
    required this.canManage,
    this.onOpenOnboarding,
    super.key,
  });
  final BranchSummary branch;
  final bool canManage;
  final VoidCallback? onOpenOnboarding;

  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    final preparing = branch.isInPreparation;
    final showAction = preparing && canManage && onOpenOnboarding != null;
    return Card(
      key: const Key('branch-not-ready'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.construction_outlined, size: 34, color: colors.warning),
            const SizedBox(height: 10),
            Text(
              branch.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              key: const Key('branch-status-badge'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: colors.warningContainer,
                borderRadius: BorderRadius.circular(50),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: colors.warning),
                  const SizedBox(width: 5),
                  Text(
                    branchStatusLabel(branch.status),
                    style: TextStyle(
                      color: colors.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              branchNotReadyMessage(branch.status),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted),
            ),
            if (preparing && !canManage) ...[
              const SizedBox(height: 8),
              Text(
                'Un Gerente General debe completar la preparación operativa y activarla.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ],
            if (showAction) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('open-onboarding'),
                onPressed: onOpenOnboarding,
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Completar preparación'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Network landing when no branch is active in the user's scope yet.
class NoActiveBranchesPanel extends StatelessWidget {
  const NoActiveBranchesPanel({
    required this.canManage,
    this.onOpenOnboarding,
    super.key,
  });
  final bool canManage;
  final VoidCallback? onOpenOnboarding;

  @override
  Widget build(BuildContext context) {
    final colors = context.dlc;
    return Card(
      key: const Key('no-active-branches'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.store_mall_directory_outlined, size: 34, color: colors.muted),
            const SizedBox(height: 10),
            Text(
              'Aún no hay sucursales activas',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'El tablero de la red aparece cuando al menos una sucursal está activa. Las sucursales nuevas inician como borrador: completa su preparación operativa y actívalas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted),
            ),
            if (canManage && onOpenOnboarding != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('open-onboarding'),
                onPressed: onOpenOnboarding,
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Preparar una sucursal'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
